import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  FlatList,
  Alert,
  Image,
  ActivityIndicator,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { mealsAPI } from '../../src/services/api';
import { colors, spacing, borderRadius, typography } from '../../src/utils/theme';

const MEAL_TYPES = ['breakfast', 'lunch', 'dinner', 'snack'] as const;

interface DailySummary {
  date: string;
  meals: any[];
  totals: {
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  };
  targets: {
    dailyCalorieTarget?: number;
    dailyProteinTarget?: number;
    dailyCarbTarget?: number;
    dailyFatTarget?: number;
  };
  remaining: {
    calories: number;
    protein: number;
    carbs: number;
    fat: number;
  };
}

export default function MealsScreen() {
  const [dailySummary, setDailySummary] = useState<DailySummary | null>(null);
  const [selectedDate, setSelectedDate] = useState(new Date().toISOString().split('T')[0]);
  const [isAnalyzing, setIsAnalyzing] = useState(false);

  const fetchDailySummary = async () => {
    try {
      const response = await mealsAPI.getDailySummary(selectedDate);
      setDailySummary(response.data.data);
    } catch (error) {
      console.error('Error fetching daily summary:', error);
    }
  };

  useEffect(() => {
    fetchDailySummary();
  }, [selectedDate]);

  const handleCameraPress = async () => {
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission Required', 'Camera permission is needed to take food photos');
      return;
    }

    const result = await ImagePicker.launchCameraAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [4, 3],
      quality: 0.8,
    });

    if (!result.canceled) {
      analyzeImage(result.assets[0].uri);
    }
  };

  const handleGalleryPress = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [4, 3],
      quality: 0.8,
    });

    if (!result.canceled) {
      analyzeImage(result.assets[0].uri);
    }
  };

  const analyzeImage = async (imageUri: string) => {
    try {
      setIsAnalyzing(true);
      // In a real app, you'd upload the image and get a URL first
      // For now, we'll simulate the analysis
      Alert.alert(
        'AI Analysis',
        'Food image analysis will process your meal and estimate nutritional content. This feature requires backend image upload configuration.',
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Continue',
            onPress: () => {
              // Navigate to manual entry or show analyzed results
              Alert.alert('Add Meal', 'Please add meal details manually for now');
            },
          },
        ]
      );
    } catch (error) {
      Alert.alert('Error', 'Failed to analyze image');
    } finally {
      setIsAnalyzing(false);
    }
  };

  const navigateDate = (direction: 'prev' | 'next') => {
    const date = new Date(selectedDate);
    date.setDate(date.getDate() + (direction === 'next' ? 1 : -1));
    setSelectedDate(date.toISOString().split('T')[0]);
  };

  const getMealsByType = (mealType: string) => {
    return dailySummary?.meals.filter((m: any) => m.meal_type === mealType) || [];
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      <View style={styles.header}>
        <Text style={styles.title}>Meals</Text>
        <TouchableOpacity style={styles.addButton}>
          <Ionicons name="add" size={24} color={colors.white} />
        </TouchableOpacity>
      </View>

      {/* Date Selector */}
      <View style={styles.dateSelector}>
        <TouchableOpacity onPress={() => navigateDate('prev')}>
          <Ionicons name="chevron-back" size={24} color={colors.primary} />
        </TouchableOpacity>
        <Text style={styles.dateText}>
          {new Date(selectedDate).toLocaleDateString('en-US', {
            weekday: 'long',
            month: 'long',
            day: 'numeric',
          })}
        </Text>
        <TouchableOpacity onPress={() => navigateDate('next')}>
          <Ionicons name="chevron-forward" size={24} color={colors.primary} />
        </TouchableOpacity>
      </View>

      {/* Photo Upload Section */}
      <View style={styles.photoSection}>
        <TouchableOpacity style={styles.photoButton} onPress={handleCameraPress}>
          <Ionicons name="camera" size={32} color={colors.primary} />
          <Text style={styles.photoButtonText}>Take Photo</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.photoButton} onPress={handleGalleryPress}>
          <Ionicons name="images" size={32} color={colors.primary} />
          <Text style={styles.photoButtonText}>Upload Photo</Text>
        </TouchableOpacity>
      </View>

      {isAnalyzing && (
        <View style={styles.analyzingBanner}>
          <ActivityIndicator size="small" color={colors.primary} />
          <Text style={styles.analyzingText}>Analyzing food...</Text>
        </View>
      )}

      {/* Daily Summary */}
      {dailySummary && (
        <View style={styles.summaryCard}>
          <Text style={styles.summaryTitle}>Daily Summary</Text>
          <View style={styles.summaryGrid}>
            <SummaryItem
              label="Calories"
              value={dailySummary.totals.calories}
              target={dailySummary.targets.dailyCalorieTarget || 2000}
              unit="kcal"
              color={colors.primary}
            />
            <SummaryItem
              label="Protein"
              value={dailySummary.totals.protein}
              target={dailySummary.targets.dailyProteinTarget || 150}
              unit="g"
              color={colors.chartGreen}
            />
            <SummaryItem
              label="Carbs"
              value={dailySummary.totals.carbs}
              target={dailySummary.targets.dailyCarbTarget || 250}
              unit="g"
              color={colors.chartOrange}
            />
            <SummaryItem
              label="Fat"
              value={dailySummary.totals.fat}
              target={dailySummary.targets.dailyFatTarget || 65}
              unit="g"
              color={colors.chartRed}
            />
          </View>
        </View>
      )}

      {/* Meals by Type */}
      {MEAL_TYPES.map((mealType) => {
        const meals = getMealsByType(mealType);
        return (
          <View key={mealType} style={styles.mealTypeSection}>
            <View style={styles.mealTypeHeader}>
              <View style={[styles.mealTypeIcon, { backgroundColor: getMealTypeColor(mealType) + '20' }]}>
                <Ionicons name={getMealTypeIcon(mealType)} size={20} color={getMealTypeColor(mealType)} />
              </View>
              <Text style={styles.mealTypeTitle}>
                {mealType.charAt(0).toUpperCase() + mealType.slice(1)}
              </Text>
              <TouchableOpacity>
                <Ionicons name="add-circle" size={24} color={colors.primary} />
              </TouchableOpacity>
            </View>
            
            {meals.length > 0 ? (
              meals.map((meal: any) => (
                <View key={meal.id} style={styles.mealCard}>
                  <View style={styles.mealInfo}>
                    <Text style={styles.mealName}>{meal.name || mealType}</Text>
                    <Text style={styles.mealCalories}>{meal.total_calories} kcal</Text>
                  </View>
                  <View style={styles.mealMacros}>
                    <Text style={styles.macroText}>P: {meal.total_protein}g</Text>
                    <Text style={styles.macroText}>C: {meal.total_carbs}g</Text>
                    <Text style={styles.macroText}>F: {meal.total_fat}g</Text>
                  </View>
                </View>
              ))
            ) : (
              <TouchableOpacity style={styles.addMealButton}>
                <Text style={styles.addMealText}>+ Add {mealType}</Text>
              </TouchableOpacity>
            )}
          </View>
        );
      })}
    </ScrollView>
  );
}

