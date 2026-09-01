import { Response } from 'express';
import { pool } from '../config/database';
import { AuthenticatedRequest } from '../middleware/auth';
import { config } from '../config';
import OpenAI from 'openai';

const openai = new OpenAI({ apiKey: config.openai.apiKey });

export async function getTips(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { unreadOnly, limit = '20' } = req.query;

  let query = 'SELECT * FROM ai_tips WHERE user_id = $1';
  const params: any[] = [userId];

  if (unreadOnly === 'true') {
    query += ' AND is_read = false';
  }

  query += ' ORDER BY priority DESC, created_at DESC LIMIT $2';
  params.push(parseInt(limit as string, 10));

  const result = await pool.query(query, params);

  res.json({
    success: true,
    data: result.rows,
  });
}

export async function markTipAsRead(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { id } = req.params;

  const result = await pool.query(
    'UPDATE ai_tips SET is_read = true WHERE id = $1 AND user_id = $2 RETURNING *',
    [id, userId]
  );

  if (result.rows.length === 0) {
    res.status(404).json({ success: false, error: 'Tip not found' });
    return;
  }

  res.json({
    success: true,
    data: result.rows[0],
  });
}

async function generateAITip(userId: string, type: string, context: any): Promise<void> {
  if (!config.openai.apiKey) return;

  try {
    const profileResult = await pool.query('SELECT * FROM user_profiles WHERE user_id = $1', [userId]);
    const profile = profileResult.rows[0];

    const prompt = `Generate a helpful, personalized ${type} tip for a fitness app user.
User profile: Age ${profile?.age}, ${profile?.sex}, ${profile?.height}cm, ${profile?.weight}kg
Goal: ${profile?.goal}, Activity: ${profile?.activityLevel}
Context: ${JSON.stringify(context)}
Return a JSON object with: title (max 50 chars), message (max 200 chars), priority (low/medium/high)`;

    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 300,
      temperature: 0.7,
    });

    const content = response.choices[0].message.content;
    let tipData;
    try {
      const jsonMatch = content?.match(/\{[\s\S]*\}/);
      tipData = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      return;
    }

    if (tipData) {
      await pool.query(
        `INSERT INTO ai_tips (user_id, type, title, message, priority, related_entity_id, related_entity_type)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, type, tipData.title, tipData.message, tipData.priority || 'medium', context.entityId, context.entityType]
      );
    }
  } catch (error) {
    console.error('AI tip generation error:', error);
  }
}

export async function generateTips(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;

  // Generate tips for different categories
  await Promise.all([
    generateAITip(userId, 'nutrition', { entityType: 'general' }),
    generateAITip(userId, 'exercise', { entityType: 'general' }),
    generateAITip(userId, 'progress', { entityType: 'general' }),
    generateAITip(userId, 'motivation', { entityType: 'general' }),
  ]);

  res.json({
    success: true,
    message: 'Tips generated successfully',
  });
}

export async function analyzeProgress(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;

  if (!config.openai.apiKey) {
    res.status(503).json({ success: false, error: 'AI analysis not configured' });
    return;
  }

  try {
    // Gather user data
    const [profileResult, weightsResult, mealsResult, workoutsResult] = await Promise.all([
      pool.query('SELECT * FROM user_profiles WHERE user_id = $1', [userId]),
      pool.query('SELECT * FROM weight_entries WHERE user_id = $1 ORDER BY date DESC LIMIT 12', [userId]),
      pool.query(`SELECT date, SUM(total_calories) as calories, SUM(total_protein) as protein, SUM(total_carbs) as carbs, SUM(total_fat) as fat FROM meals WHERE user_id = $1 AND date >= CURRENT_DATE - INTERVAL '30 days' GROUP BY date ORDER BY date DESC`, [userId]),
      pool.query(`SELECT COUNT(*) as count, SUM(duration) as total_duration FROM workout_sessions WHERE user_id = $1 AND completed_at IS NOT NULL AND scheduled_date >= CURRENT_DATE - INTERVAL '30 days'`, [userId]),
    ]);

    const profile = profileResult.rows[0];
    const weights = weightsResult.rows;
    const meals = mealsResult.rows;
    const workouts = workoutsResult.rows[0];

    const prompt = `Analyze this user's fitness progress and provide actionable insights.
Profile: ${JSON.stringify(profile)}
Recent weights (last 12): ${JSON.stringify(weights)}
Recent nutrition (30 days): ${JSON.stringify(meals.slice(0, 7))}
Recent workouts (30 days): ${JSON.stringify(workouts)}

Provide a JSON response with:
1. progressSummary: string (2-3 sentences)
2. strengths: string[]
3. areasForImprovement: string[]
4. recommendations: string[]
5. overallScore: number (1-100)`;

    const response = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 800,
      temperature: 0.5,
    });

    const content = response.choices[0].message.content;
    let analysis;
    try {
      const jsonMatch = content?.match(/\{[\s\S]*\}/);
      analysis = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      analysis = null;
    }

    // Store as AI tip
    if (analysis) {
      await pool.query(
        `INSERT INTO ai_tips (user_id, type, title, message, priority, related_entity_type)
         VALUES ($1, 'progress', $2, $3, 'high', 'goal')`,
        [userId, 'Progress Analysis', JSON.stringify(analysis)]
      );
    }

    res.json({
      success: true,
      data: analysis || { message: 'Analysis completed' },
    });
  } catch (error) {
    console.error('Progress analysis error:', error);
    res.status(500).json({ success: false, error: 'Failed to analyze progress' });
  }
}

export async function getRecipeSuggestions(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { ingredients, mealType, dietaryRestrictions, maxCalories } = req.body;

  if (!config.openai.apiKey) {
    res.status(503).json({ success: false, error: 'AI recipes not configured' });
    return;
  }

  try {
    const profileResult = await pool.query('SELECT * FROM user_profiles WHERE user_id = $1', [userId]);
    const profile = profileResult.rows[0];

    const prompt = `Generate 3 healthy recipe suggestions based on available ingredients.
User profile: Goal: ${profile?.goal}, Daily calories: ${profile?.daily_calorie_target}, Protein target: ${profile?.daily_protein_target}g
Available ingredients: ${ingredients?.join(', ') || 'various'}
Meal type: ${mealType || 'any'}
Dietary restrictions: ${dietaryRestrictions?.join(', ') || 'none'}
Max calories per serving: ${maxCalories || profile?.daily_calorie_target || 500}

Return JSON array of recipes with: name, description, ingredients (name, quantity, unit, calories, protein, carbs, fat), instructions (array), prepTime, cookTime, servings, caloriesPerServing, proteinPerServing, carbsPerServing, fatPerServing, tags`;

    const response = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 2000,
      temperature: 0.7,
    });

    const content = response.choices[0].message.content;
    let recipes;
    try {
      const jsonMatch = content?.match(/\[[\s\S]*\]/);
      recipes = jsonMatch ? JSON.parse(jsonMatch[0]) : [];
    } catch {
      recipes = [];
    }

    res.json({
      success: true,
      data: { recipes },
    });
  } catch (error) {
    console.error('Recipe suggestions error:', error);
    res.status(500).json({ success: false, error: 'Failed to generate recipes' });
  }
}

export async function getWorkoutSuggestions(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { bodyParts, duration, equipment, difficulty } = req.body;

  if (!config.openai.apiKey) {
    res.status(503).json({ success: false, error: 'AI workouts not configured' });
    return;
  }

  try {
    const profileResult = await pool.query('SELECT * FROM user_profiles WHERE user_id = $1', [userId]);
    const profile = profileResult.rows[0];

    // Get user's custom exercises
    const exercisesResult = await pool.query(
      'SELECT id, name, body_part, equipment, difficulty FROM exercises WHERE (is_custom = false OR user_id = $1) AND body_part = ANY($2)',
      [userId, bodyParts || ['chest', 'back', 'shoulders', 'arms', 'legs', 'core']]
    );

    const prompt = `Generate a personalized workout plan.
User profile: Age ${profile?.age}, ${profile?.sex}, ${profile?.height}cm, ${profile?.weight}kg, Goal: ${profile?.goal}
Target body parts: ${bodyParts?.join(', ') || 'full body'}
Duration: ${duration || 45} minutes
Available equipment: ${equipment?.join(', ') || 'bodyweight, dumbbells'}
Difficulty: ${difficulty || profile?.activity_level || 'beginner'}
Available exercises: ${JSON.stringify(exercisesResult.rows.slice(0, 20))}

Return JSON with: name, description, estimatedDuration, exercises (exerciseId, sets, reps, restTime, order)`;

    const response = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 1500,
      temperature: 0.7,
    });

    const content = response.choices[0].message.content;
    let workout;
    try {
      const jsonMatch = content?.match(/\{[\s\S]*\}/);
      workout = jsonMatch ? JSON.parse(jsonMatch[0]) : null;
    } catch {
      workout = null;
    }

    res.json({
      success: true,
      data: workout,
    });
  } catch (error) {
    console.error('Workout suggestions error:', error);
    res.status(500).json({ success: false, error: 'Failed to generate workout' });
  }
}