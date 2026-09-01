import { Response } from 'express';
import { pool } from '../config/database';
import { AuthenticatedRequest } from '../middleware/auth';
import { NotFoundError } from '../utils/errors';

function calculateBMI(weight: number, height: number): number {
  const heightInMeters = height / 100;
  return Math.round((weight / (heightInMeters * heightInMeters)) * 10) / 10;
}

function getBMICategory(bmi: number): string {
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Normal weight';
  if (bmi < 30) return 'Overweight';
  if (bmi < 35) return 'Obesity Class I';
  if (bmi < 40) return 'Obesity Class II';
  return 'Obesity Class III';
}

export async function getProgressMetrics(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;

  // Get profile
  const profileResult = await pool.query('SELECT * FROM user_profiles WHERE user_id = $1', [userId]);
  if (profileResult.rows.length === 0) {
    throw new NotFoundError('Profile');
  }
  const profile = profileResult.rows[0];

  // Get weight entries
  const weightResult = await pool.query(
    'SELECT * FROM weight_entries WHERE user_id = $1 ORDER BY date ASC',
    [userId]
  );

  const weights = weightResult.rows;
  const currentWeight = weights.length > 0 ? parseFloat(weights[weights.length - 1].weight) : parseFloat(profile.weight);
  const startWeight = weights.length > 0 ? parseFloat(weights[0].weight) : parseFloat(profile.weight);
  const targetWeight = profile.target_weight ? parseFloat(profile.target_weight) : null;

  const weightChange = currentWeight - startWeight;
  const weightChangePercent = startWeight > 0 ? ((weightChange / startWeight) * 100) : 0;

  // Calculate weeks tracked
  let weeksTracked = 0;
  if (weights.length >= 2) {
    const firstDate = new Date(weights[0].date);
    const lastDate = new Date(weights[weights.length - 1].date);
    weeksTracked = Math.max(1, Math.round((lastDate.getTime() - firstDate.getTime()) / (7 * 24 * 60 * 60 * 1000)));
  }

  const averageWeeklyChange = weeksTracked > 0 ? weightChange / weeksTracked : 0;

  const bmi = calculateBMI(currentWeight, parseFloat(profile.height));
  const bmiCategory = getBMICategory(bmi);

  // Calculate calorie deficit/surplus based on goal
  let calorieDeficitSurplus: number | undefined;
  if (profile.daily_calorie_target) {
    // This would ideally come from actual logged calories vs target
    calorieDeficitSurplus = 0; // Placeholder
  }

  res.json({
    success: true,
    data: {
      currentWeight,
      startWeight,
      targetWeight,
      weightChange: Math.round(weightChange * 100) / 100,
      weightChangePercent: Math.round(weightChangePercent * 100) / 100,
      weeksTracked,
      averageWeeklyChange: Math.round(averageWeeklyChange * 100) / 100,
      bmi,
      bmiCategory,
      calorieDeficitSurplus,
    },
  });
}

export async function getWeightHistory(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { limit = '52' } = req.query;

  const result = await pool.query(
    'SELECT * FROM weight_entries WHERE user_id = $1 ORDER BY date DESC LIMIT $2',
    [userId, parseInt(limit as string, 10)]
  );

  res.json({
    success: true,
    data: result.rows.reverse(),
  });
}

export async function addWeightEntry(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { weight, date, note } = req.body;

  const result = await pool.query(
    `INSERT INTO weight_entries (user_id, weight, date, note)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (user_id, date) DO UPDATE SET weight = EXCLUDED.weight, note = EXCLUDED.note
     RETURNING *`,
    [userId, weight, date, note]
  );

  // Also update profile weight
  await pool.query(
    'UPDATE user_profiles SET weight = $1, updated_at = NOW() WHERE user_id = $2',
    [weight, userId]
  );

  res.status(201).json({
    success: true,
    data: result.rows[0],
    message: 'Weight entry added successfully',
  });
}

export async function updateWeightEntry(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;
  const { weight, date, note } = req.body;

  const result = await pool.query(
    `UPDATE weight_entries SET weight = $1, date = $2, note = $3 WHERE id = $4 AND user_id = $5 RETURNING *`,
    [weight, date, note, id, userId]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Weight entry');
  }

  // Update profile weight if this is the latest entry
  const latestResult = await pool.query(
    'SELECT weight FROM weight_entries WHERE user_id = $1 ORDER BY date DESC LIMIT 1',
    [userId]
  );
  if (latestResult.rows.length > 0) {
    await pool.query(
      'UPDATE user_profiles SET weight = $1, updated_at = NOW() WHERE user_id = $2',
      [latestResult.rows[0].weight, userId]
    );
  }

  res.json({
    success: true,
    data: result.rows[0],
    message: 'Weight entry updated successfully',
  });
}

