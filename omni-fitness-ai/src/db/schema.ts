import {
  integer,
  real,
  sqliteTable,
  text,
} from "drizzle-orm/sqlite-core";

const timestamps = {
  createdAt: text("created_at").notNull(),
  updatedAt: text("updated_at").notNull(),
};

export const profiles = sqliteTable("profiles", {
  id: text("id").primaryKey(),
  displayName: text("display_name"),
  avatarUrl: text("avatar_url"),
  age: integer("age"),
  weight: real("weight"),
  height: real("height"),
  gender: text("gender"),
  goal: text("goal"),
  activityLevel: text("activity_level"),
  experience: text("experience"),
  calorieTarget: integer("calorie_target"),
  proteinTarget: real("protein_target"),
  dietaryPreference: text("dietary_preference"),
  trainingDaysPerWeek: integer("training_days_per_week"),
  sessionDurationMinutes: integer("session_duration_minutes"),
  workoutLocation: text("workout_location"),
  workoutType: text("workout_type"),
  onboardingCompleted: integer("onboarding_completed", { mode: "boolean" })
    .notNull()
    .default(false),
  ...timestamps,
});

export const exercises = sqliteTable("exercises", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  bodyPart: text("body_part").notNull(),
  targetMuscle: text("target_muscle"),
  equipment: text("equipment"),
  difficulty: text("difficulty"),
  instructions: text("instructions"),
  imageUrl: text("image_url"),
  videoUrl: text("video_url"),
  createdAt: text("created_at").notNull(),
});

export const workoutPlans = sqliteTable("workout_plans", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => profiles.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  description: text("description"),
  goal: text("goal"),
  daysPerWeek: integer("days_per_week").notNull().default(4),
  isCustom: integer("is_custom", { mode: "boolean" }).notNull().default(false),
  isActive: integer("is_active", { mode: "boolean" }).notNull().default(false),
  ...timestamps,
});

export const workoutDays = sqliteTable("workout_days", {
  id: text("id").primaryKey(),
  planId: text("plan_id").notNull().references(() => workoutPlans.id, { onDelete: "cascade" }),
  dayNumber: integer("day_number").notNull(),
  name: text("name").notNull(),
  focus: text("focus"),
});

export const workoutExercises = sqliteTable("workout_exercises", {
  id: text("id").primaryKey(),
  dayId: text("day_id").notNull().references(() => workoutDays.id, { onDelete: "cascade" }),
  exerciseId: text("exercise_id").notNull().references(() => exercises.id),
  sets: integer("sets").notNull().default(3),
  reps: text("reps").notNull().default("8-12"),
  restSeconds: integer("rest_seconds").notNull().default(90),
  order: integer("order").notNull().default(0),
  notes: text("notes"),
});

export const workoutSessions = sqliteTable("workout_sessions", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => profiles.id, { onDelete: "cascade" }),
  planId: text("plan_id").references(() => workoutPlans.id, { onDelete: "set null" }),
  dayId: text("day_id").references(() => workoutDays.id, { onDelete: "set null" }),
  startedAt: text("started_at").notNull(),
  completedAt: text("completed_at"),
  totalVolume: real("total_volume"),
  createdAt: text("created_at").notNull(),
});

export const workoutLogs = sqliteTable("workout_logs", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => profiles.id, { onDelete: "cascade" }),
  exerciseId: text("exercise_id").notNull().references(() => exercises.id),
  sessionId: text("session_id").references(() => workoutSessions.id, { onDelete: "cascade" }),
  loggedAt: text("logged_at").notNull(),
  setsCompleted: integer("sets_completed").notNull().default(0),
  reps: text("reps"),
  weight: real("weight"),
  durationSeconds: integer("duration_seconds"),
  notes: text("notes"),
  createdAt: text("created_at").notNull(),
});

export const foodLogs = sqliteTable("food_logs", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => profiles.id, { onDelete: "cascade" }),
  loggedAt: text("logged_at").notNull(),
  mealType: text("meal_type").notNull(),
  foodName: text("food_name").notNull(),
  calories: integer("calories").notNull().default(0),
  protein: real("protein").notNull().default(0),
  carbs: real("carbs").notNull().default(0),
  fat: real("fat").notNull().default(0),
  fiber: real("fiber"),
  imageUri: text("image_uri"),
  aiConfidence: real("ai_confidence"),
  aiModelVersion: text("ai_model_version"),
  createdAt: text("created_at").notNull(),
});

export const progressLogs = sqliteTable("progress_logs", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => profiles.id, { onDelete: "cascade" }),
  loggedAt: text("logged_at").notNull(),
  weight: real("weight"),
  bodyFat: real("body_fat"),
  notes: text("notes"),
  createdAt: text("created_at").notNull(),
});

export const notifications = sqliteTable("notifications", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => profiles.id),
  title: text("title").notNull(),
  body: text("body").notNull(),
  type: text("type").notNull().default("workout_reminder"),
  scheduledAt: text("scheduled_at").notNull(),
  sent: integer("sent", { mode: "boolean" }).notNull().default(false),
  createdAt: text("created_at").notNull(),
});
