# ThriveLens - Fitness App Synopsis

## Overview

ThriveLens is a comprehensive fitness application that combines exercise tracking, nutrition monitoring, and AI-powered insights to help users achieve their health and fitness goals. The app provides personalized workout plans, meal tracking with AI food analysis, and progress monitoring with intelligent recommendations.

---

## Core Features

### 1. User Onboarding & Profiles
- **Personal Information**: Age, height, sex, weight collection during signup
- **Goal Setting**: Choose between lose weight, maintain, gain muscle, or improve fitness
- **Activity Levels**: Sedentary to very active classifications
- **Automatic Calculations**: BMR, TDEE, and daily nutrition targets calculated from profile data
- **Progress Tracking**: Weekly weigh-ins with historical data and trends

### 2. Exercise Library (300+ Exercises)
- **Scraped from Muscle & Strength**: Real exercise data with instructions and tips
- **Body Part Filtering**: Chest, Back, Shoulders, Arms, Legs, Core, Cardio
- **Difficulty Levels**: Beginner, Intermediate, Advanced
- **Equipment Filtering**: Barbell, Dumbbells, Cables, Machine, Bodyweight, etc.
- **Detailed Information**: Step-by-step instructions, muscle groups, exercise images
- **Custom Exercises**: Users can create and save their own exercises

### 3. Workout Tracker
- **Session Planning**: Create workouts with scheduled dates
- **Exercise Selection**: Choose from library or custom exercises
- **Set Tracking**: Reps, weight, duration, RPE (Rate of Perceived Exertion)
- **Progress Logging**: Mark sets as completed, track performance over time
- **Workout History**: View past workouts with duration and exercises performed

### 4. Nutrition & Meal Tracker
- **Meal Logging**: Breakfast, lunch, dinner, and snacks
- **Food Items**: Name, quantity, unit, calories, protein, carbs, fat
- **AI Food Analysis**: Camera/photo upload for automatic food recognition
- **Daily Summaries**: Total calories and macros vs. targets
- **Nutrition Targets**: Personalized based on goals (calories, protein, carbs, fat)

### 5. Recipe Database
- **Curated Recipes**: Healthy recipes with nutritional information
- **Ingredient-Based Search**: Find recipes by available ingredients
- **AI Recipe Suggestions**: Get recipe ideas based on goals and preferences
- **Cooking Instructions**: Step-by-step cooking guides
- **Nutritional Breakdown**: Calories, protein, carbs, fat per serving

### 6. AI-Powered Features
- **Progress Analysis**: AI monitors weight trends and provides insights
- **Personalized Tips**: Nutrition, exercise, and motivation tips
- **Workout Suggestions**: AI-generated workout plans based on goals
- **Recipe Recommendations**: Meal suggestions based on dietary preferences
- **Food Recognition**: Photo-based meal analysis

### 7. Progress Dashboard
- **Weight Tracking**: Log weekly weights with chart visualization
- **Body Metrics**: BMI calculation and category
- **Nutrition Charts**: Daily/weekly calorie and macro tracking
- **Workout Analytics**: Frequency, duration, and volume trends
- **Goal Progress**: Visual progress toward target weight

---

## Tech Stack

### Frontend
- **Framework**: React Native with Expo
- **Navigation**: React Navigation (Stack + Tab)
- **State Management**: Zustand
- **UI Components**: Custom dark theme with consistent design system
- **Camera**: Expo Camera & Image Picker for food photos
- **Charts**: React Native Chart Kit for progress visualization

### Backend
- **Runtime**: Node.js with TypeScript
- **Framework**: Express.js
- **Database**: PostgreSQL
- **Authentication**: JWT (JSON Web Tokens)
- **Validation**: Express Validator + Zod
- **AI Integration**: OpenAI API (GPT-4o)

### Infrastructure
- **Containerization**: Docker Compose for PostgreSQL & Redis
- **File Storage**: Local uploads with Sharp for image processing
- **Rate Limiting**: In-memory rate limiter (Redis-ready)

---

## Database Schema

### Core Tables
- `users` - User accounts and authentication
- `user_profiles` - Personal info, goals, nutrition targets
- `exercises` - Exercise library (scraped + custom)
- `workout_sessions` - Planned and completed workouts
- `workout_exercises` - Exercises within workouts
- `exercise_sets` - Individual set data (reps, weight, etc.)
- `meals` - Meal logs with daily totals
- `food_items` - Individual food items in meals
- `weight_entries` - Weekly weight tracking
- `ai_tips` - Personalized AI recommendations
- `recipes` - Recipe database
- `nutrition_plans` - Meal plans
- `workout_plans` - Workout programs

---

## API Endpoints

### Authentication
- `POST /api/auth/register` - Create account
- `POST /api/auth/login` - Sign in
- `POST /api/auth/refresh` - Refresh token
- `POST /api/auth/logout` - Sign out

