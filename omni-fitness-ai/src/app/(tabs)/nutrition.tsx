import React, { useMemo } from "react";
import { View, ScrollView, Pressable } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import Animated, { FadeInDown, Easing } from "react-native-reanimated";
import {
  Camera,
  ClipboardList,
  CookingPot,
  Sun,
  UtensilsCrossed,
  Moon,
  Cookie,
  Plus,
  Check,
  ChevronRight,
  Flame,
  Droplets,
  Wheat,
  CircleDot,
} from "lucide-react-native";
import { Text, Card, ProgressBar, CircularProgress, PressableScale } from "@/components/ui";

const EASE_OUT = Easing.bezier(0.23, 1, 0.32, 1);

const meals = [
  {
    id: "1",
    title: "Breakfast",
    icon: Sun,
    calories: 420,
    protein: 30,
    carbs: 45,
    fat: 12,
    color: "#FFD93D",
  },
  {
    id: "2",
    title: "Lunch",
    icon: UtensilsCrossed,
    calories: 650,
    protein: 48,
    carbs: 65,
    fat: 18,
    color: "#FF6B35",
  },
  {
    id: "3",
    title: "Dinner",
    icon: Moon,
    calories: 0,
    protein: 0,
    carbs: 0,
    fat: 0,
    color: "#A78BFA",
  },
  {
    id: "4",
    title: "Snacks",
    icon: Cookie,
    calories: 0,
    protein: 0,
    carbs: 0,
    fat: 0,
    color: "#34D399",
  },
];

const nutritionTargets = {
  calories: { consumed: 1070, target: 2200 },
  protein: { consumed: 78, target: 165 },
  carbs: { consumed: 110, target: 275 },
  fat: { consumed: 30, target: 73 },
};

