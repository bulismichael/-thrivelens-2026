import React, { useMemo } from "react";
import { View, Pressable, ScrollView } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import Animated, {
  useSharedValue,
  useAnimatedScrollHandler,
  useAnimatedStyle,
  interpolate,
  Extrapolation,
  FadeInDown,
  Easing,
} from "react-native-reanimated";
import {
  Text,
  Button,
  Card,
  Avatar,
  ProgressBar,
  AIRecommendationCard,
  WorkoutCard,
  PressableScale,
} from "@/components/ui";

const EASE_OUT = Easing.bezier(0.23, 1, 0.32, 1);

const AnimatedScrollView = Animated.createAnimatedComponent(ScrollView);

function getGreeting(): string {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 17) return "Good afternoon";
  return "Good evening";
}

export default function HomeScreen() {
  const scrollY = useSharedValue(0);

  const onScroll = useAnimatedScrollHandler((e) => {
    scrollY.set(e.contentOffset.y);
  });

  const headerStyle = useAnimatedStyle(() => ({
    opacity: interpolate(scrollY.get(), [0, 60], [1, 0], Extrapolation.CLAMP),
    transform: [
      { translateY: interpolate(scrollY.get(), [0, 60], [0, -12], Extrapolation.CLAMP) },
    ],
  }));

  const user = {
    name: "Alex",
    greeting: getGreeting(),
  };

  const todayWorkout = {
    title: "Upper Body Strength",
    duration: "45 min",
    difficulty: "Intermediate",
    muscleGroups: ["Chest", "Back", "Shoulders"],
    exerciseCount: 8,
  };

  const nutrition = {
    calories: { consumed: 1450, target: 2200 },
    protein: { consumed: 95, target: 165 },
    carbs: { consumed: 180, target: 275 },
    fat: { consumed: 45, target: 73 },
  };

  const enteringWorkout = useMemo(() => FadeInDown.duration(500).delay(100).easing(EASE_OUT), []);
  const enteringNutrition = useMemo(() => FadeInDown.duration(500).delay(200).easing(EASE_OUT), []);
  const enteringAI = useMemo(() => FadeInDown.duration(500).delay(300).easing(EASE_OUT), []);
  const enteringActions = useMemo(() => FadeInDown.duration(500).delay(400).easing(EASE_OUT), []);
  const enteringRecent = useMemo(() => FadeInDown.duration(500).delay(500).easing(EASE_OUT), []);
  const enteringWeekly = useMemo(() => FadeInDown.duration(500).delay(600).easing(EASE_OUT), []);

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <AnimatedScrollView
        onScroll={onScroll}
        scrollEventThrottle={16}
        contentContainerStyle={{ paddingBottom: 100 }}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <Animated.View style={headerStyle} className="flex-row justify-between items-center px-6 py-4">
          <View>
            <Text variant="bodySmall" className="text-text-secondary">
              {user.greeting}
            </Text>
            <Text variant="h2">{user.name}</Text>
          </View>
          <View className="flex-row items-center gap-3">
            <PressableScale
              className="w-10 h-10 rounded-full bg-surface-elevated items-center justify-center"
              onPress={() => {}}
            >
              <Text variant="body">🔔</Text>
            </PressableScale>
            <PressableScale onPress={() => router.push("/profile")}>
              <Avatar initials="A" size="md" />
            </PressableScale>
          </View>
        </Animated.View>

        {/* Today's Workout Hero */}
        <Animated.View entering={enteringWorkout} className="px-6 mb-6">
          <Card variant="elevated">
            <Text variant="bodySmall" className="text-text-secondary mb-2">
              Today's Workout
            </Text>
            <Text variant="h2" className="mb-3">
              Ready for today's workout?
            </Text>

            <View className="bg-surface-highlight rounded-xl p-4 mb-4">
              <View className="flex-row justify-between items-start mb-3">
                <Text variant="h3">{todayWorkout.title}</Text>
                <View className="bg-primary/20 px-3 py-1 rounded-full">
                  <Text variant="caption" className="text-primary">
                    {todayWorkout.difficulty}
                  </Text>
                </View>
              </View>

              <View className="flex-row items-center gap-4 mb-3">
                <View className="flex-row items-center gap-1">
                  <Text variant="bodySmall" className="text-text-secondary">
                    ⏱️ {todayWorkout.duration}
                  </Text>
                </View>
                <View className="flex-row items-center gap-1">
                  <Text variant="bodySmall" className="text-text-secondary">
                    💪 {todayWorkout.exerciseCount} exercises
                  </Text>
                </View>
              </View>

              <View className="flex-row flex-wrap gap-2">
                {todayWorkout.muscleGroups.map((group, index) => (
                  <View
                    key={index}
                    className="bg-surface px-3 py-1 rounded-full"
                  >
                    <Text variant="caption" className="text-text-secondary">
                      {group}
                    </Text>
                  </View>
                ))}
              </View>
            </View>

            <Button
              title="Start Workout"
              size="lg"
              onPress={() => router.push("/active-workout")}
            />
          </Card>
        </Animated.View>

        {/* Nutrition Summary */}
        <Animated.View entering={enteringNutrition} className="px-6 mb-6">
          <Card variant="elevated">
            <View className="flex-row justify-between items-center mb-4">
              <Text variant="h3">Today's Nutrition</Text>
              <PressableScale onPress={() => router.push("/(tabs)/nutrition")}>
                <Text variant="bodySmall" className="text-primary">
                  View All
                </Text>
              </PressableScale>
            </View>

            {/* Calories */}
            <View className="mb-4">
              <View className="flex-row justify-between mb-2">
                <Text variant="body" className="text-text-secondary">
                  Calories
                </Text>
                <Text variant="body" className="text-text-primary">
                  {nutrition.calories.consumed} / {nutrition.calories.target} kcal
                </Text>
              </View>
              <ProgressBar
                progress={(nutrition.calories.consumed / nutrition.calories.target) * 100}
                color="#FF6B35"
              />
            </View>

            {/* Macros */}
            <View className="flex-row justify-between">
              <View className="flex-1 items-center">
                <Text variant="caption" className="text-text-tertiary mb-1">
                  Protein
                </Text>
                <Text variant="statSmall" className="text-primary">
                  {nutrition.protein.consumed}g
                </Text>
                <Text variant="caption" className="text-text-tertiary">
                  / {nutrition.protein.target}g
                </Text>
              </View>
              <View className="flex-1 items-center">
                <Text variant="caption" className="text-text-tertiary mb-1">
                  Carbs
                </Text>
                <Text variant="statSmall" className="text-success">
                  {nutrition.carbs.consumed}g
                </Text>
                <Text variant="caption" className="text-text-tertiary">
                  / {nutrition.carbs.target}g
                </Text>
              </View>
              <View className="flex-1 items-center">
                <Text variant="caption" className="text-text-tertiary mb-1">
                  Fat
                </Text>
                <Text variant="statSmall" className="text-warning">
                  {nutrition.fat.consumed}g
                </Text>
                <Text variant="caption" className="text-text-tertiary">
                  / {nutrition.fat.target}g
                </Text>
              </View>
            </View>
          </Card>
        </Animated.View>

        {/* AI Coach Card */}
        <Animated.View entering={enteringAI} className="px-6 mb-6">
          <AIRecommendationCard
            title="OMNI AI"
            message="You're 38g short of your protein goal today. I found a meal that fits your remaining calories."
            actionLabel="View Recommendation"
            onAction={() => router.push("/ai-coach")}
          />
        </Animated.View>

        {/* Quick Actions */}
        <Animated.View entering={enteringActions} className="px-6 mb-6">
          <Text variant="h3" className="mb-4">
            Quick Actions
          </Text>
          <View className="flex-row gap-3">
            <PressableScale
              className="flex-1 bg-surface p-4 rounded-xl items-center"
              onPress={() => router.push("/food-scanner")}
            >
              <Text variant="h2" className="mb-2">
                📷
              </Text>
              <Text variant="bodySmall" className="text-text-secondary text-center">
                Scan Food
              </Text>
            </PressableScale>
            <PressableScale
              className="flex-1 bg-surface p-4 rounded-xl items-center"
              onPress={() => router.push("/ai-coach")}
            >
              <Text variant="h2" className="mb-2">
                🤖
              </Text>
              <Text variant="bodySmall" className="text-text-secondary text-center">
                AI Coach
              </Text>
            </PressableScale>
            <PressableScale
              className="flex-1 bg-surface p-4 rounded-xl items-center"
              onPress={() => router.push("/(tabs)/workout")}
            >
              <Text variant="h2" className="mb-2">
                💪
              </Text>
              <Text variant="bodySmall" className="text-text-secondary text-center">
                Workouts
              </Text>
            </PressableScale>
          </View>
        </Animated.View>

        {/* Recent Workouts */}
        <Animated.View entering={enteringRecent} className="px-6 mb-6">
          <View className="flex-row justify-between items-center mb-4">
            <Text variant="h3">Recent Workouts</Text>
            <PressableScale onPress={() => router.push("/(tabs)/workout")}>
              <Text variant="bodySmall" className="text-primary">
                View All
              </Text>
            </PressableScale>
          </View>
          <WorkoutCard
            title="Chest & Triceps"
            duration="45 min"
            difficulty="Intermediate"
            muscleGroups={["Chest", "Triceps"]}
            exerciseCount={8}
            onPress={() => {}}
          />
        </Animated.View>

        {/* Weekly Progress */}
        <Animated.View entering={enteringWeekly} className="px-6 mb-6">
          <Text variant="h3" className="mb-4">
            Weekly Progress
          </Text>
          <Card variant="elevated">
            <View className="flex-row justify-between mb-4">
              <View className="items-center">
                <Text variant="stat" className="text-primary">
                  4
                </Text>
                <Text variant="caption" className="text-text-secondary">
                  Workouts
                </Text>
              </View>
              <View className="items-center">
                <Text variant="stat" className="text-accent">
                  12,450
                </Text>
                <Text variant="caption" className="text-text-secondary">
                  Volume (kg)
                </Text>
              </View>
              <View className="items-center">
                <Text variant="stat" className="text-success">
                  85%
                </Text>
                <Text variant="caption" className="text-text-secondary">
                  Completion
                </Text>
              </View>
            </View>
            <ProgressBar
              progress={71}
              color="#208AEF"
              showLabel
              label="Weekly Goal"
            />
          </Card>
        </Animated.View>
      </AnimatedScrollView>
    </SafeAreaView>
  );
}
