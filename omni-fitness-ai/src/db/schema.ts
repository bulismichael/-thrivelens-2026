// src/db/schema.ts
// Local SQLite mirror of the Supabase schema (supabase/migrations/0001_init.sql).
// This is the CACHE the app reads/writes to instantly and offline; sync to/from
// Supabase happens through the repository layer (A3), not automatically.
import { sqliteTable, text, integer, real } from 'drizzle-orm/sqlite-core';

export const profiles = sqliteTable('profiles', {
  id: text('id').primaryKey(), // matches auth.users.id (uuid, as text locally)
  name: text('name'),
  avatarUrl: text('avatar_url'),
  age: integer('age'),
  weight: real('weight'),
  height: real('height'),
  gender: text('gender'),
  goal: text('goal'),
  activityLevel: text('activity_level'),
  experience: text('experience'),
  onboardingCompleted: integer('onboarding_completed', { mode: 'boolean' }).notNull().default(false),
  updatedAt: integer('updated_at', { mode: 'timestamp' }).notNull(),
});

export const exercises = sqliteTable('exercises', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
  bodyPart: text('body_part').notNull(),
  targetMuscle: text('target_muscle'),
  equipment: text('equipment'),
  difficulty: text('difficulty'),
  instructions: text('instructions'),
  imageUrl: text('image_url'),
  videoUrl: text('video_url'),
});

export const workoutPlans = sqliteTable('workout_plans', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull(),
  name: text('name').notNull(),
  description: text('description'),
  goal: text('goal'),
  daysPerWeek: integer('days_per_week').notNull().default(4),
  isCustom: integer('is_custom', { mode: 'boolean' }).notNull().default(false),
  isActive: integer('is_active', { mode: 'boolean' }).notNull().default(false),
  updatedAt: integer('updated_at', { mode: 'timestamp' }).notNull(),
});

export const workoutDays = sqliteTable('workout_days', {
  id: text('id').primaryKey(),
  planId: text('plan_id').notNull(),
  dayNumber: integer('day_number').notNull(),
  name: text('name').notNull(),
  focus: text('focus'),
});

export const workoutExercises = sqliteTable('workout_exercises', {
  id: text('id').primaryKey(),
  dayId: text('day_id').notNull(),
  exerciseId: text('exercise_id').notNull(),
  sets: integer('sets').notNull().default(3),
  reps: text('reps').notNull().default('8-12'),
  restSeconds: integer('rest_seconds').notNull().default(90),
  order: integer('order').notNull().default(0),
  notes: text('notes'),
});

export const workoutSessions = sqliteTable('workout_sessions', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull(),
  planId: text('plan_id'),
  dayId: text('day_id'),
  startedAt: integer('started_at', { mode: 'timestamp' }).notNull(),
  completedAt: integer('completed_at', { mode: 'timestamp' }),
  totalVolume: real('total_volume'),
});

export const workoutLogs = sqliteTable('workout_logs', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull(),
  exerciseId: text('exercise_id').notNull(),
  sessionId: text('session_id'),
  date: integer('date', { mode: 'timestamp' }).notNull(),
  setsCompleted: integer('sets_completed').notNull().default(0),
  reps: text('reps'),
  weight: real('weight'),
  durationSeconds: integer('duration_seconds'),
  notes: text('notes'),
});

export const foodLogs = sqliteTable('food_logs', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull(),
  date: integer('date', { mode: 'timestamp' }).notNull(),
  mealType: text('meal_type').notNull(),
  foodName: text('food_name').notNull(),
  calories: integer('calories').notNull().default(0),
  protein: real('protein').notNull().default(0),
  carbs: real('carbs').notNull().default(0),
  fat: real('fat').notNull().default(0),
  fiber: real('fiber'),
  imageUri: text('image_uri'),
  aiConfidence: real('ai_confidence'),
  aiModelVersion: text('ai_model_version'),
});

export const progressLogs = sqliteTable('progress_logs', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull(),
  date: integer('date', { mode: 'timestamp' }).notNull(),
  weight: real('weight'),
  bodyFat: real('body_fat'),
  notes: text('notes'),
});

export const notifications = sqliteTable('notifications', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull(),
  title: text('title').notNull(),
  body: text('body').notNull(),
  type: text('type').notNull().default('workout_reminder'),
  scheduledAt: integer('scheduled_at', { mode: 'timestamp' }).notNull(),
  sent: integer('sent', { mode: 'boolean' }).notNull().default(false),
});

// NOTE: the offline outbox table (pending mutations, operation_id, version,
// deleted_at) belongs to A3 — add it once the sync strategy is agreed, so we
// don't design it twice.