export default function NutritionScreen() {
  const enteringHeader = useMemo(() => FadeInDown.duration(500).delay(0).easing(EASE_OUT), []);
  const enteringOverview = useMemo(() => FadeInDown.duration(500).delay(100).easing(EASE_OUT), []);
  const enteringActions = useMemo(() => FadeInDown.duration(500).delay(200).easing(EASE_OUT), []);
  const enteringMeals = useMemo(() => FadeInDown.duration(500).delay(300).easing(EASE_OUT), []);
  const enteringTotal = useMemo(() => FadeInDown.duration(500).delay(400).easing(EASE_OUT), []);

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: 100 }}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <Animated.View entering={enteringHeader} className="px-6 py-4">
          <Text variant="h1">Nutrition</Text>
          <Text variant="body" className="text-text-secondary mt-1">
            Track your daily nutrition
          </Text>
        </Animated.View>

        {/* Nutrition Overview */}
        <Animated.View entering={enteringOverview} className="px-6 mb-6">
          <Card variant="elevated">
            <Text variant="h3" className="mb-4">
              Today's Target
            </Text>
            <View className="flex-row justify-between">
              {/* Calories */}
              <CircularProgress
                value={nutritionTargets.calories.consumed}
                maxValue={nutritionTargets.calories.target}
                color="#FF6B35"
                size={80}
                strokeWidth={8}
                label="Calories"
              />

              {/* Protein */}
              <CircularProgress
                value={nutritionTargets.protein.consumed}
                maxValue={nutritionTargets.protein.target}
                color="#208AEF"
                size={80}
                strokeWidth={8}
                label="Protein"
              />

              {/* Carbs */}
              <CircularProgress
                value={nutritionTargets.carbs.consumed}
                maxValue={nutritionTargets.carbs.target}
                color="#34C759"
                size={80}
                strokeWidth={8}
                label="Carbs"
              />

              {/* Fat */}
              <CircularProgress
                value={nutritionTargets.fat.consumed}
                maxValue={nutritionTargets.fat.target}
                color="#FF9500"
                size={80}
                strokeWidth={8}
                label="Fat"
              />
            </View>
          </Card>
        </Animated.View>

        {/* Quick Actions */}
        <Animated.View entering={enteringActions} className="px-6 mb-6">
          <View className="flex-row gap-3">
            <PressableScale
              className="flex-1 bg-surface p-4 rounded-xl items-center"
              onPress={() => router.push("/food-scanner")}
            >
              <View className="w-12 h-12 rounded-full bg-accent/20 items-center justify-center mb-3">
                <Camera size={24} color="#FF6B35" />
              </View>
              <Text variant="bodySmall" className="text-text-secondary text-center">
                Scan Food
              </Text>
            </PressableScale>
            <PressableScale
              className="flex-1 bg-surface p-4 rounded-xl items-center"
              onPress={() => {}}
            >
              <View className="w-12 h-12 rounded-full bg-primary/20 items-center justify-center mb-3">
                <ClipboardList size={24} color="#208AEF" />
              </View>
              <Text variant="bodySmall" className="text-text-secondary text-center">
                Meal Plans
              </Text>
            </PressableScale>
            <PressableScale
              className="flex-1 bg-surface p-4 rounded-xl items-center"
              onPress={() => {}}
            >
              <View className="w-12 h-12 rounded-full bg-success/20 items-center justify-center mb-3">
                <CookingPot size={24} color="#34C759" />
              </View>
              <Text variant="bodySmall" className="text-text-secondary text-center">
                My Kitchen
              </Text>
            </PressableScale>
          </View>
        </Animated.View>

        {/* Meal Tracker */}
        <Animated.View entering={enteringMeals} className="px-6 mb-6">
          <View className="flex-row justify-between items-center mb-4">
            <Text variant="h3">Meal Tracker</Text>
            <PressableScale onPress={() => {}} className="flex-row items-center gap-1">
              <Text variant="bodySmall" className="text-primary">
                View All
              </Text>
              <ChevronRight size={14} color="#208AEF" />
            </PressableScale>
          </View>
          <View className="gap-3">
            {meals.map((meal) => {
              const MealIcon = meal.icon;
              return (
                <PressableScale key={meal.id} onPress={() => {}}>
                  <Card variant="elevated">
                    <View className="flex-row items-center">
                      {/* Meal Icon */}
                      <View
                        className="w-12 h-12 rounded-xl items-center justify-center mr-4"
                        style={{ backgroundColor: `${meal.color}20` }}
                      >
                        <MealIcon size={22} color={meal.color} />
                      </View>

                      {/* Meal Info */}
                      <View className="flex-1">
                        <Text variant="body" className="font-semibold">
                          {meal.title}
                        </Text>
                        {meal.calories > 0 ? (
                          <Text variant="bodySmall" className="text-text-secondary mt-0.5">
                            {meal.calories} kcal · {meal.protein}g protein
                          </Text>
                        ) : (
                          <Text variant="bodySmall" className="text-text-tertiary mt-0.5">
                            No meals logged
                          </Text>
                        )}
                      </View>

                      {/* Action */}
                      {meal.calories > 0 ? (
                        <View className="w-8 h-8 rounded-full bg-success/20 items-center justify-center">
                          <Check size={16} color="#34C759" />
                        </View>
                      ) : (
                        <PressableScale className="bg-primary/20 px-4 py-2 rounded-full flex-row items-center gap-1.5">
                          <Plus size={14} color="#208AEF" />
                          <Text variant="bodySmall" className="text-primary font-medium">
                            Add
                          </Text>
                        </PressableScale>
                      )}
                    </View>
                  </Card>
                </PressableScale>
              );
            })}
          </View>
        </Animated.View>

        {/* Daily Total */}
        <Animated.View entering={enteringTotal} className="px-6 mb-6">
          <Card variant="elevated">
            <Text variant="h3" className="mb-4">
              Daily Total
            </Text>
            <View className="flex-row justify-between">
              <View className="items-center flex-1">
                <View className="w-10 h-10 rounded-full bg-accent/20 items-center justify-center mb-2">
                  <Flame size={20} color="#FF6B35" />
                </View>
                <Text variant="statSmall" className="text-accent">
                  1,070
                </Text>
                <Text variant="caption" className="text-text-tertiary mt-1">
                  Calories
                </Text>
              </View>
              <View className="items-center flex-1">
                <View className="w-10 h-10 rounded-full bg-primary/20 items-center justify-center mb-2">
                  <CircleDot size={20} color="#208AEF" />
                </View>
                <Text variant="statSmall" className="text-primary">
                  78g
                </Text>
                <Text variant="caption" className="text-text-tertiary mt-1">
                  Protein
                </Text>
              </View>
              <View className="items-center flex-1">
                <View className="w-10 h-10 rounded-full bg-success/20 items-center justify-center mb-2">
                  <Wheat size={20} color="#34C759" />
                </View>
                <Text variant="statSmall" className="text-success">
                  110g
                </Text>
                <Text variant="caption" className="text-text-tertiary mt-1">
                  Carbs
                </Text>
              </View>
              <View className="items-center flex-1">
                <View className="w-10 h-10 rounded-full bg-warning/20 items-center justify-center mb-2">
                  <Droplets size={20} color="#FF9500" />
                </View>
                <Text variant="statSmall" className="text-warning">
                  30g
                </Text>
                <Text variant="caption" className="text-text-tertiary mt-1">
                  Fat
                </Text>
              </View>
            </View>
          </Card>
        </Animated.View>
      </ScrollView>
    </SafeAreaView>
  );
}
