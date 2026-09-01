import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  Dimensions,
  Alert,
  TextInput,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { progressAPI } from '../../src/services/api';
import { colors, spacing, borderRadius, typography } from '../../src/utils/theme';

const { width } = Dimensions.get('window');

interface Metrics {
  currentWeight: number;
  startWeight: number;
  targetWeight?: number;
  weightChange: number;
  weightChangePercent: number;
  weeksTracked: number;
  averageWeeklyChange: number;
  bmi: number;
  bmiCategory: string;
}

export default function ProgressScreen() {
  const [metrics, setMetrics] = useState<Metrics | null>(null);
  const [weightHistory, setWeightHistory] = useState<any[]>([]);
  const [showWeightInput, setShowWeightInput] = useState(false);
  const [newWeight, setNewWeight] = useState('');

  const fetchData = async () => {
    try {
      const [metricsRes, weightRes] = await Promise.all([
        progressAPI.getMetrics(),
        progressAPI.getWeightHistory(52),
      ]);
      setMetrics(metricsRes.data.data);
      setWeightHistory(weightRes.data.data);
    } catch (error) {
      console.error('Error fetching progress data:', error);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const handleAddWeight = async () => {
    const weight = parseFloat(newWeight);
    if (isNaN(weight) || weight < 20 || weight > 500) {
      Alert.alert('Invalid Weight', 'Please enter a valid weight between 20-500 kg');
      return;
    }

    try {
      await progressAPI.addWeight({
        weight,
        date: new Date().toISOString().split('T')[0],
      });
      setShowWeightInput(false);
      setNewWeight('');
      fetchData();
    } catch (error) {
      Alert.alert('Error', 'Failed to add weight entry');
    }
  };

  const renderWeightChart = () => {
    if (weightHistory.length < 2) {
      return (
        <View style={styles.chartPlaceholder}>
          <Ionicons name="bar-chart" size={48} color={colors.textMuted} />
          <Text style={styles.chartPlaceholderText}>Add more weight entries to see trends</Text>
        </View>
      );
    }

    // Simple bar chart representation
    const recentWeights = weightHistory.slice(-12);
    const minWeight = Math.min(...recentWeights.map((w) => w.weight)) - 2;
    const maxWeight = Math.max(...recentWeights.map((w) => w.weight)) + 2;
    const range = maxWeight - minWeight;

    return (
      <View style={styles.chartContainer}>
        <View style={styles.chartBars}>
          {recentWeights.map((entry, index) => {
            const height = ((entry.weight - minWeight) / range) * 100;
            return (
              <View key={entry.id} style={styles.barWrapper}>
                <View style={[styles.bar, { height: `${height}%` }]} />
                <Text style={styles.barLabel}>
                  {new Date(entry.date).toLocaleDateString('en-US', { month: 'short' })}
                </Text>
              </View>
            );
          })}
        </View>
      </View>
    );
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      <View style={styles.header}>
        <Text style={styles.title}>Progress</Text>
        <TouchableOpacity
          style={styles.addButton}
          onPress={() => setShowWeightInput(true)}
        >
          <Ionicons name="add" size={24} color={colors.white} />
        </TouchableOpacity>
      </View>

      {/* Weight Input Modal */}
      {showWeightInput && (
        <View style={styles.weightInputCard}>
          <Text style={styles.weightInputTitle}>Log Today's Weight</Text>
          <View style={styles.weightInputRow}>
            <TextInput
              style={styles.weightInput}
              placeholder="Enter weight"
              placeholderTextColor={colors.textMuted}
              keyboardType="decimal-pad"
              value={newWeight}
              onChangeText={setNewWeight}
              autoFocus
            />
            <Text style={styles.weightUnit}>kg</Text>
          </View>
          <View style={styles.weightInputActions}>
            <TouchableOpacity
              style={styles.cancelButton}
              onPress={() => {
                setShowWeightInput(false);
                setNewWeight('');
              }}
            >
              <Text style={styles.cancelButtonText}>Cancel</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.saveButton} onPress={handleAddWeight}>
              <Text style={styles.saveButtonText}>Save</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {/* Metrics Cards */}
      {metrics && (
        <View style={styles.metricsGrid}>
          <View style={[styles.metricCard, { backgroundColor: colors.primary + '20' }]}>
            <Ionicons name="scale" size={24} color={colors.primary} />
            <Text style={styles.metricValue}>{metrics.currentWeight} kg</Text>
            <Text style={styles.metricLabel}>Current Weight</Text>
          </View>

          <View style={[styles.metricCard, { backgroundColor: colors.chartGreen + '20' }]}>
            <Ionicons
              name={metrics.weightChange < 0 ? 'arrow-down' : 'arrow-up'}
              size={24}
              color={metrics.weightChange < 0 ? colors.chartGreen : colors.warning}
            />
            <Text
              style={[
                styles.metricValue,
                { color: metrics.weightChange < 0 ? colors.chartGreen : colors.warning },
              ]}
            >
              {metrics.weightChange > 0 ? '+' : ''}{metrics.weightChange} kg
            </Text>
            <Text style={styles.metricLabel}>Total Change</Text>
          </View>

          <View style={[styles.metricCard, { backgroundColor: colors.chartOrange + '20' }]}>
            <Ionicons name="trending-up" size={24} color={colors.chartOrange} />
            <Text style={styles.metricValue}>{metrics.averageWeeklyChange} kg/wk</Text>
            <Text style={styles.metricLabel}>Weekly Avg</Text>
          </View>

          <View style={[styles.metricCard, { backgroundColor: colors.chartPurple + '20' }]}>
            <Ionicons name="heart" size={24} color={colors.chartPurple} />
            <Text style={styles.metricValue}>{metrics.bmi}</Text>
            <Text style={styles.metricLabel}>{metrics.bmiCategory}</Text>
          </View>
        </View>
      )}

      {/* Weight Goal */}
      {metrics?.targetWeight && (
        <View style={styles.goalCard}>
          <View style={styles.goalHeader}>
            <Ionicons name="flag" size={20} color={colors.primary} />
            <Text style={styles.goalTitle}>Weight Goal</Text>
          </View>
          <View style={styles.goalProgress}>
            <View style={styles.goalBar}>
              <View
                style={[
                  styles.goalFill,
                  {
                    width: `${Math.min(
                      ((metrics.startWeight - metrics.currentWeight) /
                        (metrics.startWeight - metrics.targetWeight)) *
                        100,
                      100
                    )}%`,
                  },
                ]}
              />
            </View>
            <Text style={styles.goalText}>
              {Math.abs(metrics.currentWeight - metrics.targetWeight).toFixed(1)} kg remaining
            </Text>
          </View>
        </View>
      )}

      {/* Weight Chart */}
      <View style={styles.chartCard}>
        <Text style={styles.chartTitle}>Weight Trend</Text>
        {renderWeightChart()}
      </View>

      {/* Weekly Summary */}
      <View style={styles.summaryCard}>
        <Text style={styles.summaryTitle}>Weekly Summary</Text>
        <View style={styles.summaryRow}>
          <View style={styles.summaryItem}>
            <Text style={styles.summaryValue}>{metrics?.weeksTracked || 0}</Text>
            <Text style={styles.summaryLabel}>Weeks Tracked</Text>
          </View>
          <View style={styles.summaryItem}>
            <Text style={styles.summaryValue}>
              {weightHistory.length}
            </Text>
            <Text style={styles.summaryLabel}>Entries</Text>
          </View>
        </View>
      </View>

      {/* Tips */}
      <View style={styles.tipsCard}>
        <View style={styles.tipsHeader}>
          <Ionicons name="sparkles" size={20} color={colors.primary} />
          <Text style={styles.tipsTitle}>AI Insights</Text>
        </View>
        <Text style={styles.tipsText}>
          {metrics && metrics.weightChange < 0
            ? "Great progress! You're losing weight steadily. Keep it up!"
            : metrics && metrics.weightChange > 0
            ? "You've gained some weight. Consider reviewing your nutrition and exercise routine."
            : 'Keep logging your weight weekly to get personalized insights and tips.'}
        </Text>
      </View>
    </ScrollView>
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
  weightInputCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.lg,
    marginBottom: spacing.lg,
  },
  weightInputTitle: {
    ...typography.h4,
    marginBottom: spacing.md,
  },
  weightInputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  weightInput: {
    flex: 1,
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    color: colors.text,
    fontSize: 18,
  },
  weightUnit: {
    ...typography.body,
    color: colors.textSecondary,
  },
  weightInputActions: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  cancelButton: {
    flex: 1,
    backgroundColor: colors.surfaceLight,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    alignItems: 'center',
  },
  cancelButtonText: {
    ...typography.body,
    color: colors.textSecondary,
  },
  saveButton: {
    flex: 1,
    backgroundColor: colors.primary,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    alignItems: 'center',
  },
  saveButtonText: {
    ...typography.button,
  },
  metricsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.md,
    marginBottom: spacing.lg,
  },
  metricCard: {
    width: (width - spacing.lg * 2 - spacing.md) / 2,
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    alignItems: 'center',
  },
  metricValue: {
    ...typography.h3,
    marginVertical: spacing.sm,
  },
  metricLabel: {
    ...typography.caption,
  },
  goalCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.lg,
    marginBottom: spacing.lg,
  },
  goalHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  goalTitle: {
    ...typography.h4,
  },
  goalProgress: {
    gap: spacing.sm,
  },
  goalBar: {
    height: 8,
    backgroundColor: colors.surfaceLight,
    borderRadius: 4,
    overflow: 'hidden',
  },
  goalFill: {
    height: '100%',
    backgroundColor: colors.primary,
    borderRadius: 4,
  },
  goalText: {
    ...typography.bodySmall,
    textAlign: 'center',
  },
  chartCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.lg,
    marginBottom: spacing.lg,
  },
  chartTitle: {
    ...typography.h4,
    marginBottom: spacing.md,
  },
  chartPlaceholder: {
    height: 150,
    justifyContent: 'center',
    alignItems: 'center',
    gap: spacing.sm,
  },
  chartPlaceholderText: {
    ...typography.bodySmall,
  },
  chartContainer: {
    height: 200,
  },
  chartBars: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    height: '100%',
    paddingBottom: spacing.xl,
  },
  barWrapper: {
    flex: 1,
    alignItems: 'center',
    height: '100%',
    justifyContent: 'flex-end',
  },
  bar: {
    width: '60%',
    backgroundColor: colors.primary,
    borderRadius: 4,
    minHeight: 4,
  },
  barLabel: {
    ...typography.caption,
    marginTop: spacing.xs,
    fontSize: 10,
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
  summaryRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
  },
  summaryItem: {
    alignItems: 'center',
  },
  summaryValue: {
    ...typography.h2,
    color: colors.primary,
  },
  summaryLabel: {
    ...typography.caption,
    marginTop: spacing.xs,
  },
  tipsCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.lg,
  },
  tipsHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  tipsTitle: {
    ...typography.h4,
  },
  tipsText: {
    ...typography.body,
    color: colors.textSecondary,
    lineHeight: 24,
  },
});