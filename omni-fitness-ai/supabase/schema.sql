-- Supabase Postgres schema (mirrors Drizzle SQLite)
-- Run in Supabase Dashboard → SQL Editor → New Query → Paste → Run
-- Free tier: 500MB, no cost. App also works offline without this.

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- Users (extends auth.users if you use Supabase Auth, or standalone)
create table if not exists public.users (
  id text primary key,
  email text not null unique,
  password_hash text,
  name text,
  google_id text,
  avatar_url text,
  age int,
  weight float,
  height float,
  gender text,
  goal text,
  activity_level text,
  experience text,
  onboarding_completed boolean default false,
  created_at bigint not null,
  updated_at bigint not null
);

create table if not exists public.exercises (
  id text primary key,
  name text not null,
  body_part text not null,
  target_muscle text,
  equipment text,
  difficulty text,
  instructions text,
  image_url text,
  video_url text,
  created_at bigint not null
);
create index if not exists exercises_body_part_idx on public.exercises(body_part);

create table if not exists public.workout_plans (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  name text not null,
  description text,
  goal text,
  days_per_week int not null default 4,
  is_custom boolean default false,
  is_active boolean default false,
  created_at bigint not null,
  updated_at bigint not null
);

create table if not exists public.workout_days (
  id text primary key,
  plan_id text not null references public.workout_plans(id) on delete cascade,
  day_number int not null,
  name text not null,
  focus text
);

create table if not exists public.workout_exercises (
  id text primary key,
  day_id text not null references public.workout_days(id) on delete cascade,
  exercise_id text not null references public.exercises(id),
  sets int not null default 3,
  reps text not null default '8-12',
  rest_seconds int not null default 90,
  "order" int not null default 0,
  notes text
);

create table if not exists public.workout_sessions (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  plan_id text references public.workout_plans(id),
  day_id text references public.workout_days(id),
  started_at bigint not null,
  completed_at bigint,
  total_volume float,
  created_at bigint not null
);

create table if not exists public.workout_logs (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  exercise_id text not null references public.exercises(id),
  session_id text references public.workout_sessions(id) on delete cascade,
  date bigint not null,
  sets_completed int not null default 0,
  reps text,
  weight float,
  duration_seconds int,
  notes text,
  created_at bigint not null
);

create table if not exists public.food_logs (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  date bigint not null,
  meal_type text not null,
  food_name text not null,
  calories int not null default 0,
  protein float not null default 0,
  carbs float not null default 0,
  fat float not null default 0,
  fiber float,
  image_uri text,
  ai_confidence float,
  ai_model_version text,
  created_at bigint not null
);

create table if not exists public.progress_logs (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  date bigint not null,
  weight float,
  body_fat float,
  notes text,
  created_at bigint not null
);

create table if not exists public.notifications (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  title text not null,
  body text not null,
  type text not null default 'workout_reminder',
  scheduled_at bigint not null,
  sent boolean default false,
  created_at bigint not null
);

-- RLS (disable for MVP, enable later with policies)
alter table public.users disable row level security;
alter table public.exercises disable row level security;
alter table public.workout_plans disable row level security;
alter table public.workout_days disable row level security;
alter table public.workout_exercises disable row level security;
alter table public.workout_sessions disable row level security;
alter table public.workout_logs disable row level security;
alter table public.food_logs disable row level security;
alter table public.progress_logs disable row level security;
alter table public.notifications disable row level security;
