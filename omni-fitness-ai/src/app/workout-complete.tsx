import React from "react";
import { View, ScrollView } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { Text, Button, Card, ProgressBar } from "@/components/ui";

const stats = [
  { label: "Duration", value: "45 min", icon: "⏱️" },
  { label: "Exercises", value: "8", icon: "🏋️" },
  { label: "Sets", value: "32", icon: "📊" },
  { label: "Volume", value: "12,450 kg", icon: "💪" },
  { label: "Calories", value: "380 kcal", icon: "🔥" },
];

export default function WorkoutCompleteScreen() {
  return (
    <SafeAreaView className="flex-1 bg-background">
      <ScrollView
        contentContainerStyle={{ flexGrow: 1, padding: 24 }}
        showsVerticalScrollIndicator={false}
      >
        {/* Celebration */}
        <View className="items-center mb-8">
          <Text variant="display" className="mb-4">
            🎉
          </Text>
          <Text variant="h1" className="text-center mb-2">
            Workout Complete!
          </Text>
          <Text variant="body" className="text-text-secondary text-center">
            Great job! You've completed your workout.
          </Text>
        </View>

        {/* Stats Grid */}
        <View className="flex-row flex-wrap gap-3 mb-8">
          {stats.map((stat, index) => (
            <View key={index} className="w-[48%]">
              <Card variant="elevated">
                <Text variant="h2" className="mb-2">
                  {stat.icon}
                </Text>
                <Text variant="stat" className="mb-1">
                  {stat.value}
                </Text>
                <Text variant="caption" className="text-text-secondary">
                  {stat.label}
                </Text>
              </Card>
            </View>
          ))}
        </View>

        {/* Progress Comparison */}
        <Card variant="elevated" className="mb-8">
          <Text variant="h3" className="mb-4">
            Progress vs Last Workout
          </Text>
          <View className="gap-4">
            <View>
              <View className="flex-row justify-between mb-2">
                <Text variant="bodySmall" className="text-text-secondary">
                  Volume
                </Text>
                <Text variant="bodySmall" className="text-success">
                  +8%
                </Text>
              </View>
              <ProgressBar progress={85} color="#34C759" />
            </View>
            <View>
              <View className="flex-row justify-between mb-2">
                <Text variant="bodySmall" className="text-text-secondary">
                  Reps
                </Text>
                <Text variant="bodySmall" className="text-success">
                  +5%
                </Text>
              </View>
              <ProgressBar progress={78} color="#208AEF" />
            </View>
            <View>
              <View className="flex-row justify-between mb-2">
                <Text variant="bodySmall" className="text-text-secondary">
                  Duration
                </Text>
                <Text variant="bodySmall" className="text-warning">
                  -2%
                </Text>
              </View>
              <ProgressBar progress={70} color="#FF9500" />
            </View>
          </View>
        </Card>

        {/* AI Message */}
        <Card variant="ai" className="mb-8">
          <View className="flex-row items-center gap-2 mb-3">
            <View className="w-8 h-8 rounded-full bg-ai-glow/30 items-center justify-center">
              <Text variant="caption" className="text-ai-glow">
                AI
              </Text>
            </View>
            <Text variant="h3" className="text-ai-glow">
              OMNI AI
            </Text>
          </View>
          <Text variant="body" className="text-text-secondary">
            Great session! Your bench press volume increased 8% this week. Keep
            up the consistent training and you'll reach your goals in no time.
          </Text>
        </Card>

        {/* Actions */}
        <View className="gap-3">
          <Button
            title="View Progress"
            size="lg"
            onPress={() => router.push("/(tabs)/tracking")}
          />
          <Button
            title="Back to Home"
            variant="secondary"
            size="lg"
            onPress={() => router.replace("/")}
          />
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}
