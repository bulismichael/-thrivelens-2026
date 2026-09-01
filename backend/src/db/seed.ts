import { pool } from '../config/database';

const exercises = [
  // Chest
  { name: 'Bench Press', description: 'Classic chest exercise with barbell', body_part: 'chest', difficulty: 'intermediate', muscle_groups: ['Pectoralis Major', 'Triceps', 'Anterior Deltoid'], equipment: ['Barbell', 'Bench'], instructions: ['Lie on bench with feet flat on floor', 'Grip barbell slightly wider than shoulders', 'Lower bar to chest', 'Press up to starting position'] },
  { name: 'Push-up', description: 'Bodyweight chest exercise', body_part: 'chest', difficulty: 'beginner', muscle_groups: ['Pectoralis Major', 'Triceps', 'Core'], equipment: ['Bodyweight'], instructions: ['Start in plank position', 'Lower body until chest nearly touches floor', 'Push back up to starting position'] },
  { name: 'Dumbbell Fly', description: 'Isolation exercise for chest', body_part: 'chest', difficulty: 'intermediate', muscle_groups: ['Pectoralis Major'], equipment: ['Dumbbells', 'Bench'], instructions: ['Lie on bench holding dumbbells above chest', 'Lower arms out to sides in arc motion', 'Bring dumbbells back together above chest'] },
  
  // Back
  { name: 'Pull-up', description: 'Bodyweight back exercise', body_part: 'back', difficulty: 'intermediate', muscle_groups: ['Latissimus Dorsi', 'Biceps', 'Rhomboids'], equipment: ['Pull-up Bar'], instructions: ['Hang from bar with palms facing away', 'Pull body up until chin clears bar', 'Lower back down with control'] },
  { name: 'Bent Over Row', description: 'Compound back exercise', body_part: 'back', difficulty: 'intermediate', muscle_groups: ['Latissimus Dorsi', 'Rhomboids', 'Biceps'], equipment: ['Barbell'], instructions: ['Hinge at hips with slight knee bend', 'Grip barbell with overhand grip', 'Pull barbell to lower chest', 'Lower with control'] },
  { name: 'Deadlift', description: 'Full body compound lift', body_part: 'back', difficulty: 'advanced', muscle_groups: ['Erector Spinae', 'Glutes', 'Hamstrings', 'Traps'], equipment: ['Barbell'], instructions: ['Stand with feet hip-width apart', 'Grip barbell just outside knees', 'Drive through heels to stand up', 'Lower with control'] },
  
  // Shoulders
  { name: 'Overhead Press', description: 'Standing barbell shoulder press', body_part: 'shoulders', difficulty: 'intermediate', muscle_groups: ['Anterior Deltoid', 'Medial Deltoid', 'Triceps'], equipment: ['Barbell'], instructions: ['Stand with feet shoulder-width apart', 'Press barbell overhead', 'Lower to shoulder level', 'Repeat'] },
  { name: 'Lateral Raise', description: 'Isolation for side delts', body_part: 'shoulders', difficulty: 'beginner', muscle_groups: ['Medial Deltoid'], equipment: ['Dumbbells'], instructions: ['Stand with dumbbells at sides', 'Raise arms out to sides until parallel', 'Lower with control'] },
  
  // Arms
  { name: 'Bicep Curl', description: 'Classic bicep exercise', body_part: 'arms', difficulty: 'beginner', muscle_groups: ['Biceps', 'Brachialis'], equipment: ['Dumbbells'], instructions: ['Stand with dumbbells at sides', 'Curl weights up keeping elbows still', 'Lower with control'] },
  { name: 'Tricep Dip', description: 'Bodyweight tricep exercise', body_part: 'arms', difficulty: 'intermediate', muscle_groups: ['Triceps', 'Anterior Deltoid'], equipment: ['Parallel Bars'], instructions: ['Support body on parallel bars', 'Lower body by bending elbows', 'Push back up to starting position'] },
  
  // Legs
  { name: 'Squat', description: 'King of leg exercises', body_part: 'legs', difficulty: 'intermediate', muscle_groups: ['Quadriceps', 'Glutes', 'Hamstrings'], equipment: ['Barbell'], instructions: ['Stand with bar on upper back', 'Descend by pushing hips back', 'Go to parallel or below', 'Drive up through heels'] },
  { name: 'Romanian Deadlift', description: 'Hip hinge for hamstrings', body_part: 'legs', difficulty: 'intermediate', muscle_groups: ['Hamstrings', 'Glutes', 'Erector Spinae'], equipment: ['Barbell'], instructions: ['Stand with feet hip-width apart', 'Hinge at hips keeping legs straight', 'Lower barbell along legs', 'Drive hips forward to stand'] },
  { name: 'Lunges', description: 'Single leg exercise', body_part: 'legs', difficulty: 'beginner', muscle_groups: ['Quadriceps', 'Glutes', 'Hamstrings'], equipment: ['Bodyweight'], instructions: ['Step forward with one leg', 'Lower back knee toward floor', 'Push back to starting position', 'Alternate legs'] },
  
  // Core
  { name: 'Plank', description: 'Isometric core exercise', body_part: 'core', difficulty: 'beginner', muscle_groups: ['Transverse Abdominis', 'Rectus Abdominis'], equipment: ['Bodyweight'], instructions: ['Start in push-up position on forearms', 'Keep body in straight line', 'Hold position without sagging'] },
  { name: 'Russian Twist', description: 'Rotational core exercise', body_part: 'core', difficulty: 'beginner', muscle_groups: ['Obliques', 'Rectus Abdominis'], equipment: ['Bodyweight'], instructions: ['Sit with knees bent, feet off floor', 'Lean back slightly', 'Rotate torso side to side', 'Touch hands to floor each side'] },
  { name: 'Hanging Leg Raise', description: 'Advanced core exercise', body_part: 'core', difficulty: 'advanced', muscle_groups: ['Hip Flexors', 'Rectus Abdominis'], equipment: ['Pull-up Bar'], instructions: ['Hang from pull-up bar', 'Raise legs to parallel or higher', 'Lower with control', 'Avoid swinging'] },
  
  // Cardio
  { name: 'Burpee', description: 'Full body cardio exercise', body_part: 'cardio', difficulty: 'intermediate', muscle_groups: ['Full Body'], equipment: ['Bodyweight'], instructions: ['Start standing', 'Drop to squat and place hands on floor', 'Jump feet back to plank', 'Jump feet to hands and stand up with jump'] },
  { name: 'Jumping Jacks', description: 'Classic cardio warmup', body_part: 'cardio', difficulty: 'beginner', muscle_groups: ['Full Body'], equipment: ['Bodyweight'], instructions: ['Start standing with feet together', 'Jump feet apart while raising arms overhead', 'Jump feet back together while lowering arms'] },
  { name: 'Mountain Climbers', description: 'Cardio core exercise', body_part: 'cardio', difficulty: 'beginner', muscle_groups: ['Core', 'Hip Flexors'], equipment: ['Bodyweight'], instructions: ['Start in plank position', 'Drive one knee toward chest', 'Alternate legs quickly', 'Keep hips level'] },
];

async function seed() {
  try {
    console.log('🌱 Seeding database with exercises...');
    
    for (const exercise of exercises) {
      await pool.query(
        `INSERT INTO exercises (name, description, body_part, difficulty, muscle_groups, equipment, instructions, is_custom)
         VALUES ($1, $2, $3, $4, $5, $6, $7, false)
         ON CONFLICT DO NOTHING`,
        [
          exercise.name,
          exercise.description,
          exercise.body_part,
          exercise.difficulty,
          exercise.muscle_groups,
          exercise.equipment,
          exercise.instructions,
        ]
      );
    }
    
    console.log(`✅ Seeded ${exercises.length} exercises`);
    process.exit(0);
  } catch (error) {
    console.error('❌ Seeding failed:', error);
    process.exit(1);
  }
}

seed();