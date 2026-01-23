import express from 'express';
import { authenticate } from '../middleware/auth.middleware';
import { executeSSHCommand, closeSSHConnection } from '../services/ssh.service';
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

    console.log(`Executing SSH command for user ${userId}: ${command}`);
    if (workingDirectory) {
      console.log(`Working directory: ${workingDirectory}`);
    }

    const result = await executeSSHCommand(userId, command.trim(), 1, workingDirectory);

    res.json({
      success: true,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.code,
      timestamp: new Date().toISOString()
    });
  } catch (error: any) {
    console.error('Error executing SSH command:', error);
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

