import React, { useState, useMemo } from "react";
import { View, ScrollView } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { router } from "expo-router";
import Animated, { FadeInDown, Easing } from "react-native-reanimated";
import { Dumbbell, ChevronRight, BookOpen } from "lucide-react-native";
import { Text, Button, Card, WorkoutCard, PressableScale } from "@/components/ui";

const EASE_OUT = Easing.bezier(0.23, 1, 0.32, 1);

const categories = [
  "All",
  "Strength",
  "Hypertrophy",
  "Fat Loss",
  "Full Body",
  "Upper Body",
  "Lower Body",
  "Push",
  "Pull",
  "Legs",
  "Cardio",
];

const workouts = [
  {
    id: "1",
    title: "Chest & Triceps",
    duration: "45 min",
    difficulty: "Intermediate",
    muscleGroups: ["Chest", "Triceps"],
    exerciseCount: 8,
  },
  {
    id: "2",
    title: "Back & Biceps",
    duration: "50 min",
    difficulty: "Intermediate",
    muscleGroups: ["Back", "Biceps"],
    exerciseCount: 9,
  },
  {
    id: "3",
    title: "Leg Day",
    duration: "60 min",
    difficulty: "Advanced",
    muscleGroups: ["Quads", "Hamstrings", "Glutes"],
    exerciseCount: 10,
  },
  {
    id: "4",
    title: "Shoulders & Arms",
    duration: "40 min",
    difficulty: "Beginner",
    muscleGroups: ["Shoulders", "Biceps", "Triceps"],
    exerciseCount: 7,
  },
  {
    id: "5",
    title: "Full Body HIIT",
    duration: "30 min",
    difficulty: "Advanced",
    muscleGroups: ["Full Body"],
    exerciseCount: 12,
  },
];

export default function WorkoutScreen() {
  const [selectedCategory, setSelectedCategory] = useState("All");

  const enteringHeader = useMemo(() => FadeInDown.duration(500).delay(0).easing(EASE_OUT), []);
  const enteringLibrary = useMemo(() => FadeInDown.duration(500).delay(100).easing(EASE_OUT), []);
  const enteringLevel = useMemo(() => FadeInDown.duration(500).delay(200).easing(EASE_OUT), []);
  const enteringCategories = useMemo(() => FadeInDown.duration(500).delay(300).easing(EASE_OUT), []);
  const enteringAI = useMemo(() => FadeInDown.duration(500).delay(400).easing(EASE_OUT), []);

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: 100 }}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <Animated.View entering={enteringHeader} className="px-6 py-4">
          <Text variant="h1">Workout</Text>
          <Text variant="body" className="text-text-secondary mt-1">
            Find the perfect workout for you
          </Text>
        </Animated.View>

        {/* Exercise Library Button */}
        <Animated.View entering={enteringLibrary} className="px-6 mb-6">
          <PressableScale
            onPress={() => router.push("/exercise-library")}
            className="bg-surface rounded-2xl p-4 border border-border flex-row items-center"
          >
            <View className="w-14 h-14 rounded-xl bg-primary/20 items-center justify-center mr-4">
              <BookOpen size={24} color="#208AEF" />
            </View>
            <View className="flex-1">
              <Text variant="body" className="font-semibold text-white">
                Exercise Library
              </Text>
              <Text variant="bodySmall" className="text-text-secondary mt-1">
                1500+ exercises with video demos
              </Text>
            </View>
            <ChevronRight size={20} color="#6B6B80" />
          </PressableScale>
        </Animated.View>

        {/* Fitness Level */}
        <Animated.View entering={enteringLevel} className="px-6 mb-6">
          <Text variant="h3" className="mb-3">
            Fitness Level
          </Text>
          <View className="flex-row gap-3">
            {["Beginner", "Intermediate", "Advanced"].map((level) => (
              <PressableScale
                key={level}
                className="flex-1 bg-surface py-3 rounded-xl items-center border border-border"
                onPress={() => {}}
              >
                <Text variant="bodySmall" className="text-text-secondary">
                  {level}
                </Text>
              </PressableScale>
            ))}
          </View>
        </Animated.View>

        {/* Categories */}
        <Animated.View entering={enteringCategories} className="mb-6">
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={{ paddingHorizontal: 24 }}
          >
            <View className="flex-row gap-2">
              {categories.map((category) => (
                <PressableScale
                  key={category}
                  className={`px-4 py-2 rounded-full ${
                    selectedCategory === category
                      ? "bg-primary"
                      : "bg-surface-elevated"
                  }`}
                  onPress={() => setSelectedCategory(category)}
                >
                  <Text
                    variant="bodySmall"
                    className={
                      selectedCategory === category
                        ? "text-white"
                        : "text-text-secondary"
                    }
                  >
                    {category}
                  </Text>
                </PressableScale>
              ))}
            </View>
          </ScrollView>
        </Animated.View>

        {/* AI Generate Button */}
        <Animated.View entering={enteringAI} className="px-6 mb-6">
          <PressableScale onPress={() => router.push("/ai-coach")}>
            <Card variant="ai">
              <View className="flex-row items-center gap-3">
                <View className="w-12 h-12 rounded-full bg-ai-glow/30 items-center justify-center">
                  <Text variant="h3" className="text-ai-glow">
                    🤖
                  </Text>
                </View>
                <View className="flex-1">
                  <Text variant="body" className="font-semibold">
                    Generate AI Workout
                  </Text>
                  <Text variant="bodySmall" className="text-text-secondary">
                    Let AI create a personalized workout for you
                  </Text>
                </View>
                <Text variant="body" className="text-ai-glow">
                  →
                </Text>
              </View>
            </Card>
          </PressableScale>
        </Animated.View>

        {/* Workouts List */}
        <View className="px-6">
          <Text variant="h3" className="mb-4">
            Available Workouts
          </Text>
          <View className="gap-4">
            {workouts.map((workout, index) => (
              <Animated.View
                key={workout.id}
                entering={FadeInDown.duration(500).delay(500 + index * 100).easing(EASE_OUT)}
              >
                <WorkoutCard
                  title={workout.title}
                  duration={workout.duration}
                  difficulty={workout.difficulty}
                  muscleGroups={workout.muscleGroups}
                  exerciseCount={workout.exerciseCount}
                  onPress={() => {}}
                />
              </Animated.View>
            ))}
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}
