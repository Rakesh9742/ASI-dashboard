import { Client } from 'ssh2';
import { pool } from '../config/database';
import { decrypt, decryptNumber } from '../utils/encryption';
import { getSSHConnection } from './ssh.service';

interface TerminalSession {
  client: Client;
  stream: any;
  userId: number;
  connected: boolean;
  /** When true, we own the client and must end it on close. When false, client is shared with command console. */
  ownsConnection: boolean;
}

// Store active terminal sessions
const terminalSessions = new Map<string, TerminalSession>();

/**
 * Create an interactive terminal session (PTY) for a user.
 * Reuses the existing SSH connection from the command console when available (same server, no new connection).
 */
export async function createTerminalSession(sessionId: string, userId: number): Promise<TerminalSession> {
  // Check if session already exists
  const existing = terminalSessions.get(sessionId);
  if (existing && existing.connected) {
    return existing;
  }

  // Try to reuse existing SSH connection (used by command console) so full terminal shows "existing SSH"
  try {
    const client = await getSSHConnection(userId);
    if (client) {
      const session = await openShellOnClient(sessionId, userId, client, false);
      if (session) return session;
      // Fall through to new connection if shell failed (e.g. connection dropped)
    }
  } catch (e) {
    console.log(`Reusing existing SSH for terminal failed (will create new connection): ${(e as Error).message}`);
  }

  // Get user SSH credentials and create new connection
  const userResult = await pool.query(
    'SELECT ipaddress, port, ssh_user, sshpassword_hash FROM users WHERE id = $1',
    [userId]
  );

  if (userResult.rows.length === 0) {
    throw new Error('User not found');
  }

  const user = userResult.rows[0];
  const ipaddress = process.env.SSH_IP || user.ipaddress;
  let port = 22;
  if (process.env.SSH_PORT) {
    try {
      port = decryptNumber(process.env.SSH_PORT);
    } catch (error) {
      port = user.port || 22;
    }
  } else if (user.port) {
    port = user.port;
  }

  const sshUser = user.ssh_user;
  let sshPassword = null;
  if (user.sshpassword_hash) {
    try {
      sshPassword = decrypt(user.sshpassword_hash);
    } catch (error) {
      throw new Error('Failed to decrypt SSH password');
    }
  }

  if (!ipaddress || !sshUser || !sshPassword) {
    throw new Error('SSH credentials not configured for user');
  }

  console.log(`Terminal session ${sessionId}: creating new SSH connection to ${ipaddress}:${port}`);

  const client = new Client();
  return new Promise((resolve, reject) => {
    let connectionTimeout: NodeJS.Timeout | null = null;
    let isResolved = false;
    let isRejected = false;

    connectionTimeout = setTimeout(() => {
      if (!isResolved && !isRejected) {
        isRejected = true;
        client.end();
        reject(new Error('Terminal connection timeout (60s)'));
      }
    }, 60000);

    client.on('ready', () => {
      const shellTimeout = setTimeout(() => {
        if (!isResolved && !isRejected) {
          isRejected = true;
          if (connectionTimeout) clearTimeout(connectionTimeout);
          client.end();
          reject(new Error('Shell creation timeout (45s)'));
        }
      }, 45000);

      client.shell({ term: 'xterm-256color', cols: 80, rows: 24 }, (err, stream) => {
        clearTimeout(shellTimeout);
        if (err) {
          if (connectionTimeout) clearTimeout(connectionTimeout);
          if (!isRejected) {
            isRejected = true;
            reject(err);
          }
          return;
        }
        if (isRejected) {
          if (stream) stream.destroy();
          return;
        }
        if (connectionTimeout) clearTimeout(connectionTimeout);
        const session: TerminalSession = {
          client,
          stream,
          userId,
          connected: true,
          ownsConnection: true,
        };
        terminalSessions.set(sessionId, session);
        stream.on('error', () => { session.connected = false; });
        stream.on('close', () => {
          session.connected = false;
          terminalSessions.delete(sessionId);
        });
        client.on('error', () => { session.connected = false; });
        client.on('close', () => {
          session.connected = false;
          terminalSessions.delete(sessionId);
        });
        if (!isResolved && !isRejected) {
          isResolved = true;
          console.log(`Terminal session ${sessionId} ready (new connection)`);
          resolve(session);
        }
      });
    });

    client.on('error', (err) => {
      if (connectionTimeout) clearTimeout(connectionTimeout);
      if (!isRejected) {
        isRejected = true;
        reject(err);
      }
    });

    client.connect({
      host: ipaddress,
      port: port,
      username: sshUser,
      password: sshPassword,
      readyTimeout: 60000,
      keepaliveInterval: 30000,
      keepaliveCountMax: 3,
    });
  });
}

/**
 * Open a shell on an existing SSH client (reuse connection).
 */
function openShellOnClient(
  sessionId: string,
  userId: number,
  client: Client,
  ownsConnection: boolean
): Promise<TerminalSession | null> {
  return new Promise((resolve) => {
    const shellTimeout = setTimeout(() => {
      if (!resolved) {
        resolved = true;
        resolve(null);
      }
    }, 15000);

    let resolved = false;
    client.shell({ term: 'xterm-256color', cols: 80, rows: 24 }, (err, stream) => {
      clearTimeout(shellTimeout);
      if (err || !stream) {
        if (!resolved) {
          resolved = true;
          resolve(null);
        }
        return;
      }
      if (resolved) {
        stream.destroy();
        return;
      }
      const session: TerminalSession = {
        client,
        stream,
        userId,
        connected: true,
        ownsConnection,
      };
      terminalSessions.set(sessionId, session);
      stream.on('error', () => { session.connected = false; });
      stream.on('close', () => {
        session.connected = false;
        terminalSessions.delete(sessionId);
      });
      resolved = true;
      console.log(`Terminal session ${sessionId} ready (reusing existing SSH connection)`);
      resolve(session);
    });
  });
}

/**
 * Get terminal session by ID
 */
export function getTerminalSession(sessionId: string): TerminalSession | undefined {
  return terminalSessions.get(sessionId);
}

/**
 * Close terminal session. Only ends the shell stream; ends the client only if we own the connection (not shared with command console).
 */
export function closeTerminalSession(sessionId: string): void {
  const session = terminalSessions.get(sessionId);
  if (session) {
    if (session.stream) {
      session.stream.end();
    }
    if (session.ownsConnection && session.client) {
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

