import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Alert,
  ActivityIndicator,
} from 'react-native';
import { router } from 'expo-router';
import { profileAPI } from '../../src/services/api';
import { useAuthStore } from '../../src/context/AuthStore';
import { colors, spacing, borderRadius, typography } from '../../src/utils/theme';

const ACTIVITY_LEVELS = [
  { id: 'sedentary', label: 'Sedentary', description: 'Little or no exercise' },
  { id: 'light', label: 'Light', description: '1-3 days/week' },
  { id: 'moderate', label: 'Moderate', description: '3-5 days/week' },
  { id: 'active', label: 'Active', description: '6-7 days/week' },
  { id: 'very_active', label: 'Very Active', description: 'Twice daily' },
];

const GOALS = [
  { id: 'lose_weight', label: 'Lose Weight', icon: 'trending-down' },
  { id: 'maintain', label: 'Maintain', icon: 'remove' },
  { id: 'gain_muscle', label: 'Gain Muscle', icon: 'trending-up' },
  { id: 'improve_fitness', label: 'Get Fit', icon: 'heart' },
];

export default function OnboardingScreen() {
  const [step, setStep] = useState(1);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { setProfile } = useAuthStore();
  
  const [formData, setFormData] = useState({
    age: '',
    height: '',
    weight: '',
    sex: 'male' as 'male' | 'female' | 'other',
    activityLevel: 'moderate',
    goal: 'maintain',
    targetWeight: '',
  });

  const handleNext = () => {
    if (step === 1) {
      if (!formData.age || !formData.height || !formData.weight) {
        Alert.alert('Error', 'Please fill in all fields');
        return;
      }
      if (parseInt(formData.age) < 13) {
        Alert.alert('Error', 'You must be at least 13 years old');
        return;
      }
    }
    setStep(step + 1);
  };

  const handleBack = () => {
    setStep(step - 1);
  };

  const handleSubmit = async () => {
    setIsSubmitting(true);
    try {
      await profileAPI.createOrUpdate({
        age: parseInt(formData.age),
        height: parseFloat(formData.height),
        weight: parseFloat(formData.weight),
        sex: formData.sex,
        activityLevel: formData.activityLevel,
        goal: formData.goal,
        targetWeight: formData.targetWeight ? parseFloat(formData.targetWeight) : undefined,
      });

      // Fetch updated profile
      const response = await profileAPI.get();
      setProfile(response.data.data);

      router.replace('/(tabs)/home');
    } catch (error) {
      Alert.alert('Error', 'Failed to save profile. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      {/* Progress Indicator */}
      <View style={styles.progressContainer}>
        {[1, 2, 3].map((s) => (
          <View
            key={s}
            style={[styles.progressDot, step >= s && styles.progressDotActive]}
          />
        ))}
      </View>

      {/* Step 1: Basic Info */}
      {step === 1 && (
        <View style={styles.stepContainer}>
          <Text style={styles.stepTitle}>Basic Information</Text>
          <Text style={styles.stepSubtitle}>Tell us about yourself to personalize your experience</Text>

          <View style={styles.inputGroup}>
            <Text style={styles.label}>Age</Text>
            <TextInput
              style={styles.input}
              placeholder="Enter your age"
              placeholderTextColor={colors.textMuted}
              value={formData.age}
              onChangeText={(text) => setFormData({ ...formData, age: text })}
              keyboardType="number-pad"
            />
          </View>

          <View style={styles.inputGroup}>
            <Text style={styles.label}>Height (cm)</Text>
            <TextInput
              style={styles.input}
              placeholder="Enter your height"
              placeholderTextColor={colors.textMuted}
              value={formData.height}
              onChangeText={(text) => setFormData({ ...formData, height: text })}
              keyboardType="decimal-pad"
            />
          </View>

          <View style={styles.inputGroup}>
            <Text style={styles.label}>Weight (kg)</Text>
            <TextInput
              style={styles.input}
              placeholder="Enter your weight"
              placeholderTextColor={colors.textMuted}
              value={formData.weight}
              onChangeText={(text) => setFormData({ ...formData, weight: text })}
              keyboardType="decimal-pad"
            />
          </View>

          <View style={styles.inputGroup}>
            <Text style={styles.label}>Sex</Text>
            <View style={styles.segmentControl}>
              {['male', 'female', 'other'].map((option) => (
                <TouchableOpacity
                  key={option}
                  style={[
                    styles.segmentOption,
                    formData.sex === option && styles.segmentOptionActive,
                  ]}
                  onPress={() => setFormData({ ...formData, sex: option as any })}
                >
                  <Text
                    style={[
                      styles.segmentText,
                      formData.sex === option && styles.segmentTextActive,
                    ]}
                  >
                    {option.charAt(0).toUpperCase() + option.slice(1)}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>

          <TouchableOpacity style={styles.button} onPress={handleNext}>
            <Text style={styles.buttonText}>Next</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Step 2: Activity Level */}
      {step === 2 && (
        <View style={styles.stepContainer}>
          <Text style={styles.stepTitle}>Activity Level</Text>
          <Text style={styles.stepSubtitle}>How active are you on a typical week?</Text>

          <View style={styles.optionsGrid}>
            {ACTIVITY_LEVELS.map((level) => (
              <TouchableOpacity
                key={level.id}
                style={[
                  styles.optionCard,
                  formData.activityLevel === level.id && styles.optionCardActive,
                ]}
                onPress={() => setFormData({ ...formData, activityLevel: level.id })}
              >
                <Text
                  style={[
                    styles.optionLabel,
                    formData.activityLevel === level.id && styles.optionLabelActive,
                  ]}
                >
                  {level.label}
                </Text>
                <Text style={styles.optionDescription}>{level.description}</Text>
              </TouchableOpacity>
            ))}
          </View>

          <View style={styles.buttonRow}>
            <TouchableOpacity style={styles.backButton} onPress={handleBack}>
              <Text style={styles.backButtonText}>Back</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.button} onPress={handleNext}>
              <Text style={styles.buttonText}>Next</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {/* Step 3: Goal */}
      {step === 3 && (
        <View style={styles.stepContainer}>
          <Text style={styles.stepTitle}>Your Goal</Text>
          <Text style={styles.stepSubtitle}>What do you want to achieve?</Text>

          <View style={styles.goalsGrid}>
            {GOALS.map((goal) => (
              <TouchableOpacity
                key={goal.id}
                style={[
                  styles.goalCard,
                  formData.goal === goal.id && styles.goalCardActive,
                ]}
                onPress={() => setFormData({ ...formData, goal: goal.id })}
              >
                <Text
                  style={[
                    styles.goalLabel,
                    formData.goal === goal.id && styles.goalLabelActive,
                  ]}
                >
                  {goal.label}
                </Text>
              </TouchableOpacity>
            ))}
          </View>

          {formData.goal === 'lose_weight' && (
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Target Weight (kg) - Optional</Text>
              <TextInput
                style={styles.input}
                placeholder="Enter target weight"
                placeholderTextColor={colors.textMuted}
                value={formData.targetWeight}
                onChangeText={(text) => setFormData({ ...formData, targetWeight: text })}
                keyboardType="decimal-pad"
              />
            </View>
          )}

          <View style={styles.buttonRow}>
            <TouchableOpacity style={styles.backButton} onPress={handleBack}>
              <Text style={styles.backButtonText}>Back</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.button, isSubmitting && styles.buttonDisabled]}
              onPress={handleSubmit}
              disabled={isSubmitting}
            >
              {isSubmitting ? (
                <ActivityIndicator color={colors.white} />
              ) : (
                <Text style={styles.buttonText}>Get Started</Text>
              )}
            </TouchableOpacity>
          </View>
        </View>
      )}
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
  progressContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: spacing.sm,
    marginBottom: spacing.xxl,
  },
  progressDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.surfaceBorder,
  },
  progressDotActive: {
    backgroundColor: colors.primary,
    width: 24,
  },
  stepContainer: {
    flex: 1,
  },
  stepTitle: {
    ...typography.h1,
    textAlign: 'center',
    marginBottom: spacing.sm,
  },
  stepSubtitle: {
    ...typography.body,
    color: colors.textSecondary,
    textAlign: 'center',
    marginBottom: spacing.xl,
  },
  inputGroup: {
    marginBottom: spacing.lg,
  },
  label: {
    ...typography.bodySmall,
    fontWeight: '500',
    marginBottom: spacing.sm,
  },
  input: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.surfaceBorder,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    color: colors.text,
    fontSize: 16,
  },
  segmentControl: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: 4,
  },
  segmentOption: {
    flex: 1,
    paddingVertical: spacing.md,
    alignItems: 'center',
    borderRadius: borderRadius.sm,
  },
  segmentOptionActive: {
    backgroundColor: colors.primary,
  },
  segmentText: {
    ...typography.body,
    color: colors.textSecondary,
  },
  segmentTextActive: {
    color: colors.white,
    fontWeight: '600',
  },
  optionsGrid: {
    gap: spacing.md,
    marginBottom: spacing.xl,
  },
  optionCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: spacing.lg,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  optionCardActive: {
    borderColor: colors.primary,
  },
  optionLabel: {
    ...typography.h4,
    marginBottom: spacing.xs,
  },
  optionLabelActive: {
    color: colors.primary,
  },
  optionDescription: {
    ...typography.bodySmall,
  },
  goalsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.md,
    marginBottom: spacing.xl,
  },
  goalCard: {
    width: '47%',
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: spacing.lg,
    alignItems: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  goalCardActive: {
    borderColor: colors.primary,
    backgroundColor: colors.primary + '20',
  },
  goalLabel: {
    ...typography.body,
    fontWeight: '500',
  },
  goalLabelActive: {
    color: colors.primary,
  },
  buttonRow: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  backButton: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    alignItems: 'center',
  },
  backButtonText: {
    ...typography.button,
    color: colors.textSecondary,
  },
  button: {
    flex: 2,
    backgroundColor: colors.primary,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    ...typography.button,
  },
});