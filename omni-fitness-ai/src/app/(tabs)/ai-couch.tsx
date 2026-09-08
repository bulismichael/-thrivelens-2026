import React from "react";
import { View, ScrollView, Pressable } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Text, Card, Avatar } from "@/components/ui";

export default function AICouchScreen() {
  const user = {
    name: "Alex",
    age: 28,
    weight: 78,
    height: 180,
    fitnessGoal: "Build Muscle",
    fitnessLevel: "Intermediate",
    weeklyWorkouts: 4,
    memberSince: "Jan 2026",
  };

  const quickInfo = [
    { label: "Age", value: `${user.age} years` },
    { label: "Weight", value: `${user.weight} kg` },
    { label: "Height", value: `${user.height} cm` },
    { label: "Goal", value: user.fitnessGoal },
    { label: "Level", value: user.fitnessLevel },
    { label: "Workouts/Week", value: `${user.weeklyWorkouts}` },
  ];

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: 100 }}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View className="flex-row justify-between items-center px-6 py-4">
          <View>
            <Text variant="bodySmall" className="text-text-secondary">
              Your AI Assistant
            </Text>
            <Text variant="h2">AI Couch</Text>
          </View>
          <Avatar initials="A" size="md" />
        </View>

        {/* User Profile Card */}
        <View className="px-6 mb-6">
          <Card variant="elevated">
            <View className="items-center mb-4">
              <Avatar initials="A" size="lg" />
              <Text variant="h3" className="mt-3">
                {user.name}
              </Text>
              <Text variant="bodySmall" className="text-text-secondary">
                Member since {user.memberSince}
              </Text>
            </View>

            <View className="flex-row flex-wrap justify-between">
              {quickInfo.map((item, index) => (
                <View key={index} className="w-[48%] bg-surface-highlight rounded-xl p-3 mb-3 items-center">
                  <Text variant="caption" className="text-text-tertiary mb-1">
                    {item.label}
                  </Text>
                  <Text variant="body" className="text-text-primary font-semibold">
                    {item.value}
                  </Text>
                </View>
              ))}
            </View>
          </Card>
        </View>

        {/* AI Couch Info Sections */}
        <View className="px-6 mb-6">
          <Text variant="h3" className="mb-4">
            What I Know About You
          </Text>

          <Card variant="elevated" className="mb-3">
            <Text variant="bodyLarge" className="mb-2 font-semibold">
              Fitness Profile
            </Text>
            <Text variant="bodySmall" className="text-text-secondary">
              Your fitness goal is to {user.fitnessGoal.toLowerCase()} with a{" "}
              {user.fitnessLevel.toLowerCase()} experience level. You train{" "}
              {user.weeklyWorkouts} times per week.
            </Text>
          </Card>

          <Card variant="elevated" className="mb-3">
            <Text variant="bodyLarge" className="mb-2 font-semibold">
              Body Stats
            </Text>
            <Text variant="bodySmall" className="text-text-secondary">
              You are {user.age} years old, weighing {user.weight}kg at{" "}
              {user.height}cm tall. Your BMI is{" "}
              {(user.weight / ((user.height / 100) ** 2)).toFixed(1)}.
            </Text>
          </Card>

          <Card variant="elevated" className="mb-3">
            <Text variant="bodyLarge" className="mb-2 font-semibold">
              Workout History
            </Text>
            <Text variant="bodySmall" className="text-text-secondary">
              You've completed 48 workouts this month with a 85% completion
              rate. Your most trained muscle groups are chest and back.
            </Text>
          </Card>
        </View>

        {/* Placeholder for future link */}
        <View className="px-6 mb-6">
          <Card variant="elevated">
            <View className="items-center py-4">
              <Text variant="h3" className="mb-2">
                🔗 Coming Soon
              </Text>
              <Text variant="bodySmall" className="text-text-secondary text-center">
                Full AI Couch integration with personalized coaching will be
                available after fine-tuning the specialist model.
              </Text>
            </View>
          </Card>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}
