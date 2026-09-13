-- 0001_init.sql
-- Replaces the old flat schema.sql. Run via: supabase db push
-- (or paste into Supabase Dashboard -> SQL Editor, once, on a fresh project)

create extension if not exists "uuid-ossp";

-- ============================================================
-- PROFILES
-- Supabase Auth (auth.users) is the identity authority.
-- We no longer store email/password ourselves — auth.users already
-- has that, managed by Supabase. This table only holds app-specific
-- profile data, keyed 1:1 to the authenticated user.
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  avatar_url text,
  age int,
  weight float,
  height float,
  gender text,
  goal text,
  activity_level text,
  experience text,
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Auto-create an empty profile row the moment someone signs up,
-- so the app never has to guess whether a profile exists yet.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- EXERCISE CATALOGUE (public read-only reference data — not user-owned)
-- ============================================================
create table public.exercises (
  id text primary key,
  name text not null,
  body_part text not null,
  target_muscle text,
  equipment text,
  difficulty text,
  instructions text,
  image_url text,
  video_url text,
  created_at timestamptz not null default now()
);
create index exercises_body_part_idx on public.exercises(body_part);

-- ============================================================
-- WORKOUT PLANS / DAYS / EXERCISES / SESSIONS / LOGS
-- ============================================================
create table public.workout_plans (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text,
  goal text,
  days_per_week int not null default 4,
  is_custom boolean not null default false,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workout_days (
  id uuid primary key default uuid_generate_v4(),
  plan_id uuid not null references public.workout_plans(id) on delete cascade,
  day_number int not null,
  name text not null,
  focus text
);

create table public.workout_exercises (
  id uuid primary key default uuid_generate_v4(),
  day_id uuid not null references public.workout_days(id) on delete cascade,
  exercise_id text not null references public.exercises(id),
  sets int not null default 3,
  reps text not null default '8-12',
  rest_seconds int not null default 90,
  "order" int not null default 0,
  notes text
);

create table public.workout_sessions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid references public.workout_plans(id) on delete set null,
  day_id uuid references public.workout_days(id) on delete set null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  total_volume float,
  created_at timestamptz not null default now()
);

create table public.workout_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  exercise_id text not null references public.exercises(id),
  session_id uuid references public.workout_sessions(id) on delete cascade,
  date timestamptz not null default now(),
  sets_completed int not null default 0,
  reps text,
  weight float,
  duration_seconds int,
  notes text,
  created_at timestamptz not null default now()
);

-- ============================================================
-- FOOD + PROGRESS + NOTIFICATIONS
-- ============================================================
create table public.food_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  date timestamptz not null default now(),
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
  created_at timestamptz not null default now()
);

create table public.progress_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  date timestamptz not null default now(),
  weight float,
  body_fat float,
  notes text,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  type text not null default 'workout_reminder',
  scheduled_at timestamptz not null,
  sent boolean not null default false,
  created_at timestamptz not null default now()
);

-- ============================================================
-- ROW LEVEL SECURITY — enabled everywhere, narrow grants
-- ============================================================
alter table public.profiles enable row level security;
alter table public.exercises enable row level security;
alter table public.workout_plans enable row level security;
alter table public.workout_days enable row level security;
alter table public.workout_exercises enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.workout_logs enable row level security;
alter table public.food_logs enable row level security;
alter table public.progress_logs enable row level security;
alter table public.notifications enable row level security;

-- Profiles: a user can only ever see/edit their own row
create policy "profiles_owner_all" on public.profiles
  for all
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Exercise catalogue: readable by any signed-in user, writable by nobody
-- from the client (content is seeded/managed via service role / Studio).
create policy "exercises_read_all" on public.exercises
  for select
  using (auth.role() = 'authenticated');

-- Directly user-owned tables: simple owner-only policy
create policy "workout_plans_owner_all" on public.workout_plans
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "workout_sessions_owner_all" on public.workout_sessions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "workout_logs_owner_all" on public.workout_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "food_logs_owner_all" on public.food_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "progress_logs_owner_all" on public.progress_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "notifications_owner_all" on public.notifications
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Tables reached only THROUGH a parent (no user_id column of their own):
-- verify ownership by walking up to workout_plans.user_id.
create policy "workout_days_via_plan" on public.workout_days
  for all
  using (exists (
    select 1 from public.workout_plans wp
    where wp.id = workout_days.plan_id and wp.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.workout_plans wp
    where wp.id = workout_days.plan_id and wp.user_id = auth.uid()
  ));

create policy "workout_exercises_via_day" on public.workout_exercises
  for all
  using (exists (
    select 1 from public.workout_days wd
    join public.workout_plans wp on wp.id = wd.plan_id
    where wd.id = workout_exercises.day_id and wp.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.workout_days wd
    join public.workout_plans wp on wp.id = wd.plan_id
    where wd.id = workout_exercises.day_id and wp.user_id = auth.uid()
  ));