function SummaryItem({ label, value, target, unit, color }: any) {
  const percentage = Math.min((value / target) * 100, 100);
  
  return (
    <View style={styles.summaryItem}>
      <Text style={styles.summaryLabel}>{label}</Text>
      <Text style={[styles.summaryValue, { color }]}>{Math.round(value)}</Text>
      <Text style={styles.summaryUnit}>/ {target}{unit}</Text>
      <View style={styles.progressBar}>
        <View style={[styles.progressFill, { width: `${percentage}%`, backgroundColor: color }]} />
      </View>
    </View>
  );
}

function getMealTypeColor(type: string): string {
  const colors: Record<string, string> = {
    breakfast: '#FFD93D',
    lunch: '#6BCB77',
    dinner: '#4D96FF',
    snack: '#FF6B6B',
  };
  return colors[type] || colors.primary;
}

function getMealTypeIcon(type: string): string {
  const icons: Record<string, string> = {
    breakfast: 'sunny',
    lunch: 'restaurant',
    dinner: 'moon',
    snack: 'cafe',
  };
  return icons[type] || 'restaurant';
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  contentContainer: {
    padding: spacing.lg,
    paddingTop: spacing.xxl + 40,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: spacing.lg,
  },
  title: {
    ...typography.h1,
  },
  addButton: {
    width: 40,
    height: 40,
    borderRadius: borderRadius.sm,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  dateSelector: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    marginBottom: spacing.lg,
  },
  dateText: {
    ...typography.body,
    fontWeight: '500',
  },
  photoSection: {
    flexDirection: 'row',
    gap: spacing.md,
    marginBottom: spacing.lg,
  },
  photoButton: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: spacing.lg,
    alignItems: 'center',
    gap: spacing.sm,
  },
  photoButtonText: {
    ...typography.bodySmall,
    fontWeight: '500',
  },
  analyzingBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.primary + '20',
    borderRadius: borderRadius.md,
    padding: spacing.md,
    marginBottom: spacing.lg,
    gap: spacing.sm,
  },
  analyzingText: {
    ...typography.bodySmall,
    color: colors.primary,
  },
  summaryCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.lg,
    marginBottom: spacing.lg,
  },
  summaryTitle: {
    ...typography.h4,
    marginBottom: spacing.md,
  },
  summaryGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.md,
  },
  summaryItem: {
    flex: 1,
    minWidth: '42%',
    backgroundColor: colors.surfaceLight,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    alignItems: 'center',
  },
  summaryLabel: {
    ...typography.caption,
    marginBottom: spacing.xs,
  },
  summaryValue: {
    fontSize: 24,
    fontWeight: '700',
  },
  summaryUnit: {
    ...typography.caption,
    marginBottom: spacing.sm,
  },
  progressBar: {
    width: '100%',
    height: 4,
    backgroundColor: colors.surfaceBorder,
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 2,
  },
  mealTypeSection: {
    marginBottom: spacing.lg,
  },
  mealTypeHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.md,
    gap: spacing.sm,
  },
  mealTypeIcon: {
    width: 32,
    height: 32,
    borderRadius: borderRadius.sm,
    justifyContent: 'center',
    alignItems: 'center',
  },
  mealTypeTitle: {
    ...typography.h4,
    flex: 1,
  },
  mealCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    marginBottom: spacing.sm,
  },
  mealInfo: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: spacing.sm,
  },
  mealName: {
    ...typography.body,
    fontWeight: '500',
  },
  mealCalories: {
    ...typography.body,
    color: colors.primary,
    fontWeight: '600',
  },
  mealMacros: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  macroText: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  addMealButton: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: spacing.lg,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.surfaceBorder,
    borderStyle: 'dashed',
  },
  addMealText: {
    ...typography.body,
    color: colors.primary,
  },
});