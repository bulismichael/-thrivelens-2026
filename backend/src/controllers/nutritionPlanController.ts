import { Response } from 'express';
import { pool } from '../config/database';
import { AuthenticatedRequest } from '../middleware/auth';
import { NotFoundError } from '../utils/errors';
import { config } from '../config';
import OpenAI from 'openai';

const openai = new OpenAI({ apiKey: config.openai.apiKey });

export async function getNutritionPlans(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;

  const result = await pool.query(
    `SELECT np.*,
      json_agg(
        json_build_object(
          'id', pm.id,
          'mealType', pm.meal_type,
          'targetCalories', pm.target_calories,
          'targetProtein', pm.target_protein,
          'targetCarbs', pm.target_carbs,
          'targetFat', pm.target_fat,
          'foods', (
            SELECT json_agg(json_build_object(
              'id', pf.id,
              'name', pf.name,
              'quantity', pf.quantity,
              'unit', pf.unit,
              'calories', pf.calories,
              'protein', pf.protein,
              'carbs', pf.carbs,
              'fat', pf.fat
            ) ORDER BY pf."order")
            FROM planned_foods pf WHERE pf.planned_meal_id = pm.id
          )
        ) ORDER BY pm."order"
      ) as meals
    FROM nutrition_plans np
    LEFT JOIN planned_meals pm ON pm.plan_id = np.id
    WHERE np.user_id = $1
    GROUP BY np.id
    ORDER BY np.created_at DESC`,
    [userId]
  );

  res.json({
    success: true,
    data: result.rows,
  });
}

export async function getActiveNutritionPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;

  const result = await pool.query(
    `SELECT np.*,
      json_agg(
        json_build_object(
          'id', pm.id,
          'mealType', pm.meal_type,
          'targetCalories', pm.target_calories,
          'targetProtein', pm.target_protein,
          'targetCarbs', pm.target_carbs,
          'targetFat', pm.target_fat,
          'foods', (
            SELECT json_agg(json_build_object(
              'id', pf.id,
              'name', pf.name,
              'quantity', pf.quantity,
              'unit', pf.unit,
              'calories', pf.calories,
              'protein', pf.protein,
              'carbs', pf.carbs,
              'fat', pf.fat
            ) ORDER BY pf."order")
            FROM planned_foods pf WHERE pf.planned_meal_id = pm.id
          )
        ) ORDER BY pm."order"
      ) as meals
    FROM nutrition_plans np
    LEFT JOIN planned_meals pm ON pm.plan_id = np.id
    WHERE np.user_id = $1 AND np.is_active = true
    GROUP BY np.id`,
    [userId]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Active nutrition plan');
  }

  res.json({
    success: true,
    data: result.rows[0],
  });
}

export async function getNutritionPlanById(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query(
    `SELECT np.*,
      json_agg(
        json_build_object(
          'id', pm.id,
          'mealType', pm.meal_type,
          'targetCalories', pm.target_calories,
          'targetProtein', pm.target_protein,
          'targetCarbs', pm.target_carbs,
          'targetFat', pm.target_fat,
          'foods', (
            SELECT json_agg(json_build_object(
              'id', pf.id,
              'name', pf.name,
              'quantity', pf.quantity,
              'unit', pf.unit,
              'calories', pf.calories,
              'protein', pf.protein,
              'carbs', pf.carbs,
              'fat', pf.fat
            ) ORDER BY pf."order")
            FROM planned_foods pf WHERE pf.planned_meal_id = pm.id
          )
        ) ORDER BY pm."order"
      ) as meals
    FROM nutrition_plans np
    LEFT JOIN planned_meals pm ON pm.plan_id = np.id
    WHERE np.id = $1 AND np.user_id = $2
    GROUP BY np.id`,
    [id, userId]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Nutrition plan');
  }

  res.json({
    success: true,
    data: result.rows[0],
  });
}

