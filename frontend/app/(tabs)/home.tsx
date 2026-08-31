import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  RefreshControl,
  TouchableOpacity,
} from 'react-native';
import { useAuthStore } from '../../src/context/AuthStore';
import { progressAPI, mealsAPI, workoutsAPI } from '../../src/services/api';
import { colors, spacing, borderRadius, typography } from '../../src/utils/theme';
import { Ionicons } from '@expo/vector-icons';

interface DailySummary {
  date: string;
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

export default function HomeScreen() {
  const { user, profile } = useAuthStore();
  const [dailySummary, setDailySummary] = useState<DailySummary | null>(null);
  const [upcomingWorkouts, setUpcomingWorkouts] = useState<any[]>([]);
  const [metrics, setMetrics] = useState<any>(null);
  const [refreshing, setRefreshing] = useState(false);

  const fetchData = async () => {
    try {
      const [summaryRes, workoutsRes, metricsRes] = await Promise.allSettled([
        mealsAPI.getDailySummary(),
        workoutsAPI.getUpcoming(),
        progressAPI.getMetrics(),
      ]);

      if (summaryRes.status === 'fulfilled') setDailySummary(summaryRes.value.data.data);
      if (workoutsRes.status === 'fulfilled') setUpcomingWorkouts(workoutsRes.value.data.data);
      if (metricsRes.status === 'fulfilled') setMetrics(metricsRes.value.data.data);
    } catch (error) {
      console.error('Error fetching home data:', error);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const onRefresh = async () => {
    setRefreshing(true);
    await fetchData();
    setRefreshing(false);
  };

  const greeting = () => {
    const hour = new Date().getHours();
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  };

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.contentContainer}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.primary} />}
    >
      <View style={styles.header}>
        <View>
          <Text style={styles.greeting}>{greeting()}</Text>
          <Text style={styles.userName}>{user?.email?.split('@')[0] || 'User'}</Text>
        </View>
        {metrics && (
          <View style={styles.streakBadge}>
            <Ionicons name="flame" size={16} color={colors.warning} />
            <Text style={styles.streakText}>{metrics.weeksTracked} weeks</Text>
          </View>
        )}
      </View>

      {/* Weight Progress */}
      {metrics && (
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Weight Progress</Text>
          <View style={styles.weightRow}>
            <View style={styles.weightStat}>
              <Text style={styles.weightValue}>{metrics.currentWeight} kg</Text>
              <Text style={styles.weightLabel}>Current</Text>
            </View>
            <View style={styles.weightChange}>
              <Ionicons
                name={metrics.weightChange < 0 ? 'arrow-down' : 'arrow-up'}
                size={20}
                color={metrics.weightChange < 0 ? colors.success : colors.warning}
              />
              <Text
                style={[
                  styles.weightChangeText,
                  { color: metrics.weightChange < 0 ? colors.success : colors.warning },
                ]}
              >
                {metrics.weightChange > 0 ? '+' : ''}{metrics.weightChange} kg
              </Text>
            </View>
            {metrics.targetWeight && (
              <View style={styles.weightStat}>
                <Text style={styles.weightValue}>{metrics.targetWeight} kg</Text>
                <Text style={styles.weightLabel}>Target</Text>
              </View>
            )}
          </View>
        </View>
      )}