### Profile
- `GET /api/profile` - Get user profile
- `POST /api/profile` - Create/update profile
- `GET /api/profile/nutrition-targets` - Get calculated targets

### Exercises
- `GET /api/exercises` - List exercises (filterable)
- `GET /api/exercises/:id` - Get exercise details
- `POST /api/exercises` - Create custom exercise

### Workouts
- `GET /api/workouts` - List workout sessions
- `POST /api/workouts` - Create workout session
- `PATCH /api/workouts/:id/complete` - Mark as completed

### Meals
- `GET /api/meals` - List meals (filterable by date)
- `GET /api/meals/daily-summary` - Get daily totals
- `POST /api/meals` - Log a meal
- `POST /api/meals/analyze` - AI food image analysis

### Progress
- `GET /api/progress/metrics` - Get progress metrics
- `GET /api/progress/weight-history` - Weight tracking data
- `POST /api/progress/weight` - Add weight entry
- `GET /api/progress/charts/*` - Chart data endpoints

### AI
- `GET /api/ai/tips` - Get personalized tips
- `POST /api/ai/generate-tips` - Generate new tips
- `POST /api/ai/analyze-progress` - AI progress analysis
- `POST /api/ai/recipe-suggestions` - Get recipe ideas
- `POST /api/ai/workout-suggestions` - Get workout ideas

### Recipes
- `GET /api/recipes` - List recipes
- `GET /api/recipes/search` - Search by ingredients
- `POST /api/recipes` - Create custom recipe

---

## Project Structure

```
ThriveLens 2026/
├── backend/                    # Express API server
│   ├── src/
│   │   ├── config/            # Database, JWT, app config
│   │   ├── controllers/       # Route handlers
│   │   ├── middleware/        # Auth, validation, errors
│   │   ├── models/           # Database queries
│   │   ├── routes/           # API routes
│   │   ├── services/         # Business logic
│   │   ├── utils/            # Helpers, errors, JWT
│   │   └── db/               # Migrations, seeds, scraper
│   └── package.json
├── frontend/                   # React Native app
│   ├── app/                   # Expo Router screens
│   │   ├── (auth)/           # Login, Register
│   │   ├── (tabs)/           # Main tab screens
│   │   └── onboarding/       # Profile setup
│   └── src/
│       ├── components/       # Reusable UI components
│       ├── context/          # Zustand stores
│       ├── services/         # API client
│       └── utils/            # Theme, helpers
├── shared/                     # Shared TypeScript types
├── docker-compose.yml         # PostgreSQL & Redis
└── package.json               # Root workspace config
```

---

## Getting Started

### Prerequisites
- Node.js 18+
- Docker & Docker Compose
- PostgreSQL (or use Docker)

### Installation

```bash
# Clone repository
git clone <repo-url>
cd "ThriveLens 2026"

# Start database
docker-compose up -d

# Install backend dependencies
cd backend
npm install

# Run migrations
npm run db:migrate

# Seed exercises (from muscleandstrength.com)
npm run db:seed-scraped

# Start backend server
npm run dev

# In new terminal - install frontend
cd ../frontend
npm install

# Start Expo
npx expo start
```

### Environment Variables

**Backend (.env)**
```
PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_USER=thrivelens
DB_PASSWORD=thrivelens_dev_password
DB_NAME=thrivelens
JWT_SECRET=your-secret-key
OPENAI_API_KEY=your-openai-key  # Optional for AI features
```

**Frontend (.env)**
```
EXPO_PUBLIC_API_URL=http://localhost:3000/api
```

---

## Exercise Data Source

Exercises are scraped from [muscleandstrength.com](https://www.muscleandstrength.com/exercises) with proper attribution. The scraper extracts:
- Exercise name and description
- Target muscle groups
- Equipment required
- Difficulty level
- Step-by-step instructions
- Form tips
- Exercise images

**Scraping Commands:**
```bash
npm run db:scrape        # Scrape all exercises (~5-10 min)
npm run db:seed-scraped  # Seed database with scraped data
```

---

## AI Features (Optional)

Requires OpenAI API key for:
- **Food Recognition**: Analyze meal photos
- **Progress Insights**: AI-powered weight trend analysis
- **Recipe Suggestions**: Personalized meal recommendations
- **Workout Plans**: AI-generated training programs
- **Motivational Tips**: Context-aware fitness tips

---

## Future Enhancements

- [ ] Social features (friends, challenges)
- [ ] Wearable device integration (Apple Watch, Fitbit)
- [ ] Barcode scanning for packaged foods
- [ ] Workout video demonstrations
- [ ] Rest timer between sets
- [ ] Superset/circuit support
- [ ] Export data to CSV/PDF
- [ ] Offline mode with sync
- [ ] Multi-language support
- [ ] Dark/light theme toggle

---

## License

This project is for educational purposes. Exercise data sourced from muscleandstrength.com.

---

*Built with React Native, Express.js, PostgreSQL, and OpenAI*