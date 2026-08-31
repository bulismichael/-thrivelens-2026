-- ThriveLens Database Schema
-- Run this on PostgreSQL initialization

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User profiles table
CREATE TABLE IF NOT EXISTS user_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    age INTEGER NOT NULL CHECK (age > 0 AND age < 150),
    height DECIMAL(5,2) NOT NULL CHECK (height > 0 AND height < 300), -- cm
    sex VARCHAR(20) NOT NULL CHECK (sex IN ('male', 'female', 'other')),
    weight DECIMAL(5,2) NOT NULL CHECK (weight > 0 AND weight < 500), -- kg
    activity_level VARCHAR(20) NOT NULL CHECK (activity_level IN ('sedentary', 'light', 'moderate', 'active', 'very_active')),
    goal VARCHAR(30) NOT NULL CHECK (goal IN ('lose_weight', 'maintain', 'gain_muscle', 'improve_fitness')),
    target_weight DECIMAL(5,2) CHECK (target_weight > 0 AND target_weight < 500),
    daily_calorie_target INTEGER,
    daily_protein_target INTEGER,
    daily_carb_target INTEGER,
    daily_fat_target INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id)
);

-- Exercises table
CREATE TABLE IF NOT EXISTS exercises (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    body_part VARCHAR(50) NOT NULL CHECK (body_part IN ('chest', 'back', 'shoulders', 'arms', 'legs', 'core', 'cardio', 'full_body')),
    equipment TEXT[],
    difficulty VARCHAR(20) NOT NULL CHECK (difficulty IN ('beginner', 'intermediate', 'advanced')),
    instructions TEXT[],
    muscle_groups TEXT[],
    video_url VARCHAR(500),
    image_url VARCHAR(500),
    is_custom BOOLEAN DEFAULT FALSE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Workout sessions table
CREATE TABLE IF NOT EXISTS workout_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    scheduled_date TIMESTAMP WITH TIME ZONE NOT NULL,
    completed_at TIMESTAMP WITH TIME ZONE,
    duration INTEGER, -- minutes
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Workout exercises (junction table with sets)
CREATE TABLE IF NOT EXISTS workout_exercises (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    "order" INTEGER NOT NULL,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Exercise sets table
CREATE TABLE IF NOT EXISTS exercise_sets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workout_exercise_id UUID NOT NULL REFERENCES workout_exercises(id) ON DELETE CASCADE,
    set_number INTEGER NOT NULL,
    reps INTEGER,
    weight DECIMAL(6,2), -- kg
    duration INTEGER, -- seconds
    distance DECIMAL(8,2), -- meters
    rest_time INTEGER, -- seconds
    completed BOOLEAN DEFAULT FALSE,
    rpe INTEGER CHECK (rpe >= 1 AND rpe <= 10),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Meals table
CREATE TABLE IF NOT EXISTS meals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255),
    meal_type VARCHAR(20) NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
    date DATE NOT NULL,
    total_calories INTEGER DEFAULT 0,
    total_protein DECIMAL(6,2) DEFAULT 0,
    total_carbs DECIMAL(6,2) DEFAULT 0,
    total_fat DECIMAL(6,2) DEFAULT 0,
    image_url VARCHAR(500),
    ai_analyzed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Food items table
CREATE TABLE IF NOT EXISTS food_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    meal_id UUID NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    quantity DECIMAL(8,2) NOT NULL,
    unit VARCHAR(50) NOT NULL,
    calories INTEGER NOT NULL,
    protein DECIMAL(6,2) NOT NULL,
    carbs DECIMAL(6,2) NOT NULL,
    fat DECIMAL(6,2) NOT NULL,
    fiber DECIMAL(6,2),
    sugar DECIMAL(6,2),
    sodium DECIMAL(8,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Weight entries table
CREATE TABLE IF NOT EXISTS weight_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    weight DECIMAL(5,2) NOT NULL CHECK (weight > 0 AND weight < 500),
    date DATE NOT NULL,
    note TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, date)
);

