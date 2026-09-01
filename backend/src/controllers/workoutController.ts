import { Response } from 'express';
import { pool } from '../config/database';
import { AuthenticatedRequest } from '../middleware/auth';
import { NotFoundError, AuthorizationError } from '../utils/errors';

export async function getWorkoutSessions(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const {
    startDate,
    endDate,
    page = '1',
    limit = '20',
  } = req.query;

  const pageNum = parseInt(page as string, 10);
  const limitNum = Math.min(parseInt(limit as string, 10), 100);
  const offset = (pageNum - 1) * limitNum;

  let whereClause = 'WHERE ws.user_id = $1';
  const params: any[] = [userId];
  let paramIndex = 2;

  if (startDate) {
    whereClause += ` AND ws.scheduled_date >= $${paramIndex}`;
    params.push(startDate);
    paramIndex++;
  }

  if (endDate) {
    whereClause += ` AND ws.scheduled_date <= $${paramIndex}`;
    params.push(endDate);
    paramIndex++;
  }

  const countResult = await pool.query(
    `SELECT COUNT(*) FROM workout_sessions ws ${whereClause}`,
    params
  );

  const result = await pool.query(
    `SELECT ws.*, 
      json_agg(
        json_build_object(
          'id', we.id,
          'exerciseId', we.exercise_id,
          'order', we.order,
          'notes', we.notes,
          'sets', (
            SELECT json_agg(json_build_object(
              'id', es.id,
              'setNumber', es.set_number,
              'reps', es.reps,
              'weight', es.weight,
              'duration', es.duration,
              'distance', es.distance,
              'restTime', es.rest_time,
              'completed', es.completed,
              'rpe', es.rpe
            ) ORDER BY es.set_number)
            FROM exercise_sets es WHERE es.workout_exercise_id = we.id
          )
        ) ORDER BY we.order
      ) as exercises
    FROM workout_sessions ws
    LEFT JOIN workout_exercises we ON we.session_id = ws.id
    ${whereClause}
    GROUP BY ws.id
    ORDER BY ws.scheduled_date DESC
    LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`,
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

export async function getUpcomingWorkouts(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;

  const result = await pool.query(
    `SELECT ws.*, 
      json_agg(
        json_build_object(
          'id', we.id,
          'exerciseId', we.exercise_id,
          'order', we.order,
          'notes', we.notes,
          'sets', (
            SELECT json_agg(json_build_object(
              'id', es.id,
              'setNumber', es.set_number,
              'reps', es.reps,
              'weight', es.weight,
              'duration', es.duration,
              'distance', es.distance,
              'restTime', es.rest_time,
              'completed', es.completed,
              'rpe', es.rpe
            ) ORDER BY es.set_number)
            FROM exercise_sets es WHERE es.workout_exercise_id = we.id
          )
        ) ORDER BY we.order
      ) as exercises
    FROM workout_sessions ws
    LEFT JOIN workout_exercises we ON we.session_id = ws.id
    WHERE ws.user_id = $1 AND ws.scheduled_date >= NOW() AND ws.completed_at IS NULL
    GROUP BY ws.id
    ORDER BY ws.scheduled_date ASC
    LIMIT 10`,
    [userId]
  );

  res.json({
    success: true,
    data: result.rows,
  });
}

export async function getWorkoutHistory(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const {
    page = '1',
    limit = '20',
  } = req.query;

  const pageNum = parseInt(page as string, 10);
  const limitNum = Math.min(parseInt(limit as string, 10), 100);
  const offset = (pageNum - 1) * limitNum;

  const countResult = await pool.query(
    `SELECT COUNT(*) FROM workout_sessions WHERE user_id = $1 AND completed_at IS NOT NULL`,
    [userId]
  );

  const result = await pool.query(
    `SELECT ws.*, 
      json_agg(
        json_build_object(
          'id', we.id,
          'exerciseId', we.exercise_id,
          'order', we.order,
          'notes', we.notes,
          'sets', (
            SELECT json_agg(json_build_object(
              'id', es.id,
              'setNumber', es.set_number,
              'reps', es.reps,
              'weight', es.weight,
              'duration', es.duration,
              'distance', es.distance,
              'restTime', es.rest_time,
              'completed', es.completed,
              'rpe', es.rpe
            ) ORDER BY es.set_number)
            FROM exercise_sets es WHERE es.workout_exercise_id = we.id
          )
        ) ORDER BY we.order
      ) as exercises
    FROM workout_sessions ws
    LEFT JOIN workout_exercises we ON we.session_id = ws.id
    WHERE ws.user_id = $1 AND ws.completed_at IS NOT NULL
    GROUP BY ws.id
    ORDER BY ws.completed_at DESC
    LIMIT $2 OFFSET $3`,
    [userId, limitNum, offset]
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

export async function getWorkoutSessionById(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query(
    `SELECT ws.*, 
      json_agg(
        json_build_object(
          'id', we.id,
          'exerciseId', we.exercise_id,
          'exercise', e.*,
          'order', we.order,
          'notes', we.notes,
          'sets', (
            SELECT json_agg(json_build_object(
              'id', es.id,
              'setNumber', es.set_number,
              'reps', es.reps,
              'weight', es.weight,
              'duration', es.duration,
              'distance', es.distance,
              'restTime', es.rest_time,
              'completed', es.completed,
              'rpe', es.rpe
            ) ORDER BY es.set_number)
            FROM exercise_sets es WHERE es.workout_exercise_id = we.id
          )
        ) ORDER BY we.order
      ) as exercises
    FROM workout_sessions ws
    LEFT JOIN workout_exercises we ON we.session_id = ws.id
    LEFT JOIN exercises e ON e.id = we.exercise_id
    WHERE ws.id = $1 AND ws.user_id = $2
    GROUP BY ws.id`,
    [id, userId]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Workout session');
  }

  res.json({
    success: true,
    data: result.rows[0],
  });
}

export async function createWorkoutSession(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { name, scheduledDate, exercises, notes } = req.body;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Create workout session
    const sessionResult = await client.query(
      `INSERT INTO workout_sessions (user_id, name, scheduled_date, notes) VALUES ($1, $2, $3, $4) RETURNING *`,
      [userId, name, scheduledDate, notes]
    );

    const session = sessionResult.rows[0];

    // Add exercises and sets
    for (let i = 0; i < exercises.length; i++) {
      const ex = exercises[i];
      
      const workoutExerciseResult = await client.query(
        `INSERT INTO workout_exercises (session_id, exercise_id, "order", notes) VALUES ($1, $2, $3, $4) RETURNING id`,
        [session.id, ex.exerciseId, ex.order ?? i, ex.notes]
      );

      const workoutExerciseId = workoutExerciseResult.rows[0].id;

      for (let j = 0; j < ex.sets.length; j++) {
        const set = ex.sets[j];
        await client.query(
          `INSERT INTO exercise_sets (workout_exercise_id, set_number, reps, weight, duration, distance, rest_time, completed, rpe)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
          [workoutExerciseId, j + 1, set.reps, set.weight, set.duration, set.distance, set.restTime, false, set.rpe]
        );
      }
    }

    await client.query('COMMIT');

    // Fetch the complete session
    const completeResult = await pool.query(
      `SELECT ws.*, 
        json_agg(
          json_build_object(
            'id', we.id,
            'exerciseId', we.exercise_id,
            'exercise', e.*,
            'order', we.order,
            'notes', we.notes,
            'sets', (
              SELECT json_agg(json_build_object(
                'id', es.id,
                'setNumber', es.set_number,
                'reps', es.reps,
                'weight', es.weight,
                'duration', es.duration,
                'distance', es.distance,
                'restTime', es.rest_time,
                'completed', es.completed,
                'rpe', es.rpe
              ) ORDER BY es.set_number)
              FROM exercise_sets es WHERE es.workout_exercise_id = we.id
            )
          ) ORDER BY we.order
        ) as exercises
      FROM workout_sessions ws
      LEFT JOIN workout_exercises we ON we.session_id = ws.id
      LEFT JOIN exercises e ON e.id = we.exercise_id
      WHERE ws.id = $1
      GROUP BY ws.id`,
      [session.id]
    );

    res.status(201).json({
      success: true,
      data: completeResult.rows[0],
      message: 'Workout session created successfully',
    });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function updateWorkoutSession(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;
  const { name, scheduledDate, notes } = req.body;

  const checkResult = await pool.query('SELECT id FROM workout_sessions WHERE id = $1 AND user_id = $2', [id, userId]);
  if (checkResult.rows.length === 0) {
    throw new NotFoundError('Workout session');
  }

  const result = await pool.query(
    `UPDATE workout_sessions SET
     name = COALESCE($1, name),
     scheduled_date = COALESCE($2, scheduled_date),
     notes = COALESCE($3, notes),
     updated_at = NOW()
     WHERE id = $4 AND user_id = $5
     RETURNING *`,
    [name, scheduledDate, notes, id, userId]
  );

  res.json({
    success: true,
    data: result.rows[0],
    message: 'Workout session updated successfully',
  });
}

export async function completeWorkoutSession(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const checkResult = await pool.query('SELECT * FROM workout_sessions WHERE id = $1 AND user_id = $2', [id, userId]);
  if (checkResult.rows.length === 0) {
    throw new NotFoundError('Workout session');
  }

  const session = checkResult.rows[0];
  if (session.completed_at) {
    throw new AuthorizationError('Workout session already completed');
  }

  const result = await pool.query(
    `UPDATE workout_sessions SET completed_at = NOW(), updated_at = NOW() WHERE id = $1 AND user_id = $2 RETURNING *`,
    [id, userId]
  );

  res.json({
    success: true,
    data: result.rows[0],
    message: 'Workout session marked as completed',
  });
}

export async function deleteWorkoutSession(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query('DELETE FROM workout_sessions WHERE id = $1 AND user_id = $2 RETURNING id', [id, userId]);
  if (result.rows.length === 0) {
    throw new NotFoundError('Workout session');
  }

  res.json({
    success: true,
    message: 'Workout session deleted successfully',
  });
}

export async function updateExerciseSet(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { sessionId, exerciseId, setId } = req.params;
  const userId = req.user!.userId;
  const { reps, weight, duration, distance, restTime, completed, rpe } = req.body;

  // Verify ownership
  const checkResult = await pool.query(
    `SELECT es.id FROM exercise_sets es
     JOIN workout_exercises we ON we.id = es.workout_exercise_id
     JOIN workout_sessions ws ON ws.id = we.session_id
     WHERE es.id = $1 AND we.id = $2 AND ws.id = $3 AND ws.user_id = $4`,
    [setId, exerciseId, sessionId, userId]
  );

  if (checkResult.rows.length === 0) {
    throw new NotFoundError('Exercise set');
  }

  const result = await pool.query(
    `UPDATE exercise_sets SET
     reps = COALESCE($1, reps),
     weight = COALESCE($2, weight),
     duration = COALESCE($3, duration),
     distance = COALESCE($4, distance),
     rest_time = COALESCE($5, rest_time),
     completed = COALESCE($6, completed),
     rpe = COALESCE($7, rpe)
     WHERE id = $8
     RETURNING *`,
    [reps, weight, duration, distance, restTime, completed, rpe, setId]
  );

  res.json({
    success: true,
    data: result.rows[0],
    message: 'Exercise set updated successfully',
  });
}