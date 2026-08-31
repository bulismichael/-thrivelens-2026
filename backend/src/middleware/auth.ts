import { Request, Response, NextFunction } from 'express';
import { verifyToken, JWTPayload } from '../utils/jwt';
import { AuthenticationError, AuthorizationError } from '../utils/errors';
import { pool } from '../config/database';

export interface AuthenticatedRequest extends Request {
  user?: JWTPayload;
  userProfile?: any;
}

export async function authenticate(
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new AuthenticationError('No token provided');
    }

    const token = authHeader.substring(7);
    const payload = verifyToken(token);

    if (!payload || payload.type !== 'access') {
      throw new AuthenticationError('Invalid or expired token');
    }

    // Verify user still exists
    const result = await pool.query(
      'SELECT id, email FROM users WHERE id = $1',
      [payload.userId]
    );

    if (result.rows.length === 0) {
      throw new AuthenticationError('User no longer exists');
    }

    req.user = payload;
    next();
  } catch (error) {
    next(error);
  }
}

export async function optionalAuth(
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return next();
    }

    const token = authHeader.substring(7);
    const payload = verifyToken(token);

    if (payload && payload.type === 'access') {
      const result = await pool.query(
        'SELECT id, email FROM users WHERE id = $1',
        [payload.userId]
      );

      if (result.rows.length > 0) {
        req.user = payload;
      }
    }

    next();
  } catch {
    next();
  }
}

export function authorize(...roles: string[]) {
  return (req: AuthenticatedRequest, res: Response, next: NextFunction): void => {
    if (!req.user) {
      throw new AuthenticationError('Authentication required');
    }
    
    // For future role-based access control
    next();
  };
}

export async function loadUserProfile(
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    if (!req.user) {
      return next();
    }

    const result = await pool.query(
      `SELECT * FROM user_profiles WHERE user_id = $1`,
      [req.user.userId]
    );

    if (result.rows.length > 0) {
      req.userProfile = result.rows[0];
    }

    next();
  } catch (error) {
    next(error);
  }
}