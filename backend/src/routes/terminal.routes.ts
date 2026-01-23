import express from 'express';
import { Server as HTTPServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { authenticate } from '../middleware/auth.middleware';
import { createTerminalSession, getTerminalSession, closeTerminalSession, resizeTerminal } from '../services/terminal.service';
import jwt from 'jsonwebtoken';

let wss: WebSocketServer | null = null;

/**
 * Initialize WebSocket server for terminal
 */
export function initializeTerminalWebSocket(server: HTTPServer) {
  wss = new WebSocketServer({ 
    server,
    path: '/api/terminal/ws'
  });

  wss.on('connection', (ws: WebSocket, req) => {
    console.log('New WebSocket connection for terminal');

    let sessionId: string | null = null;
    let userId: number | null = null;

    // Authenticate connection via query parameter or header
    const url = new URL(req.url || '', `http://${req.headers.host}`);
    const token = url.searchParams.get('token') || req.headers.authorization?.replace('Bearer ', '');

    if (!token) {
      ws.close(1008, 'Authentication required');
      return;
    }

    try {
      const jwtSecret = process.env.JWT_SECRET || 'your-secret-key';
      const decoded = jwt.verify(token, jwtSecret) as any;
      userId = decoded.id;
      sessionId = `terminal_${userId}_${Date.now()}`;

      console.log(`Terminal WebSocket authenticated for user ${userId}, session: ${sessionId}`);
    } catch (error) {
      console.error('Terminal WebSocket authentication failed:', error);
      ws.close(1008, 'Invalid token');
      return;
    }

    // Create terminal session
    createTerminalSession(sessionId, userId!)
      .then((session) => {
        console.log(`Terminal session created successfully for ${sessionId}`);
        
        // Set up data handler IMMEDIATELY to catch all output
        // This must be done before any other operations
        session.stream.on('data', (data: Buffer) => {
          if (ws.readyState === WebSocket.OPEN) {
            const output = data.toString();
            // Only log first few outputs to avoid spam
            if (!session.stream.listenerCount || session.stream.listenerCount('data') === 1) {
              console.log(`Terminal output received (${output.length} bytes): ${output.substring(0, 100)}`);
            }
            ws.send(JSON.stringify({
              type: 'output',
              data: output
            }));
          } else {
            console.warn(`WebSocket not open, cannot send output. State: ${ws.readyState}`);
          }
        });

        // Handle stream stderr
        if (session.stream.stderr) {
          session.stream.stderr.on('data', (data: Buffer) => {
            if (ws.readyState === WebSocket.OPEN) {
              ws.send(JSON.stringify({
                type: 'output',
                data: data.toString()
              }));
            }
          });
        }

        // Handle client messages
        ws.on('message', (message: string) => {
          try {
            const msg = JSON.parse(message.toString());
            
            if (msg.type === 'input') {
              // Send input to terminal
              if (session.stream && session.connected) {
                console.log(`Sending input to terminal: ${JSON.stringify(msg.data)}`);
                session.stream.write(msg.data);
              } else {
                console.error('Cannot send input: stream not connected');
                ws.send(JSON.stringify({
                  type: 'error',
                  message: 'Terminal stream not connected'
                }));
              }
            } else if (msg.type === 'resize') {
              // Resize terminal
              resizeTerminal(sessionId!, msg.cols || 80, msg.rows || 24);
            }
          } catch (error) {
            console.error('Error handling terminal message:', error);
          }
        });

        // Handle WebSocket close
        ws.on('close', () => {
          console.log(`Terminal WebSocket closed for session ${sessionId}`);
          closeTerminalSession(sessionId!);
        });

        // Handle WebSocket error
        ws.on('error', (error) => {
          console.error(`Terminal WebSocket error for session ${sessionId}:`, error);
          closeTerminalSession(sessionId!);
        });

        // Send connection success
        ws.send(JSON.stringify({
          type: 'connected',
          sessionId: sessionId
        }));

        // Send connection success immediately
        console.log(`Sending connection success message for session ${sessionId}`);
        
        // Wait a bit for shell to initialize, then send a newline to trigger prompt
        // Reduced delay from 800ms to 300ms for faster response
        setTimeout(() => {
          if (session.connected && ws.readyState === WebSocket.OPEN) {
            console.log(`Sending initial newline to trigger shell prompt for session ${sessionId}`);
            // Send a newline to trigger the shell prompt
            session.stream.write('\r\n');
          } else {
            console.warn(`Cannot send initial newline: connected=${session.connected}, wsState=${ws.readyState}`);
          }
        }, 300);
      })
      .catch((error) => {
        console.error('Error creating terminal session:', error);
        ws.send(JSON.stringify({
          type: 'error',
          message: error.message || 'Failed to create terminal session'
        }));
        ws.close();
      });
  });

  console.log('Terminal WebSocket server initialized');
}

/**
 * HTTP endpoint to get terminal WebSocket URL
 */
const router = express.Router();

router.get('/ws-url', authenticate, (req, res) => {
  const protocol = req.protocol === 'https' ? 'wss' : 'ws';
  const host = req.get('host');
  const token = req.headers.authorization?.replace('Bearer ', '') || '';
  
  const wsUrl = `${protocol}://${host}/api/terminal/ws?token=${encodeURIComponent(token)}`;
  
  res.json({
    wsUrl: wsUrl
  });
});

export default router;