export async function createNutritionPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const { name, dailyCalories, dailyProtein, dailyCarbs, dailyFat, meals } = req.body;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const planResult = await client.query(
      `INSERT INTO nutrition_plans (user_id, name, daily_calories, daily_protein, daily_carbs, daily_fat)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [userId, name, dailyCalories, dailyProtein, dailyCarbs, dailyFat]
    );

    const plan = planResult.rows[0];

    for (let i = 0; i < meals.length; i++) {
      const meal = meals[i];
      
      const mealResult = await client.query(
        `INSERT INTO planned_meals (plan_id, meal_type, target_calories, target_protein, target_carbs, target_fat, "order")
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
        [plan.id, meal.mealType, meal.targetCalories, meal.targetProtein, meal.targetCarbs, meal.targetFat, i]
      );

      const plannedMealId = mealResult.rows[0].id;

      if (meal.foods && Array.isArray(meal.foods)) {
        for (let j = 0; j < meal.foods.length; j++) {
          const food = meal.foods[j];
          await client.query(
            `INSERT INTO planned_foods (planned_meal_id, name, quantity, unit, calories, protein, carbs, fat, "order")
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
            [plannedMealId, food.name, food.quantity, food.unit, food.calories, food.protein, food.carbs, food.fat, j]
          );
        }
      }
    }

    await client.query('COMMIT');

    // Fetch complete plan
    const completeResult = await pool.query(
      `SELECT np.*,
        json_agg(
          json_build_object(
            'id', pm.id,
            'mealType', pm.meal_type,
            'targetCalories', pm.target_calories,
            'targetProtein', pm.target_protein,
            'targetCarbs', pm.target_carbs,
            'targetFat', pm.target_fat,
            'foods', (
              SELECT json_agg(json_build_object(
                'id', pf.id,
                'name', pf.name,
                'quantity', pf.quantity,
                'unit', pf.unit,
                'calories', pf.calories,
                'protein', pf.protein,
                'carbs', pf.carbs,
                'fat', pf.fat
              ) ORDER BY pf."order")
              FROM planned_foods pf WHERE pf.planned_meal_id = pm.id
            )
          ) ORDER BY pm."order"
        ) as meals
      FROM nutrition_plans np
      LEFT JOIN planned_meals pm ON pm.plan_id = np.id
      WHERE np.id = $1
      GROUP BY np.id`,
      [plan.id]
    );

    res.status(201).json({
      success: true,
      data: completeResult.rows[0],
      message: 'Nutrition plan created successfully',
    });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function updateNutritionPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const checkResult = await pool.query('SELECT id FROM nutrition_plans WHERE id = $1 AND user_id = $2', [id, userId]);
  if (checkResult.rows.length === 0) {
    throw new NotFoundError('Nutrition plan');
  }

  const { name, dailyCalories, dailyProtein, dailyCarbs, dailyFat } = req.body;

  const result = await pool.query(
    `UPDATE nutrition_plans SET
     name = COALESCE($1, name),
     daily_calories = COALESCE($2, daily_calories),
     daily_protein = COALESCE($3, daily_protein),
     daily_carbs = COALESCE($4, daily_carbs),
     daily_fat = COALESCE($5, daily_fat),
     updated_at = NOW()
     WHERE id = $6 AND user_id = $7
     RETURNING *`,
    [name, dailyCalories, dailyProtein, dailyCarbs, dailyFat, id, userId]
  );

  res.json({
    success: true,
    data: result.rows[0],
    message: 'Nutrition plan updated successfully',
  });
}

export async function activateNutritionPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  // Deactivate all other plans
  await pool.query(
    'UPDATE nutrition_plans SET is_active = false WHERE user_id = $1',
    [userId]
  );

  // Activate the selected plan
  const result = await pool.query(
    'UPDATE nutrition_plans SET is_active = true WHERE id = $1 AND user_id = $2 RETURNING *',
    [id, userId]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Nutrition plan');
  }

  res.json({
    success: true,
    data: result.rows[0],
    message: 'Nutrition plan activated successfully',
  });
}

export async function deleteNutritionPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query('DELETE FROM nutrition_plans WHERE id = $1 AND user_id = $2 RETURNING id', [id, userId]);
  if (result.rows.length === 0) {
    throw new NotFoundError('Nutrition plan');
  }

  res.json({
    success: true,
    message: 'Nutrition plan deleted successfully',
  });
}

export async function generateNutritionPlan(req: AuthenticatedRequest, res: Response): Promise<void> {
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

    const prompt = `Generate a personalized 7-day nutrition plan for a fitness user.
Profile: Age ${profile.age}, ${profile.sex}, ${profile.height}cm, ${profile.weight}kg
Goal: ${profile.goal}, Activity: ${profile.activity_level}
Daily calorie target: ${profile.daily_calorie_target}kcal
Daily protein target: ${profile.daily_protein_target}g
Daily carb target: ${profile.daily_carb_target}g
Daily fat target: ${profile.daily_fat_target}g

Return a JSON plan with:
- name: Plan name
- meals: Array of {mealType: "breakfast"|"lunch"|"dinner"|"snack", targetCalories, targetProtein, targetCarbs, targetFat, foods: [{name, quantity, unit, calories, protein, carbs, fat}]}`;

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
        `INSERT INTO nutrition_plans (user_id, name, daily_calories, daily_protein, daily_carbs, daily_fat, is_active)
         VALUES ($1, $2, $3, $4, $5, $6, true) RETURNING *`,
        [userId, plan.name || 'AI Generated Plan', profile.daily_calorie_target, profile.daily_protein_target, profile.daily_carb_target, profile.daily_fat_target]
      );

      const dbPlan = planResult.rows[0];

      for (let i = 0; i < plan.meals.length; i++) {
        const meal = plan.meals[i];
        
        const mealResult = await client.query(
          `INSERT INTO planned_meals (plan_id, meal_type, target_calories, target_protein, target_carbs, target_fat, "order")
           VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
          [dbPlan.id, meal.mealType, meal.targetCalories, meal.targetProtein, meal.targetCarbs, meal.targetFat, i]
        );

        const plannedMealId = mealResult.rows[0].id;

        if (meal.foods && Array.isArray(meal.foods)) {
          for (let j = 0; j < meal.foods.length; j++) {
            const food = meal.foods[j];
            await client.query(
              `INSERT INTO planned_foods (planned_meal_id, name, quantity, unit, calories, protein, carbs, fat, "order")
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
              [plannedMealId, food.name, food.quantity, food.unit, food.calories, food.protein, food.carbs, food.fat, j]
            );
          }
        }
      }

      await client.query('COMMIT');

      // Fetch complete plan
      const completeResult = await pool.query(
        `SELECT np.*,
          json_agg(
            json_build_object(
              'id', pm.id,
              'mealType', pm.meal_type,
              'targetCalories', pm.target_calories,
              'targetProtein', pm.target_protein,
              'targetCarbs', pm.target_carbs,
              'targetFat', pm.target_fat,
              'foods', (
                SELECT json_agg(json_build_object(
                  'name', pf.name, 'quantity', pf.quantity, 'unit', pf.unit,
                  'calories', pf.calories, 'protein', pf.protein, 'carbs', pf.carbs, 'fat', pf.fat
                ) ORDER BY pf."order")
                FROM planned_foods pf WHERE pf.planned_meal_id = pm.id
              )
            ) ORDER BY pm."order"
          ) as meals
        FROM nutrition_plans np
        LEFT JOIN planned_meals pm ON pm.plan_id = np.id
        WHERE np.id = $1
        GROUP BY np.id`,
        [dbPlan.id]
      );

      res.status(201).json({
        success: true,
        data: completeResult.rows[0],
        message: 'AI nutrition plan generated and activated',
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('Generate nutrition plan error:', error);
    res.status(500).json({ success: false, error: 'Failed to generate nutrition plan' });
  }
}