import express from 'express';
import { authenticate } from '../middleware/auth.middleware';
import { executeSSHCommand, closeSSHConnection, activeShellStreams, passwordSentFlags, passwordPromptDetected } from '../services/ssh.service';
import { sshConnections } from '../services/ssh.service';
import { closeTerminalSessionsForUser } from '../services/terminal.service';

const router = express.Router();

/**
 * POST /api/ssh/execute
 * Execute a command on the remote server via SSH
 */
router.post('/execute', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { command, workingDirectory } = req.body;

    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    if (!command || typeof command !== 'string' || command.trim().length === 0) {
      return res.status(400).json({ error: 'Command is required' });
    }

    // Security: Prevent dangerous commands
    const dangerousCommands = ['rm -rf', 'mkfs', 'dd if=', '> /dev/sd', 'format'];
    const lowerCommand = command.toLowerCase();
    for (const dangerous of dangerousCommands) {
      if (lowerCommand.includes(dangerous.toLowerCase())) {
        return res.status(400).json({ error: 'Dangerous command not allowed' });
      }
    }

    // Log the command prominently
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`🚀 EXECUTING SSH COMMAND FOR USER ${userId}:`);
    console.log(`   Command: ${command}`);
    if (workingDirectory) {
      console.log(`   Working Directory: ${workingDirectory}`);
    }
    console.log('═══════════════════════════════════════════════════════════');

    // Clear password prompt flag before starting
    passwordPromptDetected.set(userId, false);

    // Start command execution
    const commandPromise = executeSSHCommand(userId, command.trim(), 1, workingDirectory);
    
    // Set up mechanism to handle password prompts
    // If password prompt is detected, return requiresPassword quickly so UI can show password dialog
    const passwordCheckPromise = new Promise<{ stdout: string; stderr: string; code: number | null; requiresPassword: boolean } | null>((resolve) => {
      let checkInterval: NodeJS.Timeout;
      let passwordDetectedTime: number | null = null;
      const MAX_WAIT_AFTER_PASSWORD_DETECTION = 15000; // Wait up to 15 seconds after password sent for command to complete
      const MAX_WAIT_FOR_PASSWORD_SEND = 4000; // Return requiresPassword after 4 seconds so UI updates fast
      
      checkInterval = setInterval(() => {
        if (passwordPromptDetected.get(userId) === true && passwordDetectedTime === null) {
          passwordDetectedTime = Date.now();
          console.log('Password prompt detected - waiting for password and command completion...');
        }
        
        // If password was detected, check timing
        if (passwordDetectedTime !== null) {
          const timeSinceDetection = Date.now() - passwordDetectedTime;
          const passwordWasSent = passwordSentFlags.get(userId) === true;
          
          // If password not sent after MAX_WAIT_FOR_PASSWORD_SEND, return early with requiresPassword
          if (!passwordWasSent && timeSinceDetection > MAX_WAIT_FOR_PASSWORD_SEND) {
            clearInterval(checkInterval);
            console.log(`Password prompt detected but not sent after ${MAX_WAIT_FOR_PASSWORD_SEND}ms - returning early to avoid timeout`);
            resolve({
              stdout: '',
              stderr: '[Password prompt detected - password required]',
              code: null,
              requiresPassword: true
            });
          } else if (passwordWasSent && timeSinceDetection > MAX_WAIT_AFTER_PASSWORD_DETECTION) {
            // Password was sent but command taking too long - let commandPromise handle it
            clearInterval(checkInterval);
            console.log('Password was sent, waiting for command to complete...');
            resolve(null); // Let commandPromise resolve normally
          }
        }
      }, 200); // Check every 200ms for faster password detection
      
      // Clean up interval if command completes first
      commandPromise.finally(() => {
        clearInterval(checkInterval);
        if (passwordDetectedTime === null) {
          // No password was needed, resolve to let command result through
          resolve(null);
        }
      });
    });

    // Handle password detection and command execution
    // If password is detected but not sent quickly, return early
    // Otherwise, wait for command to complete normally
    try {
      const passwordCheckResult = await Promise.race([
        passwordCheckPromise,
        commandPromise.then(() => null) // Command completed before password check resolved
      ]);
      
      let result;
      if (passwordCheckResult && 'requiresPassword' in passwordCheckResult && passwordCheckResult.requiresPassword) {
        // Password prompt detected but not sent in time - return early
        result = passwordCheckResult;
        console.log('Returning early due to password prompt - user needs to send password');
      } else {
        // Either no password needed, or password was sent - wait for command to complete
        result = await commandPromise;
        console.log('Command completed successfully');
      }
      
      // Log the result
      console.log('═══════════════════════════════════════════════════════════');
      console.log(`📤 SSH COMMAND RESULT FOR USER ${userId}:`);
      console.log(`   Exit Code: ${result.code}`);
      if (result.stdout) {
        console.log(`   Stdout: ${result.stdout.substring(0, 500)}${result.stdout.length > 500 ? '...' : ''}`);
      }
      if (result.stderr) {
        console.log(`   Stderr: ${result.stderr.substring(0, 500)}${result.stderr.length > 500 ? '...' : ''}`);
      }
      console.log('═══════════════════════════════════════════════════════════');

      // Check if password is requested in output
      const combinedOutput = (result.stdout || '') + (result.stderr || '');
      const passwordPromptPatterns = [
        /password:/i,
        /enter password/i,
        /password for/i,
        /sudo password/i,
        /\[sudo\] password/i,
        /password required/i,
      ];
      
      const requiresPassword = passwordPromptPatterns.some(pattern => pattern.test(combinedOutput)) || 
                               (result as any).requiresPassword === true;

      res.json({
        success: true,
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.code,
        requiresPassword: requiresPassword,
        timestamp: new Date().toISOString()
      });
    } catch (error: any) {
      console.error('Error executing SSH command:', error);
      res.status(500).json({ 
        error: error.message || 'Failed to execute command',
        details: error.code || 'SSH_ERROR'
      });
    }
  } catch (error: any) {
    console.error('Error in SSH execute route:', error);
    res.status(500).json({ 
      error: error.message || 'Failed to execute command',
      details: error.code || 'SSH_ERROR'
    });
  }
});

