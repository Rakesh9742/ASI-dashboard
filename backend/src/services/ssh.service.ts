import { Client, ConnectConfig } from 'ssh2';
import { pool } from '../config/database';
import { decrypt, decryptNumber } from '../utils/encryption';

interface SSHConnection {
  client: Client;
  connected: boolean;
  userId: number;
  lastUsed: Date;
}

// Store active SSH connections per user
export const sshConnections = new Map<number, SSHConnection>();

/**
 * Get or create SSH connection for a user
 */
export async function getSSHConnection(userId: number, forceNew: boolean = false): Promise<Client> {
  // Check if connection exists and is still active (unless forcing new connection)
  if (!forceNew) {
    const existing = sshConnections.get(userId);
    if (existing && existing.connected) {
      // Use the connection if it's marked as connected
      existing.lastUsed = new Date();
      console.log(`Reusing existing SSH connection for user ${userId}`);
      return existing.client;
    }
  } else {
    // If forcing new, close existing connection first
    const existing = sshConnections.get(userId);
    if (existing) {
      console.log(`Closing existing SSH connection for user ${userId} (forcing new)`);
      existing.client.end();
      sshConnections.delete(userId);
    }
  }

  // Get user SSH credentials from database
  const userResult = await pool.query(
    'SELECT ipaddress, port, ssh_user, sshpassword_hash FROM users WHERE id = $1',
    [userId]
  );

  if (userResult.rows.length === 0) {
    throw new Error('User not found');
  }

  const user = userResult.rows[0];
  
  // Get IP and port from environment (hardcoded) or user record
  const ipaddress = process.env.SSH_IP || user.ipaddress;
  let port = 22; // Default SSH port
  
  if (process.env.SSH_PORT) {
    try {
      port = decryptNumber(process.env.SSH_PORT);
    } catch (error) {
      console.error('Error decrypting SSH_PORT from env, using default:', error);
      port = user.port || 22;
    }
  } else if (user.port) {
    port = user.port;
  }

  // Print SSH connection information
  console.log('═══════════════════════════════════════════════════════════');
  console.log('🔐 SSH Connection Information:');
  console.log(`   IP Address: ${ipaddress}`);
  console.log(`   Port: ${port}`);
  console.log(`   Username: ${user.ssh_user || 'Not set'}`);
  console.log(`   User ID: ${userId}`);
  console.log(`   Source: ${process.env.SSH_IP ? 'Environment (.env)' : 'Database'}`);
  console.log('═══════════════════════════════════════════════════════════');

  const sshUser = user.ssh_user;
  let sshPassword = null;

  // Decrypt SSH password if available
  if (user.sshpassword_hash) {
    try {
      sshPassword = decrypt(user.sshpassword_hash);
    } catch (error) {
      console.error('Error decrypting SSH password:', error);
      throw new Error('Failed to decrypt SSH password');
    }
  }

  if (!ipaddress || !sshUser || !sshPassword) {
    throw new Error('SSH credentials not configured for user');
  }

  // Create new SSH connection
  const client = new Client();
  
  return new Promise((resolve, reject) => {
    client.on('ready', () => {
      console.log(`SSH connection established for user ${userId} to ${ipaddress}:${port}`);
      
      const connection: SSHConnection = {
        client,
        connected: true,
        userId,
        lastUsed: new Date()
      };
      
      sshConnections.set(userId, connection);
      
      // Handle connection errors
      client.on('error', (err) => {
        console.error(`SSH connection error for user ${userId}:`, err);
        const conn = sshConnections.get(userId);
        if (conn) {
          conn.connected = false;
        }
        // Remove dead connection
        sshConnections.delete(userId);
      });
      
      // Handle connection close
      client.on('close', () => {
        console.log(`SSH connection closed for user ${userId}`);
        const conn = sshConnections.get(userId);
        if (conn) {
          conn.connected = false;
        }
      });
      
      resolve(client);
    });

    client.on('error', (err) => {
      console.error(`SSH connection failed for user ${userId}:`, err);
      reject(err);
    });

    const config: ConnectConfig = {
      host: ipaddress,
      port: port,
      username: sshUser,
      password: sshPassword,
      readyTimeout: 60000, // 60 seconds timeout (increased from 20)
      keepaliveInterval: 30000, // Send keepalive every 30 seconds
      keepaliveCountMax: 3, // Max keepalive failures before disconnect
      // Algorithms configuration removed - let ssh2 use defaults for better compatibility
      // Add debug logging in development
      debug: process.env.NODE_ENV === 'development' ? console.log : undefined,
    };

    console.log(`Attempting SSH connection to ${ipaddress}:${port} for user ${userId}...`);
    client.connect(config);
    
    // Add timeout handler
    let timeoutCleared = false;
    const timeout = setTimeout(() => {
      if (!timeoutCleared) {
        console.error(`SSH connection timeout for user ${userId} to ${ipaddress}:${port}`);
        client.destroy();
        reject(new Error(`SSH connection timeout: Unable to connect to ${ipaddress}:${port} within 60 seconds. Please check network connectivity and SSH server status.`));
      }
    }, 60000);
    
    // Clear timeout on success
    client.once('ready', () => {
      timeoutCleared = true;
      clearTimeout(timeout);
    });
    
    client.once('error', () => {
      timeoutCleared = true;
      clearTimeout(timeout);
    });
  });
}

