export interface User {
  id: string;
  email: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface UserProfile {
  id: string;
  userId: string;
  age: number;
  height: number; // cm
  sex: 'male' | 'female' | 'other';
  weight: number; // kg
  activityLevel: 'sedentary' | 'light' | 'moderate' | 'active' | 'very_active';
  goal: 'lose_weight' | 'maintain' | 'gain_muscle' | 'improve_fitness';
  targetWeight?: number;
  dailyCalorieTarget?: number;
  dailyProteinTarget?: number;
  dailyCarbTarget?: number;
  dailyFatTarget?: number;
  createdAt: Date;
  updatedAt: Date;
}

export interface Exercise {
  id: string;
  name: string;
  description: string;
  bodyPart: BodyPart;
  equipment: string[];
  difficulty: 'beginner' | 'intermediate' | 'advanced';
  instructions: string[];
  muscleGroups: string[];
  videoUrl?: string;
  imageUrl?: string;
  isCustom: boolean;
  userId?: string;
  createdAt: Date;
  updatedAt: Date;
}

export type BodyPart = 
  | 'chest' 
  | 'back' 
  | 'shoulders' 
  | 'arms' 
  | 'legs' 
  | 'core' 
  | 'cardio' 
  | 'full_body';

export interface WorkoutSession {
  id: string;
  userId: string;
  name: string;
  exercises: WorkoutExercise[];
  scheduledDate: Date;
  completedAt?: Date;
  duration?: number; // minutes
  notes?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface WorkoutExercise {
  exerciseId: string;
  exercise?: Exercise;
  sets: ExerciseSet[];
  order: number;
  notes?: string;
}

export interface ExerciseSet {
  setNumber: number;
  reps?: number;
  weight?: number; // kg
  duration?: number; // seconds for timed exercises
  distance?: number; // meters for cardio
  restTime?: number; // seconds
  completed: boolean;
  rpe?: number; // Rate of Perceived Exertion 1-10
}

export interface Meal {
  id: string;
  userId: string;
  name: string;
  mealType: 'breakfast' | 'lunch' | 'dinner' | 'snack';
  date: Date;
  foods: FoodItem[];
  totalCalories: number;
  totalProtein: number;
  totalCarbs: number;
  totalFat: number;
  imageUrl?: string;
  aiAnalyzed: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface FoodItem {
  id: string;
  name: string;
  quantity: number;
  unit: string; // g, ml, oz, cup, piece, etc.
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber?: number;
  sugar?: number;
  sodium?: number;
}

export interface WeightEntry {
  id: string;
  userId: string;
  weight: number; // kg
  date: Date;
  note?: string;
  createdAt: Date;
}

export interface ProgressMetrics {
  currentWeight: number;
  startWeight: number;
  targetWeight?: number;
  weightChange: number;
  weightChangePercent: number;
  weeksTracked: number;
  averageWeeklyChange: number;
  bmi: number;
  bmiCategory: string;
  calorieDeficitSurplus?: number;
}

export interface AITip {
  id: string;
  userId: string;
  type: 'nutrition' | 'exercise' | 'progress' | 'general' | 'motivation';
  title: string;
  message: string;
  priority: 'low' | 'medium' | 'high';
  isRead: boolean;
  createdAt: Date;
  relatedEntityId?: string;
  relatedEntityType?: 'meal' | 'workout' | 'weight' | 'goal';
}

export interface Recipe {
  id: string;
  name: string;
  description: string;
  ingredients: RecipeIngredient[];
  instructions: string[];
  prepTime: number; // minutes
  cookTime: number; // minutes
  servings: number;
  caloriesPerServing: number;
  proteinPerServing: number;
  carbsPerServing: number;
  fatPerServing: number;
  tags: string[]; // vegetarian, vegan, gluten-free, etc.
  imageUrl?: string;
  isAiGenerated: boolean;
  userId?: string;
  createdAt: Date;
}

export interface RecipeIngredient {
  name: string;
  quantity: number;
  unit: string;
  calories?: number;
  protein?: number;
  carbs?: number;
  fat?: number;
}

export interface NutritionPlan {
  id: string;
  userId: string;
  name: string;
  dailyCalories: number;
  dailyProtein: number;
  dailyCarbs: number;
  dailyFat: number;
  meals: PlannedMeal[];
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface PlannedMeal {
  mealType: 'breakfast' | 'lunch' | 'dinner' | 'snack';
  foods: PlannedFood[];
  targetCalories: number;
  targetProtein: number;
  targetCarbs: number;
  targetFat: number;
}

export interface PlannedFood {
  name: string;
  quantity: number;
  unit: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
}

export interface WorkoutPlan {
  id: string;
  userId: string;
  name: string;
  description: string;
  daysPerWeek: number;
  sessions: PlannedWorkoutSession[];
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface PlannedWorkoutSession {
  dayOfWeek: number; // 0-6
  name: string;
  exercises: PlannedWorkoutExercise[];
  estimatedDuration: number;
}

export interface PlannedWorkoutExercise {
  exerciseId: string;
  sets: number;
  reps: string; // e.g., "8-12" or "30s"
  restTime: number;
  order: number;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}