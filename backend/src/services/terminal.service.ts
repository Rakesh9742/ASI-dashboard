import { Client } from 'ssh2';
import { pool } from '../config/database';
import { decrypt, decryptNumber } from '../utils/encryption';

interface TerminalSession {
  client: Client;
  stream: any;
  userId: number;
  connected: boolean;
}

// Store active terminal sessions
const terminalSessions = new Map<string, TerminalSession>();

/**
 * Create an interactive terminal session (PTY) for a user
 */
export async function createTerminalSession(sessionId: string, userId: number): Promise<TerminalSession> {
  // Check if session already exists
  const existing = terminalSessions.get(sessionId);
  if (existing && existing.connected) {
    return existing;
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
  console.log('🔐 Terminal SSH Connection Information:');
  console.log(`   IP Address: ${ipaddress}`);
  console.log(`   Port: ${port}`);
  console.log(`   Username: ${user.ssh_user || 'Not set'}`);
  console.log(`   User ID: ${userId}`);
  console.log(`   Session ID: ${sessionId}`);
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
    let connectionTimeout: NodeJS.Timeout | null = null;
    let isResolved = false;
    let isRejected = false;
    
    // Set a timeout for the entire connection process (increased to 60 seconds)
    connectionTimeout = setTimeout(() => {
      if (!isResolved && !isRejected) {
        console.error(`Terminal connection timeout for session ${sessionId} after 60 seconds`);
        isRejected = true;
        client.end();
        reject(new Error('Terminal connection timeout - shell creation took too long (60s). The server may be slow or overloaded.'));
      }
    }, 60000); // Increased to 60 seconds to handle slow servers

    client.on('ready', () => {
      console.log(`SSH connection established for terminal session ${sessionId} to ${ipaddress}:${port}`);
      console.log(`Creating shell PTY for session ${sessionId}...`);
      
      // Create interactive shell (PTY) with timeout
      const shellStartTime = Date.now();
      let shellTimeout: NodeJS.Timeout | null = null;
      
      // Set a separate timeout for shell creation (45 seconds)
      shellTimeout = setTimeout(() => {
        if (!isResolved && !isRejected) {
          console.error(`Shell creation timeout for session ${sessionId} after 45 seconds`);
          isRejected = true;
          if (connectionTimeout) clearTimeout(connectionTimeout);
          client.end();
          reject(new Error('Shell creation timeout - server did not respond to shell request within 45 seconds.'));
        }
      }, 45000);
      
      client.shell({ 
        term: 'xterm-256color',
        cols: 80,
        rows: 24
      }, (err, stream) => {
        const shellCreationTime = Date.now() - shellStartTime;
        console.log(`Shell creation callback received for session ${sessionId} (took ${shellCreationTime}ms)`);
        
        if (shellTimeout) clearTimeout(shellTimeout);
        
        if (err) {
          console.error(`Error creating shell for session ${sessionId}:`, err);
          if (connectionTimeout) clearTimeout(connectionTimeout);
          if (!isRejected) {
            isRejected = true;
            reject(err);
          }
          return;
        }

        // Check if we already timed out
        if (isRejected) {
          console.warn(`Shell created but connection already timed out for session ${sessionId}`);
          if (stream) stream.destroy();
          return;
        }

        console.log(`Shell stream obtained for session ${sessionId}, setting up handlers...`);

        const session: TerminalSession = {
          client,
          stream,
          userId,
          connected: true
        };
        
        terminalSessions.set(sessionId, session);
        
        // Handle stream errors
        stream.on('error', (err: Error) => {
          console.error(`Terminal stream error for session ${sessionId}:`, err);
          session.connected = false;
        });

        // Handle stream close
        stream.on('close', (code: number, signal: string) => {
          console.log(`Terminal stream closed for session ${sessionId}, code: ${code}, signal: ${signal}`);
          session.connected = false;
          terminalSessions.delete(sessionId);
        });

        // Handle client errors
        client.on('error', (err) => {
          console.error(`SSH client error for session ${sessionId}:`, err);
          session.connected = false;
        });
        
        // Handle client close
        client.on('close', () => {
          console.log(`SSH connection closed for session ${sessionId}`);
          session.connected = false;
          terminalSessions.delete(sessionId);
        });
        
        // Clear connection timeout and resolve
        if (connectionTimeout) clearTimeout(connectionTimeout);
        if (!isResolved && !isRejected) {
          isResolved = true;
          console.log(`Terminal session ${sessionId} ready and resolved`);
          resolve(session);
        }
      });
    });

    client.on('error', (err) => {
      console.error(`SSH connection failed for session ${sessionId}:`, err);
      if (connectionTimeout) clearTimeout(connectionTimeout);
      if (!isRejected) {
        isRejected = true;
        reject(err);
      }
    });

    const config = {
      host: ipaddress,
      port: port,
      username: sshUser,
      password: sshPassword,
      readyTimeout: 60000, // Increased to 60s to handle slow server responses
      keepaliveInterval: 30000, // Send keepalive every 30 seconds
      keepaliveCountMax: 3, // Max keepalive failures before disconnect
      // Algorithms configuration removed - let ssh2 use defaults for better compatibility
      // Add debug logging only in development (filtered to avoid spam)
      debug: process.env.NODE_ENV === 'development' ? (info: string) => {
        // Only log important events, not every packet
        if (info.includes('CHANNEL') || info.includes('SERVICE') || info.includes('AUTH') || info.includes('ready') || info.includes('error')) {
          console.log(`[SSH Debug] ${info.substring(0, 150)}`);
        }
      } : undefined,
    };

    console.log(`Attempting SSH connection for terminal session ${sessionId} to ${ipaddress}:${port}...`);
    client.connect(config);
  });
}

/**
 * Get terminal session by ID
 */
export function getTerminalSession(sessionId: string): TerminalSession | undefined {
  return terminalSessions.get(sessionId);
}

/**
 * Close terminal session
 */
export function closeTerminalSession(sessionId: string): void {
  const session = terminalSessions.get(sessionId);
  if (session) {
    if (session.stream) {
      session.stream.end();
    }
    if (session.client) {
      session.client.end();
    }
    terminalSessions.delete(sessionId);
    console.log(`Terminal session ${sessionId} closed`);
  }
}

/**
 * Close all terminal sessions for a user
 */
export function closeTerminalSessionsForUser(userId: number): void {
  const sessionsToClose: string[] = [];
  
  terminalSessions.forEach((session, sessionId) => {
    if (session.userId === userId) {
      sessionsToClose.push(sessionId);
    }
  });
  
  sessionsToClose.forEach(sessionId => {
    closeTerminalSession(sessionId);
  });
  
  if (sessionsToClose.length > 0) {
    console.log(`Closed ${sessionsToClose.length} terminal session(s) for user ${userId}`);
  }
}

/**
 * Resize terminal
 */
export function resizeTerminal(sessionId: string, cols: number, rows: number): void {
  const session = terminalSessions.get(sessionId);
  if (session && session.stream && session.connected) {
    session.stream.setWindow(rows, cols);
  }
}

