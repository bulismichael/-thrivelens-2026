import { Response } from 'express';
import { pool } from '../config/database';
import { AuthenticatedRequest } from '../middleware/auth';
import { NotFoundError } from '../utils/errors';
import { config } from '../config';
import OpenAI from 'openai';

const openai = new OpenAI({ apiKey: config.openai.apiKey });

export async function getWorkoutPlans(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;

  const result = await pool.query(
    `SELECT wp.*,
      json_agg(
        json_build_object(
          'id', pws.id,
          'dayOfWeek', pws.day_of_week,
          'name', pws.name,
          'estimatedDuration', pws.estimated_duration,
          'exercises', (
            SELECT json_agg(json_build_object(
              'id', pwe.id,
              'exerciseId', pwe.exercise_id,
              'sets', pwe.sets,
              'reps', pwe.reps,
              'restTime', pwe.rest_time,
              'order', pwe."order"
            ) ORDER BY pwe."order")
            FROM planned_workout_exercises pwe WHERE pwe.planned_session_id = pws.id
          )
        ) ORDER BY pws."order"
      ) as sessions
    FROM workout_plans wp
    LEFT JOIN planned_workout_sessions pws ON pws.plan_id = wp.id
    WHERE wp.user_id = $1
    GROUP BY wp.id
    ORDER BY wp.created_at DESC`,
    [userId]
  );

  res.json({
    success: true,
    data: result.rows,
  });
}

export async function getActiveWorkoutPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;

  const result = await pool.query(
    `SELECT wp.*,
      json_agg(
        json_build_object(
          'id', pws.id,
          'dayOfWeek', pws.day_of_week,
          'name', pws.name,
          'estimatedDuration', pws.estimated_duration,
          'exercises', (
            SELECT json_agg(json_build_object(
              'id', pwe.id,
              'exerciseId', pwe.exercise_id,
              'sets', pwe.sets,
              'reps', pwe.reps,
              'restTime', pwe.rest_time,
              'order', pwe."order"
            ) ORDER BY pwe."order")
            FROM planned_workout_exercises pwe WHERE pwe.planned_session_id = pws.id
          )
        ) ORDER BY pws."order"
      ) as sessions
    FROM workout_plans wp
    LEFT JOIN planned_workout_sessions pws ON pws.plan_id = wp.id
    WHERE wp.user_id = $1 AND wp.is_active = true
    GROUP BY wp.id`,
    [userId]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Active workout plan');
  }

  res.json({
    success: true,
    data: result.rows[0],
  });
}

export async function getWorkoutPlanById(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query(
    `SELECT wp.*,
      json_agg(
        json_build_object(
          'id', pws.id,
          'dayOfWeek', pws.day_of_week,
          'name', pws.name,
          'estimatedDuration', pws.estimated_duration,
          'exercises', (
            SELECT json_agg(json_build_object(
              'id', pwe.id,
              'exerciseId', pwe.exercise_id,
              'sets', pwe.sets,
              'reps', pwe.reps,
              'restTime', pwe.rest_time,
              'order', pwe."order"
            ) ORDER BY pwe."order")
            FROM planned_workout_exercises pwe WHERE pwe.planned_session_id = pws.id
          )
        ) ORDER BY pws."order"
      ) as sessions
    FROM workout_plans wp
    LEFT JOIN planned_workout_sessions pws ON pws.plan_id = wp.id
    WHERE wp.id = $1 AND wp.user_id = $2
    GROUP BY wp.id`,
    [id, userId]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Workout plan');
  }

  res.json({
    success: true,
    data: result.rows[0],
  });
}