/**
 * POST /api/ssh/connect
 * Check SSH connection status (connection is established at login time only)
 * This endpoint only checks if connection exists, doesn't create new ones
 */
router.post('/connect', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;

    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // Check if connection exists (established at login)
    const connection = sshConnections.get(userId);
    
    if (connection && connection.connected) {
      res.json({
        success: true,
        message: 'SSH connection is active',
        connected: true
      });
    } else {
      res.status(400).json({ 
        success: false,
        error: 'SSH connection not established. Please log out and log in again to establish SSH connection.',
        connected: false
      });
    }
  } catch (error: any) {
    console.error('Error checking SSH connection:', error);
    res.status(500).json({ 
      error: error.message || 'Failed to check SSH connection',
      details: error.code || 'SSH_CONNECTION_ERROR'
    });
  }
});

/**
 * POST /api/ssh/password
 * Send password to an active SSH command that requires it
 */
router.post('/password', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { password } = req.body;

    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    if (!password || typeof password !== 'string') {
      return res.status(400).json({ error: 'Password is required' });
    }

    // Get the active shell stream for this user
    const stream = activeShellStreams.get(userId);
    if (!stream) {
      return res.status(404).json({ 
        error: 'No active command requiring password',
        requiresPassword: false
      });
    }

    // Send password to the stream
    stream.write(password + '\n');
    
    // Mark that password was sent
    passwordSentFlags.set(userId, true);
    
    console.log(`Password sent to SSH command for user ${userId}`);

    res.json({
      success: true,
      message: 'Password sent'
    });
  } catch (error: any) {
    console.error('Error sending password:', error);
    res.status(500).json({ 
      error: error.message || 'Failed to send password'
    });
  }
});

/**
 * POST /api/ssh/disconnect
 * Close SSH connection for the logged-in user
 */
router.post('/disconnect', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;

    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // Close SSH connection
    closeSSHConnection(userId);
    
    // Close all terminal sessions for this user
    closeTerminalSessionsForUser(userId);

    res.json({
      success: true,
      message: 'SSH connection and terminal sessions closed successfully'
    });
  } catch (error: any) {
    console.error('Error closing SSH connection:', error);
    res.status(500).json({ 
      error: error.message || 'Failed to close SSH connection'
    });
  }
});

export default router;

