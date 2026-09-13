-- seed.sql — run in SQL Editor AFTER 0001_init.sql and AFTER you've created
-- one real test user (Dashboard -> Authentication -> Users -> Add user).
-- Replace YOUR_USER_ID below with that user's UUID before running.

-- 1) Exercise catalogue (no dependency, safe to run anytime)
insert into public.exercises (id, name, body_part, target_muscle, equipment, difficulty, instructions) values
  ('bench-press', 'Barbell Bench Press', 'chest', 'pectorals', 'barbell', 'intermediate', 'Lie on a flat bench, lower the bar to mid-chest, press back up to full arm extension.'),
  ('overhead-press', 'Standing Overhead Press', 'shoulders', 'deltoids', 'barbell', 'intermediate', 'Press bar from shoulder height to full overhead extension.'),
  ('back-squat', 'Barbell Back Squat', 'legs', 'quadriceps', 'barbell', 'intermediate', 'Bar on upper back, squat until thighs are parallel to floor, drive back up.'),
  ('bent-over-row', 'Barbell Bent-Over Row', 'back', 'lats', 'barbell', 'intermediate', 'Hinge forward, pull bar to lower ribs, lower with control.')
on conflict (id) do nothing;

-- 2) Update the auto-created profile row for your test user
update public.profiles
set
  name = 'David',
  age = 28,
  weight = 78.5,
  height = 178,
  gender = 'male',
  goal = 'muscle_gain',
  activity_level = 'moderately_active',
  experience = 'intermediate',
  onboarding_completed = true,
  updated_at = now()
where id = 'YOUR_USER_ID';

-- 3) A workout plan + its two days + exercises assigned to each day
with plan as (
  insert into public.workout_plans (user_id, name, description, goal, days_per_week, is_active)
  values ('YOUR_USER_ID', 'Full Body Starter', 'A simple 2-day full body split for beginners', 'strength', 2, true)
  returning id
),
day1 as (
  insert into public.workout_days (plan_id, day_number, name, focus)
  select id, 1, 'Day 1 - Push', 'chest/shoulders/triceps' from plan
  returning id, plan_id
),
day2 as (
  insert into public.workout_days (plan_id, day_number, name, focus)
  select id, 2, 'Day 2 - Pull & Legs', 'back/legs' from plan
  returning id, plan_id
)
insert into public.workout_exercises (day_id, exercise_id, sets, reps, rest_seconds, "order")
select day1.id, 'bench-press', 4, '8-10', 90, 1 from day1
union all
select day1.id, 'overhead-press', 3, '8-10', 90, 2 from day1
union all
select day2.id, 'back-squat', 4, '8-10', 120, 1 from day2
union all
select day2.id, 'bent-over-row', 3, '8-10', 90, 2 from day2;

-- 4) A couple of food logs
insert into public.food_logs (user_id, meal_type, food_name, calories, protein, carbs, fat, fiber)
values
  ('YOUR_USER_ID', 'breakfast', 'Oatmeal with banana', 350, 10, 60, 6, 8),
  ('YOUR_USER_ID', 'lunch', 'Grilled chicken salad', 450, 40, 20, 18, 5);

-- 5) A progress log
insert into public.progress_logs (user_id, weight, body_fat, notes)
values ('YOUR_USER_ID', 78.5, 18.2, 'morning weigh-in');