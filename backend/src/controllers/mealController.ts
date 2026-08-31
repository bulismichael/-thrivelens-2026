import { Response } from 'express';
import { pool } from '../config/database';
import { AuthenticatedRequest } from '../middleware/auth';
import { NotFoundError } from '../utils/errors';
import { config } from '../config';
import OpenAI from 'openai';

const openai = new OpenAI({ apiKey: config.openai.apiKey });

export async function getMeals(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const {
    date,
    startDate,
    endDate,
    mealType,
    page = '1',
    limit = '50',
  } = req.query;

  const pageNum = parseInt(page as string, 10);
  const limitNum = Math.min(parseInt(limit as string, 10), 100);
  const offset = (pageNum - 1) * limitNum;

  let whereClause = 'WHERE m.user_id = $1';
  const params: any[] = [userId];
  let paramIndex = 2;

  if (date) {
    whereClause += ` AND m.date = $${paramIndex}`;
    params.push(date);
    paramIndex++;
  } else {
    if (startDate) {
      whereClause += ` AND m.date >= $${paramIndex}`;
      params.push(startDate);
      paramIndex++;
    }
    if (endDate) {
      whereClause += ` AND m.date <= $${paramIndex}`;
      params.push(endDate);
      paramIndex++;
    }
  }

  if (mealType) {
    whereClause += ` AND m.meal_type = $${paramIndex}`;
    params.push(mealType);
    paramIndex++;
  }

  const countResult = await pool.query(
    `SELECT COUNT(*) FROM meals m ${whereClause}`,
    params
  );

  const result = await pool.query(
    `SELECT m.*, 
      json_agg(
        json_build_object(
          'id', fi.id,
          'name', fi.name,
          'quantity', fi.quantity,
          'unit', fi.unit,
          'calories', fi.calories,
          'protein', fi.protein,
          'carbs', fi.carbs,
          'fat', fi.fat,
          'fiber', fi.fiber,
          'sugar', fi.sugar,
          'sodium', fi.sodium
        )
      ) as foods
    FROM meals m
    LEFT JOIN food_items fi ON fi.meal_id = m.id
    ${whereClause}
    GROUP BY m.id
    ORDER BY m.date DESC, 
      CASE m.meal_type 
        WHEN 'breakfast' THEN 1 
        WHEN 'lunch' THEN 2 
        WHEN 'dinner' THEN 3 
        WHEN 'snack' THEN 4 
      END
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

export async function getDailySummary(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { date } = req.query;

  const targetDate = date as string || new Date().toISOString().split('T')[0];

  const result = await pool.query(
    `SELECT 
      m.meal_type,
      json_agg(
        json_build_object(
          'id', fi.id,
          'name', fi.name,
          'quantity', fi.quantity,
          'unit', fi.unit,
          'calories', fi.calories,
          'protein', fi.protein,
          'carbs', fi.carbs,
          'fat', fi.fat
        )
      ) as foods,
      SUM(m.total_calories) as meal_calories,
      SUM(m.total_protein) as meal_protein,
      SUM(m.total_carbs) as meal_carbs,
      SUM(m.total_fat) as meal_fat
    FROM meals m
    LEFT JOIN food_items fi ON fi.meal_id = m.id
    WHERE m.user_id = $1 AND m.date = $2
    GROUP BY m.meal_type
    ORDER BY 
      CASE m.meal_type 
        WHEN 'breakfast' THEN 1 
        WHEN 'lunch' THEN 2 
        WHEN 'dinner' THEN 3 
        WHEN 'snack' THEN 4 
      END`,
    [userId, targetDate]
  );

  const totals = result.rows.reduce((acc: any, meal: any) => {
    acc.calories += parseInt(meal.meal_calories) || 0;
    acc.protein += parseFloat(meal.meal_protein) || 0;
    acc.carbs += parseFloat(meal.meal_carbs) || 0;
    acc.fat += parseFloat(meal.meal_fat) || 0;
    return acc;
  }, { calories: 0, protein: 0, carbs: 0, fat: 0 });

  // Get user's nutrition targets
  const profileResult = await pool.query(
    'SELECT daily_calorie_target, daily_protein_target, daily_carb_target, daily_fat_target FROM user_profiles WHERE user_id = $1',
    [userId]
  );

  const targets = profileResult.rows[0] || {};

  res.json({
    success: true,
    data: {
      date: targetDate,
      meals: result.rows,
      totals,
      targets,
      remaining: {
        calories: Math.max(0, (targets.daily_calorie_target || 0) - totals.calories),
        protein: Math.max(0, (targets.daily_protein_target || 0) - totals.protein),
        carbs: Math.max(0, (targets.daily_carb_target || 0) - totals.carbs),
        fat: Math.max(0, (targets.daily_fat_target || 0) - totals.fat),
      },
    },
  });
}

export async function getMealById(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query(
    `SELECT m.*, 
      json_agg(
        json_build_object(
          'id', fi.id,
          'name', fi.name,
          'quantity', fi.quantity,
          'unit', fi.unit,
          'calories', fi.calories,
          'protein', fi.protein,
          'carbs', fi.carbs,
          'fat', fi.fat,
          'fiber', fi.fiber,
          'sugar', fi.sugar,
          'sodium', fi.sodium
        )
      ) as foods
    FROM meals m
    LEFT JOIN food_items fi ON fi.meal_id = m.id
    WHERE m.id = $1 AND m.user_id = $2
    GROUP BY m.id`,
    [id, userId]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Meal');
  }

  res.json({
    success: true,
    data: result.rows[0],
  });
}

export async function createMeal(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { name, mealType, date, foods, imageUrl } = req.body;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const totalCalories = foods.reduce((sum: number, f: any) => sum + f.calories, 0);
    const totalProtein = foods.reduce((sum: number, f: any) => sum + f.protein, 0);
    const totalCarbs = foods.reduce((sum: number, f: any) => sum + f.carbs, 0);
    const totalFat = foods.reduce((sum: number, f: any) => sum + f.fat, 0);

    const mealResult = await client.query(
      `INSERT INTO meals (user_id, name, meal_type, date, total_calories, total_protein, total_carbs, total_fat, image_url, ai_analyzed)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
      [userId, name, mealType, date, totalCalories, totalProtein, totalCarbs, totalFat, imageUrl, !!imageUrl]
    );

    const meal = mealResult.rows[0];

    for (const food of foods) {
      await client.query(
        `INSERT INTO food_items (meal_id, name, quantity, unit, calories, protein, carbs, fat, fiber, sugar, sodium)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
        [meal.id, food.name, food.quantity, food.unit, food.calories, food.protein, food.carbs, food.fat, food.fiber, food.sugar, food.sodium]
      );
    }

    await client.query('COMMIT');

    // Fetch complete meal
    const completeResult = await pool.query(
      `SELECT m.*, 
        json_agg(
          json_build_object(
            'id', fi.id,
            'name', fi.name,
            'quantity', fi.quantity,
            'unit', fi.unit,
            'calories', fi.calories,
            'protein', fi.protein,
            'carbs', fi.carbs,
            'fat', fi.fat,
            'fiber', fi.fiber,
            'sugar', fi.sugar,
            'sodium', fi.sodium
          )
        ) as foods
      FROM meals m
      LEFT JOIN food_items fi ON fi.meal_id = m.id
      WHERE m.id = $1
      GROUP BY m.id`,
      [meal.id]
    );

    res.status(201).json({
      success: true,
      data: completeResult.rows[0],
      message: 'Meal logged successfully',
    });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function updateMeal(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;
  const { name, mealType, date, foods, imageUrl } = req.body;

  const checkResult = await pool.query('SELECT id FROM meals WHERE id = $1 AND user_id = $2', [id, userId]);
  if (checkResult.rows.length === 0) {
    throw new NotFoundError('Meal');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const totalCalories = foods.reduce((sum: number, f: any) => sum + f.calories, 0);
    const totalProtein = foods.reduce((sum: number, f: any) => sum + f.protein, 0);
    const totalCarbs = foods.reduce((sum: number, f: any) => sum + f.carbs, 0);
    const totalFat = foods.reduce((sum: number, f: any) => sum + f.fat, 0);

    await client.query(
      `UPDATE meals SET name = $1, meal_type = $2, date = $3, total_calories = $4, total_protein = $5, total_carbs = $6, total_fat = $7, image_url = $8, updated_at = NOW() WHERE id = $9`,
      [name, mealType, date, totalCalories, totalProtein, totalCarbs, totalFat, imageUrl, id]
    );

    // Delete existing food items
    await client.query('DELETE FROM food_items WHERE meal_id = $1', [id]);

    // Insert new food items
    for (const food of foods) {
      await client.query(
        `INSERT INTO food_items (meal_id, name, quantity, unit, calories, protein, carbs, fat, fiber, sugar, sodium)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
        [id, food.name, food.quantity, food.unit, food.calories, food.protein, food.carbs, food.fat, food.fiber, food.sugar, food.sodium]
      );
    }

    await client.query('COMMIT');

    // Fetch complete meal
    const completeResult = await pool.query(
      `SELECT m.*, 
        json_agg(
          json_build_object(
            'id', fi.id,
            'name', fi.name,
            'quantity', fi.quantity,
            'unit', fi.unit,
            'calories', fi.calories,
            'protein', fi.protein,
            'carbs', fi.carbs,
            'fat', fi.fat,
            'fiber', fi.fiber,
            'sugar', fi.sugar,
            'sodium', fi.sodium
          )
        ) as foods
      FROM meals m
      LEFT JOIN food_items fi ON fi.meal_id = m.id
      WHERE m.id = $1
      GROUP BY m.id`,
      [id]
    );

    res.json({
      success: true,
      data: completeResult.rows[0],
      message: 'Meal updated successfully',
    });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function deleteMeal(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query('DELETE FROM meals WHERE id = $1 AND user_id = $2 RETURNING id', [id, userId]);
  if (result.rows.length === 0) {
    throw new NotFoundError('Meal');
  }

  res.json({
    success: true,
    message: 'Meal deleted successfully',
  });
}

export async function analyzeFoodImage(req: AuthenticatedRequest, res: Response): Promise<void> {
  if (!config.openai.apiKey) {
    res.status(503).json({
      success: false,
      error: 'AI food analysis not configured',
    });
    return;
  }

  const { imageUrl } = req.body;

  if (!imageUrl) {
    res.status(400).json({
      success: false,
      error: 'Image URL is required',
    });
    return;
  }

  try {
    const response = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        {
          role: 'system',
          content: `You are a nutrition expert. Analyze the food image and return a JSON array of food items with their estimated nutritional information. Each item should have: name, quantity (number), unit (g, ml, oz, cup, piece), calories, protein (g), carbs (g), fat (g), fiber (g, optional), sugar (g, optional), sodium (mg, optional). Be as accurate as possible with portion estimation.`
        },
        {
          role: 'user',
          content: [
            { type: 'text', text: 'Analyze this food image and provide nutritional information for each item.' },
            { type: 'image_url', image_url: { url: imageUrl } }
          ]
        }
      ],
      max_tokens: 1000,
      temperature: 0.3,
    });

    const content = response.choices[0].message.content;
    let foods;
    
    try {
      // Extract JSON from response
      const jsonMatch = content?.match(/\[[\s\S]*\]/);
      foods = jsonMatch ? JSON.parse(jsonMatch[0]) : [];
    } catch {
      foods = [];
    }

    res.json({
      success: true,
      data: { foods },
    });
  } catch (error) {
    console.error('Food analysis error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to analyze food image',
    });
  }
}