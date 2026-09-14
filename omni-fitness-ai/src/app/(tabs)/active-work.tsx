import React, { useState, useEffect } from "react";
import { View, Pressable } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { Text, Button, Card, ProgressBar } from "@/components/ui";

const exercises = [
  {
    id: "1",
    name: "Bench Press",
    sets: [
      { set: 1, weight: 80, reps: 10, completed: true },
      { set: 2, weight: 80, reps: 9, completed: true },
      { set: 3, weight: 80, reps: 8, completed: false },
    ],
    targetSets: 4,
    targetReps: "8-12",
  },
  {
    id: "2",
    name: "Incline Dumbbell Press",
    sets: [],
    targetSets: 3,
    targetReps: "10-12",
  },
];

export default function ActiveWorkoutScreen() {
  const [currentExerciseIndex, setCurrentExerciseIndex] = useState(0);
  const [currentSetIndex, setCurrentSetIndex] = useState(0);
  const [restTimer, setRestTimer] = useState(0);
  const [isResting, setIsResting] = useState(false);

  const currentExercise = exercises[currentExerciseIndex];

  useEffect(() => {
    let interval: ReturnType<typeof setInterval>;
    if (isResting && restTimer > 0) {
      interval = setInterval(() => {
        setRestTimer((prev) => prev - 1);
      }, 1000);
    } else if (restTimer === 0) {
      setIsResting(false);
    }
    return () => clearInterval(interval);
  }, [isResting, restTimer]);

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, "0")}`;
  };

  const handleCompleteSet = () => {
    // Mark current set as completed
    setIsResting(true);
    setRestTimer(90); // 90 seconds rest
  };

  const handleSkipRest = () => {
    setIsResting(false);
    setRestTimer(0);
  };

  return (
    <SafeAreaView className="flex-1 bg-background">
      {/* Header */}
      <View className="flex-row items-center justify-between px-6 py-4 border-b border-border">
        <Pressable onPress={() => router.back()}>
          <Text variant="body" className="text-primary">
            ← Exit
          </Text>
        </Pressable>
        <Text variant="h3">Active Workout</Text>
        <View className="w-12" />
      </View>

      {/* Progress */}
      <View className="px-6 py-4">
        <ProgressBar
          progress={(currentExerciseIndex / exercises.length) * 100}
          color="#208AEF"
          showLabel
          label={`Exercise ${currentExerciseIndex + 1} of ${exercises.length}`}
        />
      </View>

      {/* Current Exercise */}
      <View className="flex-1 px-6">
        {/* Exercise Video Placeholder */}
        <Card variant="elevated" className="mb-6">
          <View className="h-48 items-center justify-center bg-surface-highlight rounded-xl">
            <Text variant="h1" className="mb-2">
              🏋️
            </Text>
            <Text variant="body" className="text-text-secondary">
              Exercise video
            </Text>
          </View>
        </Card>

        {/* Exercise Info */}
        <View className="mb-6">
          <Text variant="h1" className="mb-2">
            {currentExercise.name}
          </Text>
          <Text variant="body" className="text-text-secondary">
            {currentExercise.targetSets} sets × {currentExercise.targetReps} reps
          </Text>
        </View>

        {/* Sets */}
        <View className="gap-3 mb-6">
          {currentExercise.sets.map((set, index) => (
            <View
              key={index}
              className={`flex-row items-center justify-between p-4 rounded-xl ${
                set.completed
                  ? "bg-success/10 border border-success/30"
                  : "bg-surface-elevated border border-border"
              }`}
            >
              <View className="flex-row items-center gap-3">
                <View
                  className={`w-8 h-8 rounded-full items-center justify-center ${
                    set.completed ? "bg-success" : "bg-surface-highlight"
                  }`}
                >
                  <Text
                    variant="bodySmall"
                    className={set.completed ? "text-white" : "text-text-secondary"}
                  >
                    {set.completed ? "✓" : set.set}
                  </Text>
                </View>
                <Text variant="body" className="font-semibold">
                  Set {set.set}
                </Text>
              </View>
              <View className="flex-row items-center gap-4">
                <Text variant="body" className="text-text-primary">
                  {set.weight} kg × {set.reps}
                </Text>
              </View>
            </View>
          ))}

          {/* Add Set Button */}
          <Pressable className="flex-row items-center justify-center p-4 rounded-xl border border-dashed border-border">
            <Text variant="body" className="text-text-secondary">
              + Add Set
            </Text>
          </Pressable>
        </View>
      </View>

      {/* Rest Timer / Complete Set Button */}
      <View className="px-6 pb-6">
        {isResting ? (
          <Card variant="elevated" className="mb-4">
            <View className="items-center">
              <Text variant="caption" className="text-text-secondary mb-2">
                REST TIME
              </Text>
              <Text variant="display" className="text-primary mb-4">
                {formatTime(restTimer)}
              </Text>
              <Button
                title="Skip Rest"
                variant="secondary"
                onPress={handleSkipRest}
              />
            </View>
          </Card>
        ) : (
          <Button
            title="Complete Set"
            size="lg"
            onPress={handleCompleteSet}
          />
        )}

        {/* Navigation */}
        <View className="flex-row justify-between mt-4">
          <Button
            title="Previous"
            variant="ghost"
            onPress={() => {
              if (currentExerciseIndex > 0) {
                setCurrentExerciseIndex((prev) => prev - 1);
              }
            }}
            disabled={currentExerciseIndex === 0}
          />
          <Button
            title="Next Exercise"
            variant="ghost"
            onPress={() => {
              if (currentExerciseIndex < exercises.length - 1) {
                setCurrentExerciseIndex((prev) => prev + 1);
              } else {
                // Workout complete
                router.push("/workout-complete");
              }
            }}
          />
        </View>
      </View>
    </SafeAreaView>
  );
}