export async function deleteWeightEntry(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query('DELETE FROM weight_entries WHERE id = $1 AND user_id = $2 RETURNING id', [id, userId]);
  if (result.rows.length === 0) {
    throw new NotFoundError('Weight entry');
  }

  // Update profile weight to latest entry
  const latestResult = await pool.query(
    'SELECT weight FROM weight_entries WHERE user_id = $1 ORDER BY date DESC LIMIT 1',
    [userId]
  );
  if (latestResult.rows.length > 0) {
    await pool.query(
      'UPDATE user_profiles SET weight = $1, updated_at = NOW() WHERE user_id = $2',
      [latestResult.rows[0].weight, userId]
    );
  } else {
    // No more entries, use profile's original weight
    const profileResult = await pool.query('SELECT weight FROM user_profiles WHERE user_id = $1', [userId]);
    if (profileResult.rows.length > 0) {
      await pool.query(
        'UPDATE user_profiles SET weight = $1, updated_at = NOW() WHERE user_id = $2',
        [profileResult.rows[0].weight, userId]
      );
    }
  }

  res.json({
    success: true,
    message: 'Weight entry deleted successfully',
  });
}

export async function getWeightChartData(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { weeks = '12' } = req.query;

  const weeksNum = parseInt(weeks as string, 10);
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - weeksNum * 7);

  const result = await pool.query(
    `SELECT date, weight FROM weight_entries 
     WHERE user_id = $1 AND date >= $2 
     ORDER BY date ASC`,
    [userId, startDate.toISOString().split('T')[0]]
  );

  // Get profile for start weight if no entries
  let startWeight: number | null = null;
  if (result.rows.length === 0) {
    const profileResult = await pool.query('SELECT weight FROM user_profiles WHERE user_id = $1', [userId]);
    if (profileResult.rows.length > 0) {
      startWeight = parseFloat(profileResult.rows[0].weight);
    }
  }

  res.json({
    success: true,
    data: {
      entries: result.rows.map(r => ({ date: r.date, weight: parseFloat(r.weight) })),
      startWeight,
    },
  });
}

export async function getNutritionChartData(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { days = '30' } = req.query;

  const daysNum = parseInt(days as string, 10);
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - daysNum);

  const result = await pool.query(
    `SELECT date, 
      SUM(total_calories) as calories,
      SUM(total_protein) as protein,
      SUM(total_carbs) as carbs,
      SUM(total_fat) as fat
    FROM meals 
    WHERE user_id = $1 AND date >= $2
    GROUP BY date
    ORDER BY date ASC`,
    [userId, startDate.toISOString().split('T')[0]]
  );

  // Get targets
  const profileResult = await pool.query(
    'SELECT daily_calorie_target, daily_protein_target, daily_carb_target, daily_fat_target FROM user_profiles WHERE user_id = $1',
    [userId]
  );
  const targets = profileResult.rows[0] || {};

  res.json({
    success: true,
    data: {
      entries: result.rows.map(r => ({
        date: r.date,
        calories: parseInt(r.calories) || 0,
        protein: parseFloat(r.protein) || 0,
        carbs: parseFloat(r.carbs) || 0,
        fat: parseFloat(r.fat) || 0,
      })),
      targets,
    },
  });
}

export async function getWorkoutChartData(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { weeks = '12' } = req.query;

  const weeksNum = parseInt(weeks as string, 10);
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - weeksNum * 7);

  const result = await pool.query(
    `SELECT 
      DATE_TRUNC('week', scheduled_date) as week_start,
      COUNT(*) as workout_count,
      SUM(duration) as total_duration
    FROM workout_sessions
    WHERE user_id = $1 AND scheduled_date >= $2 AND completed_at IS NOT NULL
    GROUP BY DATE_TRUNC('week', scheduled_date)
    ORDER BY week_start ASC`,
    [userId, startDate]
  );

  res.json({
    success: true,
    data: result.rows.map(r => ({
      weekStart: r.week_start,
      workoutCount: parseInt(r.workout_count),
      totalDuration: parseInt(r.total_duration) || 0,
    })),
  });
}