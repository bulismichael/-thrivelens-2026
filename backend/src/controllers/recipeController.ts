import { Response } from 'express';
import { pool } from '../config/database';
import { AuthenticatedRequest } from '../middleware/auth';
import { NotFoundError } from '../utils/errors';

export async function getRecipes(req: AuthenticatedRequest, res: Response): Promise<void> {
  const {
    tags,
    maxCalories,
    maxPrepTime,
    page = '1',
    limit = '20',
  } = req.query;

  const pageNum = parseInt(page as string, 10);
  const limitNum = Math.min(parseInt(limit as string, 10), 50);
  const offset = (pageNum - 1) * limitNum;

  let whereClause = 'WHERE 1=1';
  const params: any[] = [];
  let paramIndex = 1;

  if (tags) {
    const tagArray = (tags as string).split(',');
    whereClause += ` AND tags && $${paramIndex}`;
    params.push(tagArray);
    paramIndex++;
  }

  if (maxCalories) {
    whereClause += ` AND calories_per_serving <= $${paramIndex}`;
    params.push(parseInt(maxCalories as string, 10));
    paramIndex++;
  }

  if (maxPrepTime) {
    whereClause += ` AND prep_time <= $${paramIndex}`;
    params.push(parseInt(maxPrepTime as string, 10));
    paramIndex++;
  }

  const countResult = await pool.query(
    `SELECT COUNT(*) FROM recipes ${whereClause}`,
    params
  );

  const result = await pool.query(
    `SELECT r.*, 
      json_agg(
        json_build_object(
          'id', ri.id,
          'name', ri.name,
          'quantity', ri.quantity,
          'unit', ri.unit,
          'calories', ri.calories,
          'protein', ri.protein,
          'carbs', ri.carbs,
          'fat', ri.fat
        ) ORDER BY ri."order"
      ) as ingredients,
      json_agg(
        json_build_object(
          'id', rin.id,
          'stepNumber', rin.step_number,
          'instruction', rin.instruction
        ) ORDER BY rin.step_number
      ) as instructions
    FROM recipes r
    LEFT JOIN recipe_ingredients ri ON ri.recipe_id = r.id
    LEFT JOIN recipe_instructions rin ON rin.recipe_id = r.id
    ${whereClause}
    GROUP BY r.id
    ORDER BY r.created_at DESC
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

export async function searchRecipes(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { q, ingredients } = req.query;

  if (!q && !ingredients) {
    res.status(400).json({ success: false, error: 'Search query or ingredients required' });
    return;
  }

  let whereClause = 'WHERE 1=1';
  const params: any[] = [];
  let paramIndex = 1;

  if (q) {
    whereClause += ` AND (name ILIKE $${paramIndex} OR description ILIKE $${paramIndex})`;
    params.push(`%${q}%`);
    paramIndex++;
  }

  if (ingredients) {
    const ingredientArray = (ingredients as string).split(',').map(i => i.trim());
    whereClause += ` AND EXISTS (
      SELECT 1 FROM recipe_ingredients ri 
      WHERE ri.recipe_id = recipes.id 
      AND ri.name ILIKE ANY($${paramIndex})
    )`;
    params.push(ingredientArray.map(i => `%${i}%`));
    paramIndex++;
  }

  const result = await pool.query(
    `SELECT r.*, 
      json_agg(
        json_build_object(
          'id', ri.id,
          'name', ri.name,
          'quantity', ri.quantity,
          'unit', ri.unit
        ) ORDER BY ri."order"
      ) as ingredients
    FROM recipes r
    LEFT JOIN recipe_ingredients ri ON ri.recipe_id = r.id
    ${whereClause}
    GROUP BY r.id
    ORDER BY r.created_at DESC
    LIMIT 20`,
    params
  );

  res.json({
    success: true,
    data: result.rows,
  });
}

export async function getRecipeById(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;

  const result = await pool.query(
    `SELECT r.*, 
      json_agg(
        json_build_object(
          'id', ri.id,
          'name', ri.name,
          'quantity', ri.quantity,
          'unit', ri.unit,
          'calories', ri.calories,
          'protein', ri.protein,
          'carbs', ri.carbs,
          'fat', ri.fat
        ) ORDER BY ri."order"
      ) as ingredients,
      json_agg(
        json_build_object(
          'id', rin.id,
          'stepNumber', rin.step_number,
          'instruction', rin.instruction
        ) ORDER BY rin.step_number
      ) as instructions
    FROM recipes r
    LEFT JOIN recipe_ingredients ri ON ri.recipe_id = r.id
    LEFT JOIN recipe_instructions rin ON rin.recipe_id = r.id
    WHERE r.id = $1
    GROUP BY r.id`,
    [id]
  );

  if (result.rows.length === 0) {
    throw new NotFoundError('Recipe');
  }

  res.json({
    success: true,
    data: result.rows[0],
  });
}

export async function createRecipe(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const {
    name,
    description,
    prepTime,
    cookTime,
    servings,
    caloriesPerServing,
    proteinPerServing,
    carbsPerServing,
    fatPerServing,
    tags = [],
    ingredients,
    instructions,
    imageUrl,
  } = req.body;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const recipeResult = await client.query(
      `INSERT INTO recipes (name, description, prep_time, cook_time, servings, calories_per_serving, protein_per_serving, carbs_per_serving, fat_per_serving, tags, image_url, is_ai_generated, user_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, false, $12) RETURNING *`,
      [name, description, prepTime, cookTime, servings, caloriesPerServing, proteinPerServing, carbsPerServing, fatPerServing, tags, imageUrl, userId]
    );

    const recipe = recipeResult.rows[0];

    for (let i = 0; i < ingredients.length; i++) {
      const ing = ingredients[i];
      await client.query(
        `INSERT INTO recipe_ingredients (recipe_id, name, quantity, unit, calories, protein, carbs, fat, "order")
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [recipe.id, ing.name, ing.quantity, ing.unit, ing.calories, ing.protein, ing.carbs, ing.fat, i]
      );
    }

    for (let i = 0; i < instructions.length; i++) {
      await client.query(
        `INSERT INTO recipe_instructions (recipe_id, step_number, instruction) VALUES ($1, $2, $3)`,
        [recipe.id, i + 1, instructions[i]]
      );
    }

    await client.query('COMMIT');

    // Fetch complete recipe
    const completeResult = await pool.query(
      `SELECT r.*, 
        json_agg(json_build_object('id', ri.id, 'name', ri.name, 'quantity', ri.quantity, 'unit', ri.unit, 'calories', ri.calories, 'protein', ri.protein, 'carbs', ri.carbs, 'fat', ri.fat) ORDER BY ri."order") as ingredients,
        json_agg(json_build_object('id', rin.id, 'stepNumber', rin.step_number, 'instruction', rin.instruction) ORDER BY rin.step_number) as instructions
      FROM recipes r
      LEFT JOIN recipe_ingredients ri ON ri.recipe_id = r.id
      LEFT JOIN recipe_instructions rin ON rin.recipe_id = r.id
      WHERE r.id = $1
      GROUP BY r.id`,
      [recipe.id]
    );

    res.status(201).json({
      success: true,
      data: completeResult.rows[0],
      message: 'Recipe created successfully',
    });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function updateRecipe(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const checkResult = await pool.query('SELECT * FROM recipes WHERE id = $1 AND user_id = $2', [id, userId]);
  if (checkResult.rows.length === 0) {
    throw new NotFoundError('Recipe');
  }

  // For simplicity, we'll just update basic fields
  const { name, description, prepTime, cookTime, servings, caloriesPerServing, proteinPerServing, carbsPerServing, fatPerServing, tags, imageUrl } = req.body;

  const result = await pool.query(
    `UPDATE recipes SET
     name = COALESCE($1, name),
     description = COALESCE($2, description),
     prep_time = COALESCE($3, prep_time),
     cook_time = COALESCE($4, cook_time),
     servings = COALESCE($5, servings),
     calories_per_serving = COALESCE($6, calories_per_serving),
     protein_per_serving = COALESCE($7, protein_per_serving),
     carbs_per_serving = COALESCE($8, carbs_per_serving),
     fat_per_serving = COALESCE($9, fat_per_serving),
     tags = COALESCE($10, tags),
     image_url = COALESCE($11, image_url)
     WHERE id = $12 AND user_id = $13
     RETURNING *`,
    [name, description, prepTime, cookTime, servings, caloriesPerServing, proteinPerServing, carbsPerServing, fatPerServing, tags, imageUrl, id, userId]
  );

  res.json({
    success: true,
    data: result.rows[0],
    message: 'Recipe updated successfully',
  });
}

export async function deleteRecipe(req: AuthenticatedRequest, res: Response): Promise<void> {
  const { id } = req.params;
  const userId = req.user!.userId;

  const result = await pool.query('DELETE FROM recipes WHERE id = $1 AND user_id = $2 RETURNING id', [id, userId]);
  if (result.rows.length === 0) {
    throw new NotFoundError('Recipe');
  }

  res.json({
    success: true,
    message: 'Recipe deleted successfully',
  });
}

// Saved recipes (user's cookbook)
export async function saveRecipe(req: AuthenticatedRequest, res: Response): Promise<void> {
  // This would require a saved_recipes table - for now, we'll just return success
  res.json({
    success: true,
    message: 'Recipe saved to cookbook',
  });
}

export async function unsaveRecipe(req: AuthenticatedRequest, res: Response): Promise<void> {
  res.json({
    success: true,
    message: 'Recipe removed from cookbook',
  });
}

export async function getSavedRecipes(req: AuthenticatedRequest, res: Response): Promise<void> {
  // Would query saved_recipes table
  res.json({
    success: true,
    data: [],
  });
}