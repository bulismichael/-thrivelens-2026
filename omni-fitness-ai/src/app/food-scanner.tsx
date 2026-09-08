import React, { useState } from "react";
import { View, ScrollView, Pressable } from "react-native";
import { router } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { Text, Button, Card } from "@/components/ui";

const scanOptions = [
  {
    id: "1",
    title: "Take Photo",
    icon: "📷",
    description: "Use your camera to scan food",
  },
  {
    id: "2",
    title: "Upload Photo",
    icon: "🖼️",
    description: "Choose from your gallery",
  },
  {
    id: "3",
    title: "Scan Barcode",
    icon: "📊",
    description: "Scan product barcodes",
  },
];

const sampleResults = [
  {
    id: "1",
    name: "Chicken Breast",
    amount: "180g",
    calories: 295,
    protein: 55,
    confidence: 95,
  },
  {
    id: "2",
    name: "Rice",
    amount: "220g",
    calories: 286,
    protein: 6,
    confidence: 92,
  },
  {
    id: "3",
    name: "Vegetables",
    amount: "120g",
    calories: 70,
    protein: 4,
    confidence: 88,
  },
];

export default function FoodScannerScreen() {
  const [scanning, setScanning] = useState(false);
  const [results, setResults] = useState<typeof sampleResults | null>(null);

  const handleScan = () => {
    setScanning(true);
    // Simulate scanning
    setTimeout(() => {
      setScanning(false);
      setResults(sampleResults);
    }, 2000);
  };

  const totalCalories = results?.reduce((sum, r) => sum + r.calories, 0) || 0;
  const totalProtein = results?.reduce((sum, r) => sum + r.protein, 0) || 0;

  return (
    <SafeAreaView className="flex-1 bg-background" edges={["top"]}>
      {/* Header */}
      <View className="flex-row items-center justify-between px-6 py-4 border-b border-border">
        <Pressable onPress={() => router.back()}>
          <Text variant="body" className="text-primary">
            ← Back
          </Text>
        </Pressable>
        <Text variant="h3">Scan Your Food</Text>
        <View className="w-12" />
      </View>

      <ScrollView
        contentContainerStyle={{ padding: 24, paddingBottom: 100 }}
        showsVerticalScrollIndicator={false}
      >
        {!results ? (
          <>
            {/* Camera Preview Placeholder */}
            <View className="bg-surface rounded-2xl h-64 items-center justify-center mb-6 border border-border">
              {scanning ? (
                <View className="items-center">
                  <Text variant="h1" className="mb-4">
                    🔍
                  </Text>
                  <Text variant="body" className="text-text-secondary">
                    Analyzing your meal...
                  </Text>
                  <Text variant="caption" className="text-text-tertiary mt-2">
                    OMNI AI is identifying food items
                  </Text>
                </View>
              ) : (
                <View className="items-center">
                  <Text variant="h1" className="mb-4">
                    📷
                  </Text>
                  <Text variant="body" className="text-text-secondary">
                    Point camera at your food
                  </Text>
                  <Text variant="caption" className="text-text-tertiary mt-2">
                    Or choose an option below
                  </Text>
                </View>
              )}
            </View>

            {/* Scan Options */}
            <View className="gap-3">
              {scanOptions.map((option) => (
                <Pressable
                  key={option.id}
                  className="flex-row items-center gap-4 bg-surface p-4 rounded-xl border border-border"
                  onPress={handleScan}
                >
                  <View className="w-12 h-12 rounded-full bg-primary/20 items-center justify-center">
                    <Text variant="h3">{option.icon}</Text>
                  </View>
                  <View className="flex-1">
                    <Text variant="body" className="font-semibold">
                      {option.title}
                    </Text>
                    <Text variant="bodySmall" className="text-text-secondary">
                      {option.description}
                    </Text>
                  </View>
                  <Text variant="body" className="text-text-tertiary">
                    →
                  </Text>
                </Pressable>
              ))}
            </View>
          </>
        ) : (
          <>
            {/* Results Header */}
            <View className="mb-6">
              <Text variant="h2" className="mb-2">
                Scan Results
              </Text>
              <Text variant="body" className="text-text-secondary">
                AI analysis of your meal
              </Text>
            </View>

            {/* Food Items */}
            <View className="gap-3 mb-6">
              {results.map((item) => (
                <Card key={item.id} variant="elevated">
                  <View className="flex-row justify-between items-start">
                    <View className="flex-1">
                      <Text variant="body" className="font-semibold">
                        {item.name}
                      </Text>
                      <Text variant="bodySmall" className="text-text-secondary">
                        {item.amount}
                      </Text>
                    </View>
                    <View className="items-end">
                      <Text variant="body" className="text-primary font-semibold">
                        {item.calories} kcal
                      </Text>
                      <Text variant="caption" className="text-text-secondary">
                        {item.protein}g protein
                      </Text>
                    </View>
                  </View>
                  <View className="mt-2 flex-row items-center gap-2">
                    <View className="flex-1 h-1 bg-surface-highlight rounded-full overflow-hidden">
                      <View
                        className="h-full bg-success rounded-full"
                        style={{ width: `${item.confidence}%` }}
                      />
                    </View>
                    <Text variant="caption" className="text-text-tertiary">
                      {item.confidence}% confidence
                    </Text>
                  </View>
                </Card>
              ))}
            </View>

            {/* Total */}
            <Card variant="elevated" className="mb-6">
              <View className="flex-row justify-between items-center">
                <View>
                  <Text variant="h3">Total</Text>
                  <Text variant="caption" className="text-text-tertiary">
                    Estimated values
                  </Text>
                </View>
                <View className="items-end">
                  <Text variant="stat" className="text-primary">
                    {totalCalories} kcal
                  </Text>
                  <Text variant="bodySmall" className="text-text-secondary">
                    {totalProtein}g protein
                  </Text>
                </View>
              </View>
            </Card>

            {/* Actions */}
            <View className="gap-3">
              <Button
                title="Add to Meal"
                size="lg"
                onPress={() => router.back()}
              />
              <Button
                title="Edit Portions"
                variant="secondary"
                size="lg"
                onPress={() => {}}
              />
              <Button
                title="Scan Again"
                variant="ghost"
                size="lg"
                onPress={() => setResults(null)}
              />
            </View>

            {/* Disclaimer */}
            <Text variant="caption" className="text-text-tertiary text-center mt-6">
              Values are estimates based on AI analysis. Actual nutritional content may vary.
            </Text>
          </>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}
