import { Response } from 'express';
import { pool } from '../config/database';
import { AuthenticatedRequest } from '../middleware/auth';
import { NotFoundError } from '../utils/errors';

const BODY_PARTS = ['chest', 'back', 'shoulders', 'arms', 'legs', 'core', 'cardio', 'full_body'];

export async function getExercises(req: AuthenticatedRequest, res: Response): Promise<void> {
  const {
    bodyPart,
    difficulty,
    isCustom,
    search,
    page = '1',
    limit = '50',
  } = req.query;

  const pageNum = parseInt(page as string, 10);
  const limitNum = Math.min(parseInt(limit as string, 10), 100);
  const offset = (pageNum - 1) * limitNum;

  let whereClause = 'WHERE 1=1';
  const params: any[] = [];
  let paramIndex = 1;

  if (bodyPart) {
    whereClause += ` AND body_part = $${paramIndex}`;
    params.push(bodyPart);
    paramIndex++;
  }

  if (difficulty) {
    whereClause += ` AND difficulty = $${paramIndex}`;
    params.push(difficulty);
    paramIndex++;
  }

  if (isCustom !== undefined) {
    whereClause += ` AND is_custom = $${paramIndex}`;
    params.push(isCustom === 'true');
    paramIndex++;
  } else if (!req.user) {
    // Non-authenticated users only see non-custom exercises
    whereClause += ` AND is_custom = false`;
  } else {
    // Authenticated users see their custom exercises and public ones
    whereClause += ` AND (is_custom = false OR user_id = $${paramIndex})`;
    params.push(req.user.userId);
    paramIndex++;
  }

  if (search) {
    whereClause += ` AND (name ILIKE $${paramIndex} OR description ILIKE $${paramIndex})`;
    params.push(`%${search}%`);
    paramIndex++;
  }

  const countResult = await pool.query(
    `SELECT COUNT(*) FROM exercises ${whereClause}`,
    params
  );

  const result = await pool.query(
    `SELECT * FROM exercises ${whereClause} ORDER BY is_custom, name LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`,
    [...params, limitNum, offset]
  );

  res.json({
    success: true,
    data: result.rows,
    pagination: {
      page: pageNum,
      limit: limitNum,
      total: parseInt(countResult.rows[0].count),
      totalPages: Math.ceil(parseInt(countResult.rows[0].count) / limitNum),
    },
  });
}

export async function getBodyParts(req: AuthenticatedRequest, res: Response): Promise<void> {
  const result = await pool.query(
    `SELECT body_part, COUNT(*) as count FROM exercises WHERE is_custom = false GROUP BY body_part ORDER BY body_part`
  );

  const bodyParts = BODY_PARTS.map(bp => {
    const found = result.rows.find(r => r.body_part === bp);
    return { name: bp, count: parseInt(found?.count || '0') };
  });

  res.json({
    success: true,
    data: bodyParts,
  });
}

export async function getExerciseById(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;

  let query = 'SELECT * FROM exercises WHERE id = $1';
  const params = [id];

  if (req.user) {
    query += ' AND (is_custom = false OR user_id = $2)';
    params.push(req.user.userId);
  } else {
    query += ' AND is_custom = false';
  }

  const result = await pool.query(query, params);

  if (result.rows.length === 0) {
    throw new NotFoundError('Exercise');
  }

  res.json({
    success: true,
    data: result.rows[0],
  });
}

export async function createExercise(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const {
    name,
    description,
    bodyPart,
    equipment = [],
    difficulty,
    instructions = [],
    muscleGroups = [],
    videoUrl,
    imageUrl,
  } = req.body;

  const result = await pool.query(
    `INSERT INTO exercises (name, description, body_part, equipment, difficulty, instructions, muscle_groups, video_url, image_url, is_custom, user_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, true, $10)
     RETURNING *`,
    [name, description, bodyPart, equipment, difficulty, instructions, muscleGroups, videoUrl, imageUrl, userId]
  );

  res.status(201).json({
    success: true,
    data: result.rows[0],
    message: 'Custom exercise created successfully',
  });
}

export async function updateExercise(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  // Check ownership
  const checkResult = await pool.query('SELECT * FROM exercises WHERE id = $1 AND user_id = $2 AND is_custom = true', [id, userId]);
  if (checkResult.rows.length === 0) {
    throw new NotFoundError('Custom exercise');
  }

  const {
    name,
    description,
    bodyPart,
    equipment,
    difficulty,
    instructions,
    muscleGroups,
    videoUrl,
    imageUrl,
  } = req.body;

  const result = await pool.query(
    `UPDATE exercises SET
     name = COALESCE($1, name),
     description = COALESCE($2, description),
     body_part = COALESCE($3, body_part),
     equipment = COALESCE($4, equipment),
     difficulty = COALESCE($5, difficulty),
     instructions = COALESCE($6, instructions),
     muscle_groups = COALESCE($7, muscle_groups),
     video_url = COALESCE($8, video_url),
     image_url = COALESCE($9, image_url),
     updated_at = NOW()
     WHERE id = $10 AND user_id = $11 AND is_custom = true
     RETURNING *`,
    [name, description, bodyPart, equipment, difficulty, instructions, muscleGroups, videoUrl, imageUrl, id, userId]
  );

  res.json({
    success: true,
    data: result.rows[0],
    message: 'Exercise updated successfully',
  });
}

export async function deleteExercise(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query(
    'DELETE FROM exercises WHERE id = $1 AND user_id = $2 AND is_custom = true RETURNING id',
    [id, userId]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Custom exercise');
  }

  res.json({
    success: true,
    message: 'Exercise deleted successfully',
  });
}