/**
 * Execute command on remote server via SSH
 */
export async function executeSSHCommand(userId: number, command: string, retries: number = 1, workingDirectory?: string): Promise<{ stdout: string; stderr: string; code: number | null }> {
  let lastError: Error | null = null;
  
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      // Only reuse existing connection (established at login), don't create new ones
      const connection = sshConnections.get(userId);
      if (!connection || !connection.connected) {
        throw new Error('SSH connection not established. Please log out and log in again to establish SSH connection.');
      }
      
      const client = connection.client;
      
      // Verify connection is still active
      if (!connection.connected) {
        throw new Error('SSH connection is not active. Please log out and log in again.');
      }

      // If working directory is provided, try to change to it, but run command anyway if it doesn't exist
      let finalCommand = command;
      if (workingDirectory && workingDirectory.trim().length > 0) {
        // Check if directory exists and change to it
        // If directory doesn't exist, run command normally (not in that directory)
        // Escape the directory path to handle spaces and special characters
        const escapedDir = workingDirectory.replace(/'/g, "'\\''");
        finalCommand = `if [ -d '${escapedDir}' ]; then cd '${escapedDir}' && ${command}; else echo "Warning: Directory '${escapedDir}' not found, running command in current directory" >&2 && ${command}; fi`;
      }

      const result = await new Promise<{ stdout: string; stderr: string; code: number | null }>((resolve, reject) => {
        // Add timeout for command execution
        const commandTimeout = setTimeout(() => {
          reject(new Error('Command execution timeout: Command took too long to execute'));
        }, 300000); // 5 minutes timeout for command execution

        client.exec(finalCommand, (err, stream) => {
          if (err) {
            clearTimeout(commandTimeout);
            // If connection error, remove the connection and retry
            if (err.message.includes('Not connected') || err.message.includes('destroyed') || err.message.includes('timeout')) {
              sshConnections.delete(userId);
              reject(err); // Will be caught and retried
              return;
            }
            reject(err);
            return;
          }

          let stdout = '';
          let stderr = '';

          stream.on('close', (code: number | null) => {
            clearTimeout(commandTimeout);
            resolve({ stdout, stderr, code });
          });

          stream.on('data', (data: Buffer) => {
            stdout += data.toString();
          });

          stream.stderr.on('data', (data: Buffer) => {
            stderr += data.toString();
          });
          
          stream.on('error', (err: Error) => {
            clearTimeout(commandTimeout);
            reject(err);
          });
        });
      });
      
      // Success - return result
      return result;
    } catch (error: any) {
      lastError = error;
      console.error(`SSH command execution attempt ${attempt + 1}/${retries + 1} failed:`, error.message);
      
      // If this was the last attempt, throw the error
      if (attempt === retries) {
        throw error;
      }
      
      // Wait a bit before retrying (exponential backoff)
      const waitTime = 2000 * (attempt + 1);
      console.log(`Retrying SSH command in ${waitTime}ms...`);
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }
  }
  
  throw lastError || new Error('Failed to execute SSH command after retries');
}

/**
 * Close SSH connection for a user
 */
export function closeSSHConnection(userId: number): void {
  const connection = sshConnections.get(userId);
  if (connection && connection.connected) {
    connection.client.end();
    sshConnections.delete(userId);
    console.log(`SSH connection closed for user ${userId}`);
  }
}

/**
 * Close all SSH connections (useful for cleanup)
 */
export function closeAllSSHConnections(): void {
  sshConnections.forEach((connection, userId) => {
    if (connection.connected) {
      connection.client.end();
    }
  });
  sshConnections.clear();
  console.log('All SSH connections closed');
}

/**
 * Clean up inactive connections (older than 1 hour)
 */
export function cleanupInactiveConnections(): void {
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
  
  sshConnections.forEach((connection, userId) => {
    if (connection.lastUsed < oneHourAgo) {
      console.log(`Closing inactive SSH connection for user ${userId}`);
      closeSSHConnection(userId);
    }
  });
}

// Run cleanup every 30 minutes
setInterval(cleanupInactiveConnections, 30 * 60 * 1000);

