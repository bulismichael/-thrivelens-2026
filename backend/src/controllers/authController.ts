import { Response } from 'express';
import bcrypt from 'bcryptjs';
import { pool } from '../config/database';
import { generateAccessToken, generateRefreshToken, verifyToken } from '../utils/jwt';
import { AuthenticatedRequest } from '../middleware/auth';
import { AuthenticationError, ConflictError, NotFoundError } from '../utils/errors';
import { config } from '../config';

const SALT_ROUNDS = 12;

export async function register(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { email, password } = req.body;

  // Check if user already exists
  const existingUser = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
  if (existingUser.rows.length > 0) {
    throw new ConflictError('Email already registered');
  }

  // Hash password
  const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

  // Create user
  const result = await pool.query(
    `INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id, email, created_at`,
    [email, passwordHash]
  );

  const user = result.rows[0];

  // Generate tokens
  const accessToken = generateAccessToken(user.id, user.email);
  const refreshToken = generateRefreshToken(user.id, user.email);

  // Store refresh token
  await pool.query(
    `INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)`,
    [user.id, refreshToken, new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)]
  );

  res.status(201).json({
    success: true,
    data: {
      user: {
        id: user.id,
        email: user.email,
        createdAt: user.created_at,
      },
      accessToken,
      refreshToken,
    },
    message: 'Registration successful',
  });
}

export async function login(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { email, password } = req.body;

  // Find user
  const result = await pool.query('SELECT * FROM users WHERE email = $1', [email]);
  if (result.rows.length === 0) {
    throw new AuthenticationError('Invalid email or password');
  }

  const user = result.rows[0];

  // Verify password
  const isValid = await bcrypt.compare(password, user.password_hash);
  if (!isValid) {
    throw new AuthenticationError('Invalid email or password');
  }

  // Generate tokens
  const accessToken = generateAccessToken(user.id, user.email);
  const refreshToken = generateRefreshToken(user.id, user.email);

  // Store refresh token
  await pool.query(
    `INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)`,
    [user.id, refreshToken, new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)]
  );

  res.json({
    success: true,
    data: {
      user: {
        id: user.id,
        email: user.email,
        createdAt: user.created_at,
      },
      accessToken,
      refreshToken,
    },
    message: 'Login successful',
  });
}

export async function refresh(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { refreshToken } = req.body;

  // Verify refresh token
  const payload = verifyToken(refreshToken);
  if (!payload || payload.type !== 'refresh') {
    throw new AuthenticationError('Invalid refresh token');
  }

  // Check if token exists in database
  const tokenResult = await pool.query(
    'SELECT * FROM refresh_tokens WHERE token = $1 AND user_id = $2 AND expires_at > NOW()',
    [refreshToken, payload.userId]
  );

  if (tokenResult.rows.length === 0) {
    throw new AuthenticationError('Invalid or expired refresh token');
  }

  // Verify user still exists
  const userResult = await pool.query('SELECT id, email FROM users WHERE id = $1', [payload.userId]);
  if (userResult.rows.length === 0) {
    throw new AuthenticationError('User no longer exists');
  }

  const user = userResult.rows[0];

  // Generate new tokens
  const newAccessToken = generateAccessToken(user.id, user.email);
  const newRefreshToken = generateRefreshToken(user.id, user.email);

  // Delete old refresh token and store new one
  await pool.query('DELETE FROM refresh_tokens WHERE token = $1', [refreshToken]);
  await pool.query(
    `INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)`,
    [user.id, newRefreshToken, new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)]
  );

  res.json({
    success: true,
    data: {
      accessToken: newAccessToken,
      refreshToken: newRefreshToken,
    },
  });
}

export async function logout(req: AuthenticatedRequest, res: Response): Promise<void> {
  if (!req.user) {
    throw new AuthenticationError('Authentication required');
  }

  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const accessToken = authHeader.substring(7);
    const payload = verifyToken(accessToken);
    if (payload && payload.type === 'access') {
      // Delete all refresh tokens for this user (or just the current one)
      await pool.query('DELETE FROM refresh_tokens WHERE user_id = $1', [req.user.userId]);
    }
  }

  res.json({
    success: true,
    message: 'Logged out successfully',
  });
}

export async function changePassword(req: AuthenticatedRequest, res: Response): Promise<void> {
  if (!req.user) {
    throw new AuthenticationError('Authentication required');
  }

  const { currentPassword, newPassword } = req.body;

  // Get user with password hash
  const result = await pool.query('SELECT password_hash FROM users WHERE id = $1', [req.user.userId]);
  if (result.rows.length === 0) {
    throw new NotFoundError('User');
  }

  const user = result.rows[0];

  // Verify current password
  const isValid = await bcrypt.compare(currentPassword, user.password_hash);
  if (!isValid) {
    throw new AuthenticationError('Current password is incorrect');
  }

  // Hash new password
  const newPasswordHash = await bcrypt.hash(newPassword, SALT_ROUNDS);

  // Update password
  await pool.query('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2', [
    newPasswordHash,
    req.user.userId,
  ]);

  // Invalidate all refresh tokens (force re-login)
  await pool.query('DELETE FROM refresh_tokens WHERE user_id = $1', [req.user.userId]);

  res.json({
    success: true,
    message: 'Password changed successfully. Please log in again.',
  });
}

export async function getMe(req: AuthenticatedRequest, res: Response): Promise<void> {
  if (!req.user) {
    throw new AuthenticationError('Authentication required');
  }

  // Get user profile if exists
  const profileResult = await pool.query('SELECT * FROM user_profiles WHERE user_id = $1', [req.user.userId]);

  res.json({
    success: true,
    data: {
      user: {
        id: req.user.userId,
        email: req.user.email,
      },
      profile: profileResult.rows[0] || null,
    },
  });
}

export async function forgotPassword(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { email } = req.body;

  // Check if user exists (but don't reveal if they don't for security)
  const result = await pool.query('SELECT id FROM users WHERE email = $1', [email]);

  // Always return success for security (don't reveal if email exists)
  res.json({
    success: true,
    message: 'If the email exists, a password reset link has been sent',
  });

  // In a real app, you would send an email with a reset token here
  // For now, we'll just log it in development
  if (config.nodeEnv === 'development' && result.rows.length > 0) {
    console.log(`Password reset requested for: ${email}`);
  }
}

export async function resetPassword(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { token, newPassword } = req.body;

  // Verify reset token (in production, this would be a JWT or stored token)
  const payload = verifyToken(token);
  if (!payload || payload.type !== 'access') {
    throw new AuthenticationError('Invalid or expired reset token');
  }

  // Hash new password
  const passwordHash = await bcrypt.hash(newPassword, SALT_ROUNDS);

  // Update password
  await pool.query('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2', [
    passwordHash,
    payload.userId,
  ]);

  // Invalidate all refresh tokens
  await pool.query('DELETE FROM refresh_tokens WHERE user_id = $1', [payload.userId]);

  res.json({
    success: true,
    message: 'Password reset successful. Please log in with your new password.',
  });
}