export async function createWorkoutPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { name, description, daysPerWeek, sessions } = req.body;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const planResult = await client.query(
      `INSERT INTO workout_plans (user_id, name, description, days_per_week)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [userId, name, description, daysPerWeek]
    );

    const plan = planResult.rows[0];

    for (let i = 0; i < sessions.length; i++) {
      const session = sessions[i];
      
      const sessionResult = await client.query(
        `INSERT INTO planned_workout_sessions (plan_id, day_of_week, name, estimated_duration, "order")
         VALUES ($1, $2, $3, $4, $5) RETURNING id`,
        [plan.id, session.dayOfWeek, session.name, session.estimatedDuration, i]
      );

      const plannedSessionId = sessionResult.rows[0].id;

      if (session.exercises && Array.isArray(session.exercises)) {
        for (let j = 0; j < session.exercises.length; j++) {
          const exercise = session.exercises[j];
          await client.query(
            `INSERT INTO planned_workout_exercises (planned_session_id, exercise_id, sets, reps, rest_time, "order")
             VALUES ($1, $2, $3, $4, $5, $6)`,
            [plannedSessionId, exercise.exerciseId, exercise.sets, exercise.reps, exercise.restTime, j]
          );
        }
      }
    }

    await client.query('COMMIT');

    // Fetch complete plan
    const completeResult = await pool.query(
      `SELECT wp.*,
        json_agg(
          json_build_object(
            'id', pws.id,
            'dayOfWeek', pws.day_of_week,
            'name', pws.name,
            'estimatedDuration', pws.estimated_duration,
            'exercises', (
              SELECT json_agg(json_build_object(
                'id', pwe.id,
                'exerciseId', pwe.exercise_id,
                'sets', pwe.sets,
                'reps', pwe.reps,
                'restTime', pwe.rest_time,
                'order', pwe."order"
              ) ORDER BY pwe."order")
              FROM planned_workout_exercises pwe WHERE pwe.planned_session_id = pws.id
            )
          ) ORDER BY pws."order"
        ) as sessions
      FROM workout_plans wp
      LEFT JOIN planned_workout_sessions pws ON pws.plan_id = wp.id
      WHERE wp.id = $1
      GROUP BY wp.id`,
      [plan.id]
    );

    res.status(201).json({
      success: true,
      data: completeResult.rows[0],
      message: 'Workout plan created successfully',
    });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function updateWorkoutPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const checkResult = await pool.query('SELECT id FROM workout_plans WHERE id = $1 AND user_id = $2', [id, userId]);
  if (checkResult.rows.length === 0) {
    throw new NotFoundError('Workout plan');
  }

  const { name, description, daysPerWeek } = req.body;

  const result = await pool.query(
    `UPDATE workout_plans SET
     name = COALESCE($1, name),
     description = COALESCE($2, description),
     days_per_week = COALESCE($3, days_per_week),
     updated_at = NOW()
     WHERE id = $4 AND user_id = $5
     RETURNING *`,
    [name, description, daysPerWeek, id, userId]
  );

  res.json({
    success: true,
    data: result.rows[0],
    message: 'Workout plan updated successfully',
  });
}

export async function activateWorkoutPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  await pool.query('UPDATE workout_plans SET is_active = false WHERE user_id = $1', [userId]);

  const result = await pool.query(
    'UPDATE workout_plans SET is_active = true WHERE id = $1 AND user_id = $2 RETURNING *',
    [id, userId]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Workout plan');
  }

  res.json({
    success: true,
    data: result.rows[0],
    message: 'Workout plan activated successfully',
  });
}

export async function deleteWorkoutPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query('DELETE FROM workout_plans WHERE id = $1 AND user_id = $2 RETURNING id', [id, userId]);
  if (result.rows.length === 0) {
    throw new NotFoundError('Workout plan');
  }

  res.json({
    success: true,
    message: 'Workout plan deleted successfully',
  });
}

export async function generateWorkoutPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;

  if (!config.openai.apiKey) {
    res.status(503).json({ success: false, error: 'AI plan generation not configured' });
    return;
  }

  try {
    const profileResult = await pool.query('SELECT * FROM user_profiles WHERE user_id = $1', [userId]);
    if (profileResult.rows.length === 0) {
      throw new NotFoundError('Profile');
    }

    const profile = profileResult.rows[0];

    // Get available exercises
    const exercisesResult = await pool.query(
      'SELECT id, name, body_part, equipment, difficulty FROM exercises WHERE is_custom = false'
    );

    const prompt = `Generate a personalized weekly workout plan for a fitness user.
Profile: Age ${profile.age}, ${profile.sex}, ${profile.height}cm, ${profile.weight}kg
Goal: ${profile.goal}, Activity: ${profile.activity_level}

Available exercises (select from these): ${JSON.stringify(exercisesResult.rows.slice(0, 50))}

Return a JSON plan with:
- name: Plan name
- description: Brief description
- daysPerWeek: Number (3-6)
- sessions: Array of {dayOfWeek (0=Sun, 1=Mon, etc), name, estimatedDuration (minutes), exercises: [{exerciseId, sets, reps, restTime, order}]}`;

    const response = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 2000,
      temperature: 0.7,
    });

    const content = response.choices[0].message.content;
    let plan;
    try {
      const jsonMatch = content?.match(/\{[\s\S]*\}/);
      plan = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      plan = null;
    }

    if (!plan) {
      throw new Error('Failed to generate plan');
    }

    // Create the plan in database
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const planResult = await client.query(
        `INSERT INTO workout_plans (user_id, name, description, days_per_week, is_active)
         VALUES ($1, $2, $3, $4, true) RETURNING *`,
        [userId, plan.name || 'AI Generated Plan', plan.description || '', plan.daysPerWeek || 4]
      );

      const dbPlan = planResult.rows[0];

      if (plan.sessions && Array.isArray(plan.sessions)) {
        for (let i = 0; i < plan.sessions.length; i++) {
          const session = plan.sessions[i];
          
          const sessionResult = await client.query(
            `INSERT INTO planned_workout_sessions (plan_id, day_of_week, name, estimated_duration, "order")
             VALUES ($1, $2, $3, $4, $5) RETURNING id`,
            [dbPlan.id, session.dayOfWeek, session.name, session.estimatedDuration, i]
          );

          const plannedSessionId = sessionResult.rows[0].id;

          if (session.exercises && Array.isArray(session.exercises)) {
            for (let j = 0; j < session.exercises.length; j++) {
              const exercise = session.exercises[j];
              await client.query(
                `INSERT INTO planned_workout_exercises (planned_session_id, exercise_id, sets, reps, rest_time, "order")
                 VALUES ($1, $2, $3, $4, $5, $6)`,
                [plannedSessionId, exercise.exerciseId, exercise.sets, exercise.reps, exercise.restTime, j]
              );
            }
          }
        }
      }

      await client.query('COMMIT');

      // Fetch complete plan
      const completeResult = await pool.query(
        `SELECT wp.*,
          json_agg(
            json_build_object(
              'id', pws.id,
              'dayOfWeek', pws.day_of_week,
              'name', pws.name,
              'estimatedDuration', pws.estimated_duration,
              'exercises', (
                SELECT json_agg(json_build_object(
                  'id', pwe.id,
                  'exerciseId', pwe.exercise_id,
                  'sets', pwe.sets,
                  'reps', pwe.reps,
                  'restTime', pwe.rest_time,
                  'order', pwe."order"
                ) ORDER BY pwe."order")
                FROM planned_workout_exercises pwe WHERE pwe.planned_session_id = pws.id
              )
            ) ORDER BY pws."order"
          ) as sessions
        FROM workout_plans wp
        LEFT JOIN planned_workout_sessions pws ON pws.plan_id = wp.id
        WHERE wp.id = $1
        GROUP BY wp.id`,
        [dbPlan.id]
      );

      res.status(201).json({
        success: true,
        data: completeResult.rows[0],
        message: 'AI workout plan generated and activated',
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('Generate workout plan error:', error);
    res.status(500).json({ success: false, error: 'Failed to generate workout plan' });
  }
}