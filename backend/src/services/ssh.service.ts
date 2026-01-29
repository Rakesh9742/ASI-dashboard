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

// Store active shell streams for password input (key: userId, value: stream)
export const activeShellStreams = new Map<number, any>();

// Track if password was sent for a user's command (key: userId, value: boolean)
export const passwordSentFlags = new Map<number, boolean>();

// Track if password prompt was detected for a user's command (key: userId, value: boolean)
export const passwordPromptDetected = new Map<number, boolean>();

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
      // SSH connection established
      
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
      // Get or reuse existing connection (established at login)
      // If connection is lost, automatically reconnect instead of throwing error
      let connection = sshConnections.get(userId);
      if (!connection || !connection.connected) {
        console.log(`SSH connection not found or disconnected for user ${userId}, attempting to reconnect...`);
        // Reuse the existing connection if possible, or create a new one if needed
        // getSSHConnection will reuse existing connection if it exists and is connected
        await getSSHConnection(userId);
        connection = sshConnections.get(userId);
        if (!connection || !connection.connected) {
          throw new Error('Failed to establish SSH connection. Please check your SSH credentials.');
        }
      } else {
        // Connection exists and is active - reusing it
        console.log(`✅ Reusing existing SSH connection for user ${userId} (established at login)`);
      }
      
      const client = connection.client;
      
      // Verify connection is still active (double-check after getting it)
      if (!connection.connected) {
        console.log(`SSH connection marked as inactive for user ${userId}, attempting to reconnect...`);
        // Try to reconnect - getSSHConnection will create new connection if old one is dead
        await getSSHConnection(userId, true); // Force new connection
        connection = sshConnections.get(userId);
        if (!connection || !connection.connected) {
          throw new Error('SSH connection is not active and reconnection failed. Please check your SSH credentials.');
        }
      }

      // Check if command contains sudo - if so, we need to use shell with PTY
      const isSudoCommand = command.trim().toLowerCase().startsWith('sudo');
      
      // If working directory is provided, change to it before running the command
      let finalCommand = command;
      if (workingDirectory && workingDirectory.trim().length > 0) {
        // Escape the directory path to handle spaces and special characters
        const escapedDir = workingDirectory.replace(/'/g, "'\\''");
        // Change to the directory and run the command
        // Use && to ensure command only runs if cd succeeds
        // If directory doesn't exist, cd will fail and command won't run (safer)
        finalCommand = `cd '${escapedDir}' && ${command}`;
        console.log(`📁 Executing command in working directory: ${workingDirectory}`);
      } else {
        console.log(`📁 Executing command in current directory (no working directory specified)`);
      }

      const result = await new Promise<{ stdout: string; stderr: string; code: number | null }>((resolve, reject) => {
        // Add timeout for command execution
        const commandTimeout = setTimeout(() => {
          reject(new Error('Command execution timeout: Command took too long to execute'));
        }, 300000); // 5 minutes timeout for command execution

        if (isSudoCommand) {
          // Use shell with PTY for sudo commands to allow password prompts
          console.log(`Using shell PTY for sudo command: ${finalCommand}`);
          client.shell({ 
            term: 'xterm-256color',
            cols: 80,
            rows: 24
          }, (err, stream) => {
            if (err) {
              clearTimeout(commandTimeout);
              reject(err);
              return;
            }

            let stdout = '';
            let stderr = '';
            let allOutput = '';
            let passwordPrompted = false;
            let passwordSent = false;
            let commandSent = false;
            let outputComplete = false;
            let commandStarted = false;
            let completionInProgress = false; // Prevent multiple completion triggers

            // Store the stream for password input
            activeShellStreams.set(userId, stream);

            // Send the command after a short delay to ensure shell is ready
            setTimeout(() => {
              if (!commandSent) {
                commandSent = true;
                stream.write(finalCommand + '\n');
                commandStarted = true;
                console.log('Command sent to shell:', finalCommand);
              }
            }, 100);

            // Handle all output (stdout and stderr are combined in shell)
            stream.on('data', (data: Buffer) => {
              const output = data.toString();
              allOutput += output;
              
              // Log actual output for debugging (limit to avoid spam)
              const outputPreview = output.replace(/\n/g, '\\n').substring(0, Math.min(150, output.length));
              console.log(`[SSH Output] Received ${data.length} bytes. Preview: ${outputPreview}${output.length > 150 ? '...' : ''}`);
              
              // Check for password prompt
              if (!passwordPrompted && /password/i.test(output)) {
                passwordPrompted = true;
                passwordPromptDetected.set(userId, true);
                console.log('Password prompt detected in sudo command');
                stderr += '\n[Password prompt detected - password required]';
              }
              
              // Check if password was sent (check the flag set by API endpoint)
              if (passwordPrompted && !passwordSent) {
                if (passwordSentFlags.get(userId) === true) {
                  passwordSent = true;
                  console.log('Password was sent via API, waiting for command output...');
                } else {
                  // Also check if output continues after prompt (fallback detection)
                  const lines = allOutput.split('\n');
                  const promptIndex = lines.findIndex(line => /password/i.test(line));
                  if (promptIndex >= 0 && lines.length > promptIndex + 1) {
                    const outputAfterPrompt = lines.slice(promptIndex + 1).join('\n');
                    if (outputAfterPrompt.trim().length > 0 && !outputAfterPrompt.includes('password')) {
                      passwordSent = true;
                      console.log('Password appears to have been sent (detected from output), waiting for command output...');
                    }
                  }
                }
              }
              
              // Collect output
              stdout += output;
            });

            // Monitor for command completion
            // Look for shell prompt patterns or wait for timeout
            let lastActivityTime = Date.now();
            let lastOutputLength = 0;
            // Use faster polling when password is detected (100ms) vs normal (500ms)
            let checkInterval = 500;
            let completionCheckInterval: NodeJS.Timeout;
            
            const runCompletionCheck = () => {
              const timeSinceLastActivity = Date.now() - lastActivityTime;
              const currentOutputLength = allOutput.length;
              const outputChanged = currentOutputLength !== lastOutputLength;
              lastOutputLength = currentOutputLength;
              
              // Update last activity if output changed
              if (outputChanged) {
                lastActivityTime = Date.now();
              }
              
              // Speed up polling if password is prompted but not sent yet
              if (passwordPrompted && !passwordSent && checkInterval > 100) {
                clearInterval(completionCheckInterval);
                checkInterval = 100;
                completionCheckInterval = setInterval(runCompletionCheck, checkInterval);
                return;
              }
              
              // Check if we see a shell prompt (indicates command finished)
              const lines = allOutput.split('\n');
              const lastLine = lines[lines.length - 1] || '';
              const secondLastLine = lines[lines.length - 2] || '';
              // Lenient prompt: user@host(path):path$ or user@host:[...]$ (dots, parens, brackets)
              const promptRegex = /^[\w@.\-()]+@[\w.\-()]+[:\/][\w\/~\[\]\.\-]*[#$>]\s*$/;
              const hasPrompt = promptRegex.test(lastLine.trim());
              
              // More sophisticated completion detection:
              // 1. If password was prompted but not sent, wait longer (don't resolve yet)
              // 2. If password was sent, wait for actual command output
              // 3. If we see a prompt after the command, command is done
              // 4. If no activity for extended period after password sent, command might be done
              
              let shouldComplete = false;
              
              if (passwordPrompted && !passwordSent) {
                // Password prompted but not sent yet - wait longer (up to 120 seconds)
                // Increased from 60s to handle slow network and user input
                if (timeSinceLastActivity > 120000) {
                  console.log('Timeout waiting for password to be sent');
                  shouldComplete = true;
                }
              } else if (passwordPrompted && passwordSent) {
                // Password was sent - wait for command to complete
                // Look for prompt after command output, or wait for extended period
                const commandIndex = allOutput.indexOf(finalCommand);
                
                // Check if we have output after the command (excluding the command echo itself)
                const lines = allOutput.split('\n');
                const commandLineIndex = lines.findIndex(line => line.includes(finalCommand.split(' ')[0]));
                
                if (commandLineIndex >= 0) {
                  // Get all lines after the command
                  const linesAfterCommand = lines.slice(commandLineIndex + 1);
                  const outputAfterCommand = linesAfterCommand.join('\n');
                  
                  // Check for various completion indicators:
                  // 1. Shell prompt appears (user@host:path$)
                  // 2. Command output followed by prompt
                  // 3. Error messages that indicate completion
                  const hasOutputAfterCommand = outputAfterCommand.trim().length > 0;
                  const lastFewLines = linesAfterCommand.slice(-3).join('\n');
                  const promptRegex = /^[\w@.\-()]+@[\w.\-()]+[:\/][\w\/~\[\]\.\-]*[#$>]\s*$/;
                  const hasPromptInLastLines = promptRegex.test(lastFewLines.trim());
                  
                  // More lenient prompt detection - check if any line looks like a prompt (user@host:path$)
                  const anyLineIsPrompt = linesAfterCommand.some(line => {
                    const trimmed = line.trim();
                    return promptRegex.test(trimmed) && trimmed.length < 150;
                  });
                  
                  // Only log completion check details if not already completing (to reduce log spam)
                  if (!completionInProgress && timeSinceLastActivity % 5000 < 200) {
                    // Log every ~5 seconds to reduce spam
                    console.log(`[Completion Check] Password sent. Output after command: ${outputAfterCommand.length} chars, Has prompt: ${hasPromptInLastLines || anyLineIsPrompt}, Time since activity: ${timeSinceLastActivity}ms`);
                  }
                  
                  // Check for completion indicators in the output
                  const hasDoneMessage = /Done\./i.test(outputAfterCommand) || /done\./i.test(allOutput);
                  const hasSuccessMessage = /success/i.test(outputAfterCommand) || /completed/i.test(outputAfterCommand);
                  
                  // Complete if:
                  // 1. We see a prompt in the output (command finished)
                  // 2. We see "Done." or success message (command explicitly finished) — no wait
                  // 3. We have "Done." and 2s+ inactivity (fast path so UI updates quickly)
                  // 4. No activity for 60 seconds (command likely finished or hung)
                  // 5. Substantial output and no activity for 8 seconds (reduced from 30s for faster UI)
                  if (anyLineIsPrompt && hasOutputAfterCommand) {
                    if (!completionInProgress) {
                      console.log('Command completion detected: Shell prompt found after command output');
                    }
                    shouldComplete = true;
                  } else if (hasDoneMessage || hasSuccessMessage) {
                    if (!completionInProgress) {
                      console.log(`Command completion detected: Found completion message (Done/Success)`);
                    }
                    shouldComplete = true;
                  } else if (hasDoneMessage && timeSinceLastActivity > 2000) {
                    // Fast path: "Done." in output and 2s no new data — complete so UI updates quickly
                    if (!completionInProgress) {
                      console.log('Command completion detected: Done. with 2s inactivity');
                    }
                    shouldComplete = true;
                  } else if (timeSinceLastActivity > 60000) {
                    console.log('Command completion detected: Timeout (60s) after password sent');
                    shouldComplete = true;
                  } else if (hasOutputAfterCommand && outputAfterCommand.length > 100 && timeSinceLastActivity > 8000) {
                    // Substantial output and 8s inactivity — likely done (reduced from 30s for faster UI)
                    if (!completionInProgress) {
                      console.log('Command completion detected: Substantial output with 8s inactivity');
                    }
                    shouldComplete = true;
                  }
                } else {
                  // Command line not found in output — still check for "Done." so we don't wait 30s
                  const hasDoneInAll = /Done\./i.test(allOutput) || /done\./i.test(allOutput);
                  if (hasDoneInAll && timeSinceLastActivity > 2000) {
                    if (!completionInProgress) {
                      console.log('Command completion detected: Done. in output (command line not found)');
                    }
                    shouldComplete = true;
                  } else if (timeSinceLastActivity > 15000) {
                    console.log('Command completion detected: Timeout (15s) - command not found in output');
                    shouldComplete = true;
                  }
                }
              } else {
                // No password prompt - normal command completion
                if (hasPrompt && allOutput.length > 0) {
                  shouldComplete = true;
                } else if (timeSinceLastActivity > 5000 && allOutput.length > 0) {
                  // Wait 5 seconds of no activity for non-sudo commands
                  shouldComplete = true;
                }
              }
              
              if (shouldComplete && !outputComplete && !completionInProgress && commandStarted) {
                // Don't resolve immediately - wait a bit more to capture any remaining output
                // This is especially important for commands that output data after completion
                completionInProgress = true; // Set flag to prevent multiple triggers
                setTimeout(() => {
                  if (!outputComplete) {
                    outputComplete = true;
                    clearInterval(completionCheckInterval);
                    clearTimeout(commandTimeout);
                    
                    console.log('═══════════════════════════════════════════════════════════');
                    console.log('✅ Command completion detected (after final wait)');
                    console.log(`   Output length: ${allOutput.length} characters`);
                    console.log(`   Password prompted: ${passwordPrompted}`);
                    console.log(`   Password sent: ${passwordSent}`);
                    console.log(`   Time since last activity: ${timeSinceLastActivity}ms`);
                    console.log(`   Last 10 lines of output:`);
                    const lastLines = allOutput.split('\n').slice(-10);
                    lastLines.forEach((line, idx) => {
                      console.log(`     ${idx + 1}. ${line.substring(0, 150)}`);
                    });
                    console.log('═══════════════════════════════════════════════════════════');
                    
                    // Log raw output before cleaning for debugging
                    console.log('═══════════════════════════════════════════════════════════');
                    console.log('📋 RAW OUTPUT BEFORE CLEANING:');
                    console.log(`   Total length: ${allOutput.length} characters`);
                    console.log(`   First 1500 chars:\n${allOutput.substring(0, Math.min(1500, allOutput.length))}`);
                    console.log(`   Last 1500 chars:\n${allOutput.substring(Math.max(0, allOutput.length - 1500))}`);
                    console.log('═══════════════════════════════════════════════════════════');
                    
                    // Clean up output - remove command echo and prompt
                    let cleanOutput = allOutput;
                    // Remove the command line if it was echoed (be more careful - only exact line matches)
                    const commandLines = finalCommand.split('\n');
                    for (const cmdLine of commandLines) {
                      // Only remove if it's a complete line match
                      const escapedCmd = cmdLine.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                      cleanOutput = cleanOutput.replace(new RegExp(`^${escapedCmd}\\s*$`, 'gm'), '');
                    }
                    // Remove prompt lines (but keep actual command output)
                    cleanOutput = cleanOutput.split('\n')
                      .filter(line => {
                        const trimmed = line.trim();
                        // Remove shell prompts (lenient: user@host(path):path$)
                        if (/^[\w@.\-()]+@[\w.\-()]+[:\/][\w\/~\[\]\.\-]*[#$>]\s*$/.test(trimmed)) {
                          return false;
                        }
                        // Remove "Last login" messages
                        if (trimmed.includes('Last login:')) {
                          return false;
                        }
                        // Remove password prompts
                        if (/\[sudo\] password for/i.test(trimmed)) {
                          return false;
                        }
                        // Remove command echo (if it appears as a standalone line)
                        if (trimmed.includes('sudo python3') && trimmed.length > 100) {
                          return false;
                        }
                        // Remove DISPLAY variable warnings (harmless shell warnings, not actual errors)
                        if (/^DISPLAY:\s*Undefined variable\.?$/i.test(trimmed)) {
                          return false;
                        }
                        // Keep everything else (including actual script output)
                        return true;
                      })
                      .join('\n')
                      .trim();
                    
                    // Log cleaned output for debugging
                    console.log('═══════════════════════════════════════════════════════════');
                    console.log('📋 CLEANED OUTPUT:');
                    console.log(`   Length: ${cleanOutput.length} characters`);
                    console.log(`   Content:\n${cleanOutput.substring(0, Math.min(2000, cleanOutput.length))}${cleanOutput.length > 2000 ? '\n... (truncated)' : ''}`);
                    console.log('═══════════════════════════════════════════════════════════');
                    
                    stdout = cleanOutput;
                    
                    // Determine exit code - if password was prompted but command didn't complete, it's an error
                    // Otherwise, check if there are error indicators in output
                    let exitCode = 0;
                    if (passwordPrompted && !passwordSent) {
                      exitCode = 1; // Password required but not provided
                    } else if (cleanOutput.toLowerCase().includes('error') || cleanOutput.toLowerCase().includes('failed')) {
                      exitCode = 1;
                    } else if (cleanOutput.toLowerCase().includes('done.') || cleanOutput.toLowerCase().includes('success')) {
                      exitCode = 0; // Success indicators
                    }
                    
                    resolve({ stdout, stderr, code: exitCode });
                  }
                }, 1500); // Wait 1.5s after completion detection so UI updates quickly
              }
            };
            
            // Start the completion check interval
            completionCheckInterval = setInterval(runCompletionCheck, checkInterval);

            stream.on('close', (code: number | null) => {
              console.log(`[SSH Stream] Stream closed with code: ${code}`);
              console.log(`[SSH Stream] Final output length: ${allOutput.length} characters`);
              
              // Wait a bit more to ensure all data is captured
              setTimeout(() => {
                    clearInterval(completionCheckInterval);
                    clearTimeout(commandTimeout);
                    activeShellStreams.delete(userId); // Clean up
                    passwordSentFlags.delete(userId); // Clean up password flag
                    passwordPromptDetected.delete(userId); // Clean up password prompt flag
                if (!outputComplete) {
                  outputComplete = true;
                  console.log('═══════════════════════════════════════════════════════════');
                  console.log('✅ Command completion detected (stream closed)');
                  console.log(`   Final output length: ${allOutput.length} characters`);
                  console.log('═══════════════════════════════════════════════════════════');
                  
                  // Clean up output - remove command echo and prompt
                  let cleanOutput = allOutput;
                  // Remove the command line if it was echoed
                  const commandLines = finalCommand.split('\n');
                  for (const cmdLine of commandLines) {
                    const escapedCmd = cmdLine.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    cleanOutput = cleanOutput.replace(new RegExp(`^${escapedCmd}\\s*$`, 'gm'), '');
                  }
                  // Remove prompt lines (but keep actual command output)
                  cleanOutput = cleanOutput.split('\n')
                    .filter(line => {
                      const trimmed = line.trim();
                      // Remove shell prompts (lenient: user@host(path):path$)
                      if (/^[\w@.\-()]+@[\w.\-()]+[:\/][\w\/~\[\]\.\-]*[#$>]\s*$/.test(trimmed)) {
                        return false;
                      }
                      // Remove "Last login" messages
                      if (trimmed.includes('Last login:')) {
                        return false;
                      }
                      // Remove password prompts
                      if (/\[sudo\] password for/i.test(trimmed)) {
                        return false;
                      }
                      // Remove command echo (if it appears as a standalone line)
                      if (trimmed.includes('sudo python3') && trimmed.length > 100) {
                        return false;
                      }
                      // Keep everything else (including actual script output)
                      return true;
                    })
                    .join('\n')
                    .trim();
                  
                  stdout = cleanOutput;
                  
                  // Determine exit code
                  let exitCode = code || 0;
                  if (passwordPrompted && !passwordSent) {
                    exitCode = 1;
                  } else if (cleanOutput.toLowerCase().includes('error') || cleanOutput.toLowerCase().includes('failed')) {
                    exitCode = 1;
                  } else if (cleanOutput.toLowerCase().includes('done.') || cleanOutput.toLowerCase().includes('success')) {
                    exitCode = 0;
                  }
                  
                  resolve({ stdout, stderr, code: exitCode });
                }
              }, 2000); // Wait 2 seconds after stream close to capture any final data
            });
            
            stream.on('error', (err: Error) => {
                    clearInterval(completionCheckInterval);
                    clearTimeout(commandTimeout);
                    activeShellStreams.delete(userId); // Clean up
                    passwordSentFlags.delete(userId); // Clean up password flag
                    passwordPromptDetected.delete(userId); // Clean up password prompt flag
              reject(err);
            });
          });
        } else {
          // Use exec for non-sudo commands (faster, no PTY needed)
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
        }
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

