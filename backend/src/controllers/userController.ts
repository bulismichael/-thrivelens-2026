import { Response } from 'express';
import { pool } from '../config/database';
import { AuthenticatedRequest } from '../middleware/auth';
import { NotFoundError, AuthorizationError } from '../utils/errors';

export async function getAllUsers(req: AuthenticatedRequest, res: Response): Promise<void> {
  const page = parseInt(req.query.page as string) || 1;
  const limit = parseInt(req.query.limit as string) || 20;
  const offset = (page - 1) * limit;

  const result = await pool.query(
    `SELECT id, email, created_at FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
    [limit, offset]
  );

  const countResult = await pool.query('SELECT COUNT(*) FROM users');

  res.json({
    success: true,
    data: result.rows,
    pagination: {
      page,
      limit,
      total: parseInt(countResult.rows[0].count),
      totalPages: Math.ceil(parseInt(countResult.rows[0].count) / limit),
    },
  });
}

export async function getUserById(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;

  const result = await pool.query(
    `SELECT id, email, created_at FROM users WHERE id = $1`,
    [id]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('User');
  }

  // Users can only view their own profile unless admin
  if (req.user!.userId !== id) {
    throw new AuthorizationError('You can only view your own profile');
  }

  res.json({
    success: true,
    data: result.rows[0],
  });
}

export async function updateUser(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;

  if (req.user!.userId !== id) {
    throw new AuthorizationError('You can only update your own profile');
  }

  const { email } = req.body;

  if (email) {
    const existingUser = await pool.query('SELECT id FROM users WHERE email = $1 AND id != $2', [email, id]);
    if (existingUser.rows.length > 0) {
      throw new AuthorizationError('Email already in use');
    }
  }

  const result = await pool.query(
    `UPDATE users SET email = COALESCE($1, email), updated_at = NOW() WHERE id = $2 RETURNING id, email, created_at`,
    [email, id]
  );

  res.json({
    success: true,
    data: result.rows[0],
    message: 'User updated successfully',
  });
}

export async function deleteUser(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;

  if (req.user!.userId !== id) {
    throw new AuthorizationError('You can only delete your own account');
  }

  await pool.query('DELETE FROM users WHERE id = $1', [id]);

  res.json({
    success: true,
    message: 'Account deleted successfully',
  });
}