-- AI tips table
CREATE TABLE IF NOT EXISTS ai_tips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL CHECK (type IN ('nutrition', 'exercise', 'progress', 'general', 'motivation')),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    priority VARCHAR(10) NOT NULL CHECK (priority IN ('low', 'medium', 'high')),
    is_read BOOLEAN DEFAULT FALSE,
    related_entity_id UUID,
    related_entity_type VARCHAR(20) CHECK (related_entity_type IN ('meal', 'workout', 'weight', 'goal')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Recipes table
CREATE TABLE IF NOT EXISTS recipes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    prep_time INTEGER NOT NULL, -- minutes
    cook_time INTEGER NOT NULL, -- minutes
    servings INTEGER NOT NULL,
    calories_per_serving INTEGER NOT NULL,
    protein_per_serving DECIMAL(6,2) NOT NULL,
    carbs_per_serving DECIMAL(6,2) NOT NULL,
    fat_per_serving DECIMAL(6,2) NOT NULL,
    tags TEXT[],
    image_url VARCHAR(500),
    is_ai_generated BOOLEAN DEFAULT FALSE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Recipe ingredients table
CREATE TABLE IF NOT EXISTS recipe_ingredients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    quantity DECIMAL(8,2) NOT NULL,
    unit VARCHAR(50) NOT NULL,
    calories INTEGER,
    protein DECIMAL(6,2),
    carbs DECIMAL(6,2),
    fat DECIMAL(6,2),
    "order" INTEGER NOT NULL
);

-- Recipe instructions table
CREATE TABLE IF NOT EXISTS recipe_instructions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    step_number INTEGER NOT NULL,
    instruction TEXT NOT NULL
);

-- Nutrition plans table
CREATE TABLE IF NOT EXISTS nutrition_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    daily_calories INTEGER NOT NULL,
    daily_protein DECIMAL(6,2) NOT NULL,
    daily_carbs DECIMAL(6,2) NOT NULL,
    daily_fat DECIMAL(6,2) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Planned meals table
CREATE TABLE IF NOT EXISTS planned_meals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    plan_id UUID NOT NULL REFERENCES nutrition_plans(id) ON DELETE CASCADE,
    meal_type VARCHAR(20) NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
    target_calories INTEGER NOT NULL,
    target_protein DECIMAL(6,2) NOT NULL,
    target_carbs DECIMAL(6,2) NOT NULL,
    target_fat DECIMAL(6,2) NOT NULL,
    "order" INTEGER NOT NULL
);

-- Planned foods table
CREATE TABLE IF NOT EXISTS planned_foods (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    planned_meal_id UUID NOT NULL REFERENCES planned_meals(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    quantity DECIMAL(8,2) NOT NULL,
    unit VARCHAR(50) NOT NULL,
    calories INTEGER NOT NULL,
    protein DECIMAL(6,2) NOT NULL,
    carbs DECIMAL(6,2) NOT NULL,
    fat DECIMAL(6,2) NOT NULL,
    "order" INTEGER NOT NULL
);

-- Workout plans table
CREATE TABLE IF NOT EXISTS workout_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    days_per_week INTEGER NOT NULL CHECK (days_per_week > 0 AND days_per_week <= 7),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Planned workout sessions table
CREATE TABLE IF NOT EXISTS planned_workout_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    plan_id UUID NOT NULL REFERENCES workout_plans(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),
    name VARCHAR(255) NOT NULL,
    estimated_duration INTEGER NOT NULL, -- minutes
    "order" INTEGER NOT NULL
);

-- Planned workout exercises table
CREATE TABLE IF NOT EXISTS planned_workout_exercises (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    planned_session_id UUID NOT NULL REFERENCES planned_workout_sessions(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    sets INTEGER NOT NULL,
    reps VARCHAR(50) NOT NULL,
    rest_time INTEGER NOT NULL, -- seconds
    "order" INTEGER NOT NULL
);

-- Refresh tokens table
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON user_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_exercises_body_part ON exercises(body_part);
CREATE INDEX IF NOT EXISTS idx_exercises_is_custom ON exercises(is_custom);
CREATE INDEX IF NOT EXISTS idx_workout_sessions_user_id ON workout_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_workout_sessions_scheduled_date ON workout_sessions(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_workout_exercises_session_id ON workout_exercises(session_id);
CREATE INDEX IF NOT EXISTS idx_exercise_sets_workout_exercise_id ON exercise_sets(workout_exercise_id);
CREATE INDEX IF NOT EXISTS idx_meals_user_id ON meals(user_id);
CREATE INDEX IF NOT EXISTS idx_meals_date ON meals(date);
CREATE INDEX IF NOT EXISTS idx_food_items_meal_id ON food_items(meal_id);
CREATE INDEX IF NOT EXISTS idx_weight_entries_user_id ON weight_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_weight_entries_date ON weight_entries(date);
CREATE INDEX IF NOT EXISTS idx_ai_tips_user_id ON ai_tips(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_tips_is_read ON ai_tips(is_read);
CREATE INDEX IF NOT EXISTS idx_recipes_user_id ON recipes(user_id);
CREATE INDEX IF NOT EXISTS idx_nutrition_plans_user_id ON nutrition_plans(user_id);
CREATE INDEX IF NOT EXISTS idx_workout_plans_user_id ON workout_plans(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token ON refresh_tokens(token);