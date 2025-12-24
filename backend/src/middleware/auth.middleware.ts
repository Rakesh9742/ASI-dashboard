import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

export interface AuthRequest extends Request {
  user?: {
    id: number;
    username: string;
    email: string;
    role: string;
  };
}

export const authenticate = (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const authHeader = req.headers.authorization;

    // Debug logging to help diagnose issues
    if (!authHeader) {
      console.log('❌ Auth Debug: No Authorization header found');
      console.log('   Available headers:', Object.keys(req.headers));
      return res.status(401).json({ 
        error: 'No token provided',
        hint: 'Make sure you include: Authorization: Bearer YOUR_TOKEN'
      });
    }

    if (!authHeader.startsWith('Bearer ')) {
      console.log('❌ Auth Debug: Authorization header does not start with "Bearer "');
      console.log('   Received header:', authHeader.substring(0, 20) + '...');
      console.log('   Expected format: Bearer <token>');
      return res.status(401).json({ 
        error: 'Invalid token format',
        hint: 'Authorization header must start with "Bearer " (with a space after Bearer)'
      });
    }

    const token = authHeader.substring(7); // Remove 'Bearer ' prefix

    const decoded = jwt.verify(
      token,
      process.env.JWT_SECRET || 'your-secret-key'
    ) as any;

    req.user = {
      id: decoded.id,
      username: decoded.username,
      email: decoded.email,
      role: decoded.role
    };

    next();
  } catch (error: any) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expired' });
    }
    return res.status(401).json({ error: 'Invalid token' });
  }
};

// Role-based authorization middleware
export const authorize = (...allowedRoles: string[]) => {
  return (req: AuthRequest, res: Response, next: NextFunction) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ 
        error: 'Access denied',
        message: `Required roles: ${allowedRoles.join(', ')}`
      });
    }

    next();
  };
};





