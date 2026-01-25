import express from 'express';
import { Server as HTTPServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import * as net from 'net';
import { pool } from '../config/database';
import { decrypt } from '../utils/encryption';
import jwt from 'jsonwebtoken';

let wss: WebSocketServer | null = null;

/**
 * Initialize WebSocket server for VNC proxy
 */
export function initializeVncWebSocket(server: HTTPServer) {
  wss = new WebSocketServer({ 
    server,
    path: '/api/vnc/ws'
  });

  wss.on('connection', (ws: WebSocket, req) => {
    console.log('New WebSocket connection for VNC');

    let userId: number | null = null;
    let vncSocket: net.Socket | null = null;

    // Authenticate connection via query parameter
    const url = new URL(req.url || '', `http://${req.headers.host}`);
    const token = url.searchParams.get('token');
    const vncHost = url.searchParams.get('host');
    const vncPort = url.searchParams.get('port') || '5900';

    if (!token) {
      ws.close(1008, 'Authentication required');
      return;
    }

    if (!vncHost) {
      ws.close(1008, 'VNC host required');
      return;
    }

    try {
      const jwtSecret = process.env.JWT_SECRET || 'your-secret-key';
      const decoded = jwt.verify(token, jwtSecret) as any;
      userId = decoded.id;

      console.log(`VNC WebSocket authenticated for user ${userId}, connecting to ${vncHost}:${vncPort}`);
    } catch (error) {
      console.error('VNC WebSocket authentication failed:', error);
      ws.close(1008, 'Invalid token');
      return;
    }

    // Get user's VNC password if available (optional)
    let vncPassword: string | null = null;
    pool.query(
      'SELECT vnc_password_hash FROM users WHERE id = $1',
      [userId]
    )
      .then((result) => {
        if (result.rows.length > 0 && result.rows[0].vnc_password_hash) {
          try {
            vncPassword = decrypt(result.rows[0].vnc_password_hash);
          } catch (e) {
            console.warn('Could not decrypt VNC password, proceeding without password');
          }
        }
      })
      .catch((e) => {
        console.warn('Error fetching VNC password:', e);
      });

    // Create TCP connection to VNC server
    const port = parseInt(vncPort, 10);
    if (isNaN(port) || port < 1 || port > 65535) {
      ws.close(1008, 'Invalid VNC port');
      return;
    }

    vncSocket = new net.Socket();
    
    // Connect to VNC server
    vncSocket.connect(port, vncHost, () => {
      console.log(`VNC TCP connection established to ${vncHost}:${port}`);
      
      // Send VNC protocol version handshake
      // VNC protocol starts with version string: "RFB 003.008\n"
      // But we'll let the client handle the handshake, so we just proxy the data
    });

    // Forward data from VNC server to WebSocket client
    vncSocket.on('data', (data: Buffer) => {
      if (ws.readyState === WebSocket.OPEN) {
        // Send raw binary data (VNC protocol)
        ws.send(data);
      }
    });

    // Forward data from WebSocket client to VNC server
    ws.on('message', (message: Buffer) => {
      if (vncSocket && !vncSocket.destroyed) {
        // Send raw binary data (VNC protocol)
        vncSocket.write(message);
      }
    });

    // Handle VNC socket errors
    vncSocket.on('error', (error) => {
      console.error(`VNC TCP connection error:`, error);
      if (ws.readyState === WebSocket.OPEN) {
        ws.close(1011, `VNC connection error: ${error.message}`);
      }
    });

    // Handle VNC socket close
    vncSocket.on('close', () => {
      console.log(`VNC TCP connection closed`);
      if (ws.readyState === WebSocket.OPEN) {
        ws.close(1000, 'VNC connection closed');
      }
    });

    // Handle WebSocket close
    ws.on('close', () => {
      console.log(`VNC WebSocket closed`);
      if (vncSocket && !vncSocket.destroyed) {
        vncSocket.end();
        vncSocket.destroy();
      }
    });

    // Handle WebSocket error
    ws.on('error', (error) => {
      console.error(`VNC WebSocket error:`, error);
      if (vncSocket && !vncSocket.destroyed) {
        vncSocket.end();
        vncSocket.destroy();
      }
    });
  });

  console.log('VNC WebSocket server initialized');
}

/**
 * HTTP endpoint to get VNC WebSocket URL
 */
const router = express.Router();

router.get('/ws-url', async (req, res) => {
  try {
    // This would require authentication middleware
    const protocol = req.protocol === 'https' ? 'wss' : 'ws';
    const host = req.get('host');
    const token = req.headers.authorization?.replace('Bearer ', '') || '';
    
    // Get user's VNC host from database
    // For now, return a template URL
    const wsUrl = `${protocol}://${host}/api/vnc/ws?token=${encodeURIComponent(token)}&host=HOST&port=PORT`;
    
    res.json({
      wsUrl: wsUrl
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

export default router;

