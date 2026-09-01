import { Response } from 'express';
import { pool } from '../config/database';
import { AuthenticatedRequest } from '../middleware/auth';
import { NotFoundError } from '../utils/errors';

function calculateBMR(profile: any): number {
  const { weight, height, age, sex } = profile;
  // Mifflin-St Jeor Equation
  if (sex === 'male') {
    return 10 * weight + 6.25 * height - 5 * age + 5;
  } else {
    return 10 * weight + 6.25 * height - 5 * age - 161;
  }
}

function calculateTDEE(bmr: number, activityLevel: string): number {
  const multipliers: Record<string, number> = {
    sedentary: 1.2,
    light: 1.375,
    moderate: 1.55,
    active: 1.725,
    very_active: 1.9,
  };
  return Math.round(bmr * (multipliers[activityLevel] || 1.2));
}

function calculateNutritionTargets(tdee: number, goal: string, weight: number): any {
  let calorieTarget = tdee;
  
  switch (goal) {
    case 'lose_weight':
      calorieTarget = tdee - 500; // ~0.5kg/week loss
      break;
    case 'gain_muscle':
      calorieTarget = tdee + 300; // Surplus for muscle gain
      break;
    case 'improve_fitness':
      calorieTarget = tdee;
      break;
    case 'maintain':
    default:
      calorieTarget = tdee;
      break;
  }

  // Protein: 1.6-2.2g per kg body weight
  const proteinTarget = Math.round(weight * 2);
  
  // Fat: 25-30% of calories
  const fatTarget = Math.round((calorieTarget * 0.25) / 9);
  
  // Carbs: remaining calories
  const carbTarget = Math.round((calorieTarget - (proteinTarget * 4) - (fatTarget * 9)) / 4);

  return {
    dailyCalorieTarget: Math.max(calorieTarget, 1200),
    dailyProteinTarget: Math.max(proteinTarget, 50),
    dailyCarbTarget: Math.max(carbTarget, 50),
    dailyFatTarget: Math.max(fatTarget, 30),
  };
}

export async function getProfile(req: AuthenticatedRequest, res: Response): Promise<void> {
  if (!req.userProfile) {
    throw new NotFoundError('Profile');
  }

  res.json({
    success: true,
    data: req.userProfile,
  });
}

export async function createOrUpdateProfile(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;
  const {
    age,
    height,
    sex,
    weight,
    activityLevel,
    goal,
    targetWeight,
  } = req.body;

  // Calculate nutrition targets
  const bmr = calculateBMR({ weight, height, age, sex });
  const tdee = calculateTDEE(bmr, activityLevel);
  const nutritionTargets = calculateNutritionTargets(tdee, goal, weight);

  const result = await pool.query(
    `INSERT INTO user_profiles 
     (user_id, age, height, sex, weight, activity_level, goal, target_weight, 
      daily_calorie_target, daily_protein_target, daily_carb_target, daily_fat_target)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
     ON CONFLICT (user_id) DO UPDATE SET
     age = EXCLUDED.age,
     height = EXCLUDED.height,
     sex = EXCLUDED.sex,
     weight = EXCLUDED.weight,
     activity_level = EXCLUDED.activity_level,
     goal = EXCLUDED.goal,
     target_weight = EXCLUDED.target_weight,
     daily_calorie_target = EXCLUDED.daily_calorie_target,
     daily_protein_target = EXCLUDED.daily_protein_target,
     daily_carb_target = EXCLUDED.daily_carb_target,
     daily_fat_target = EXCLUDED.daily_fat_target,
     updated_at = NOW()
     RETURNING *`,
    [
      userId,
      age,
      height,
      sex,
      weight,
      activityLevel,
      goal,
      targetWeight,
      nutritionTargets.dailyCalorieTarget,
      nutritionTargets.dailyProteinTarget,
      nutritionTargets.dailyCarbTarget,
      nutritionTargets.dailyFatTarget,
    ]
  );

  res.json({
    success: true,
    data: result.rows[0],
    message: req.userProfile ? 'Profile updated successfully' : 'Profile created successfully',
  });
}

export async function deleteProfile(req: AuthenticatedRequest, res: Response): Promise<void> {
  const userId = req.user!.userId;

  await pool.query('DELETE FROM user_profiles WHERE user_id = $1', [userId]);

  res.json({
    success: true,
    message: 'Profile deleted successfully',
  });
}

export async function getNutritionTargets(req: AuthenticatedRequest, res: Response): Promise<void> {
  if (!req.userProfile) {
    throw new NotFoundError('Profile');
  }

  const profile = req.userProfile;
  const bmr = calculateBMR(profile);
  const tdee = calculateTDEE(bmr, profile.activity_level);
  const targets = calculateNutritionTargets(tdee, profile.goal, profile.weight);

  res.json({
    success: true,
    data: {
      bmr: Math.round(bmr),
      tdee,
      ...targets,
      bmi: calculateBMI(profile.weight, profile.height),
    },
  });
}

function calculateBMI(weight: number, height: number): number {
  const heightInMeters = height / 100;
  return Math.round((weight / (heightInMeters * heightInMeters)) * 10) / 10;
}