      {/* Today's Nutrition */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Today's Nutrition</Text>
        {dailySummary ? (
          <View style={styles.nutritionGrid}>
            <NutrientBox
              label="Calories"
              value={dailySummary.totals.calories}
              target={dailySummary.targets.dailyCalorieTarget || 2000}
              unit="kcal"
              color={colors.primary}
            />
            <NutrientBox
              label="Protein"
              value={dailySummary.totals.protein}
              target={dailySummary.targets.dailyProteinTarget || 150}
              unit="g"
              color={colors.chartGreen}
            />
            <NutrientBox
              label="Carbs"
              value={dailySummary.totals.carbs}
              target={dailySummary.targets.dailyCarbTarget || 250}
              unit="g"
              color={colors.chartOrange}
            />
            <NutrientBox
              label="Fat"
              value={dailySummary.totals.fat}
              target={dailySummary.targets.dailyFatTarget || 65}
              unit="g"
              color={colors.chartRed}
            />
          </View>
        ) : (
          <Text style={styles.emptyText}>No meals logged today</Text>
        )}
      </View>

      {/* Upcoming Workouts */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Upcoming Workouts</Text>
        {upcomingWorkouts.length > 0 ? (
          upcomingWorkouts.slice(0, 3).map((workout) => (
            <View key={workout.id} style={styles.workoutItem}>
              <View style={styles.workoutIcon}>
                <Ionicons name="fitness" size={20} color={colors.primary} />
              </View>
              <View style={styles.workoutInfo}>
                <Text style={styles.workoutName}>{workout.name}</Text>
                <Text style={styles.workoutDate}>
                  {new Date(workout.scheduled_date).toLocaleDateString('en-US', {
                    weekday: 'short',
                    month: 'short',
                    day: 'numeric',
                  })}
                </Text>
              </View>
              {workout.duration && (
                <Text style={styles.workoutDuration}>{workout.duration} min</Text>
              )}
            </View>
          ))
        ) : (
          <Text style={styles.emptyText}>No upcoming workouts</Text>
        )}
      </View>

      {/* AI Tips */}
      <View style={styles.card}>
        <View style={styles.tipHeader}>
          <Ionicons name="sparkles" size={20} color={colors.primary} />
          <Text style={styles.cardTitle}>AI Tips</Text>
        </View>
        <Text style={styles.emptyText}>
          Complete your profile and log meals to get personalized tips
        </Text>
      </View>
    </ScrollView>
  );
}

function NutrientBox({ label, value, target, unit, color }: any) {
  const percentage = Math.min((value / target) * 100, 100);
  
  return (
    <View style={styles.nutrientBox}>
      <Text style={styles.nutrientLabel}>{label}</Text>
      <Text style={[styles.nutrientValue, { color }]}>{Math.round(value)}</Text>
      <Text style={styles.nutrientUnit}>/ {target}{unit}</Text>
      <View style={styles.progressBar}>
        <View style={[styles.progressFill, { width: `${percentage}%`, backgroundColor: color }]} />
      </View>
    </View>
  );
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
    marginBottom: spacing.xl,
  },
  greeting: {
    ...typography.body,
    color: colors.textSecondary,
  },
  userName: {
    ...typography.h2,
    textTransform: 'capitalize',
  },
  streakBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: borderRadius.full,
    gap: spacing.xs,
  },
  streakText: {
    ...typography.bodySmall,
    fontWeight: '600',
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.lg,
    marginBottom: spacing.md,
  },
  cardTitle: {
    ...typography.h4,
    marginBottom: spacing.md,
  },
  weightRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
  },
  weightStat: {
    alignItems: 'center',
  },
  weightValue: {
    ...typography.h3,
    color: colors.primary,
  },
  weightLabel: {
    ...typography.caption,
    marginTop: spacing.xs,
  },
  weightChange: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  weightChangeText: {
    ...typography.body,
    fontWeight: '600',
  },
  nutritionGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.md,
  },
  nutrientBox: {
    flex: 1,
    minWidth: '42%',
    backgroundColor: colors.surfaceLight,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    alignItems: 'center',
  },
  nutrientLabel: {
    ...typography.caption,
    marginBottom: spacing.xs,
  },
  nutrientValue: {
    fontSize: 24,
    fontWeight: '700',
  },
  nutrientUnit: {
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
  workoutItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surfaceLight,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    marginBottom: spacing.sm,
  },
  workoutIcon: {
    width: 40,
    height: 40,
    borderRadius: borderRadius.sm,
    backgroundColor: colors.primary + '20',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: spacing.md,
  },
  workoutInfo: {
    flex: 1,
  },
  workoutName: {
    ...typography.body,
    fontWeight: '500',
  },
  workoutDate: {
    ...typography.caption,
    marginTop: spacing.xs,
  },
  workoutDuration: {
    ...typography.bodySmall,
    color: colors.primary,
  },
  tipHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  emptyText: {
    ...typography.bodySmall,
    textAlign: 'center',
    padding: spacing.md,
  },
});