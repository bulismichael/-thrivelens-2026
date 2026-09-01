import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  Alert,
  TextInput,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../../src/context/AuthStore';
import { profileAPI, authAPI } from '../../src/services/api';
import { colors, spacing, borderRadius, typography } from '../../src/utils/theme';

export default function ProfileScreen() {
  const { user, profile, setProfile, logout } = useAuthStore();
  const [isEditing, setIsEditing] = useState(false);
  const [formData, setFormData] = useState({
    age: '',
    height: '',
    weight: '',
    sex: 'male' as 'male' | 'female' | 'other',
    activityLevel: 'moderate',
    goal: 'maintain',
    targetWeight: '',
  });

  useEffect(() => {
    if (profile) {
      setFormData({
        age: profile.age?.toString() || '',
        height: profile.height?.toString() || '',
        weight: profile.weight?.toString() || '',
        sex: profile.sex || 'male',
        activityLevel: profile.activityLevel || 'moderate',
        goal: profile.goal || 'maintain',
        targetWeight: profile.targetWeight?.toString() || '',
      });
    }
  }, [profile]);

  const handleSave = async () => {
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

      // Refresh profile
      const response = await profileAPI.get();
      setProfile(response.data.data);
      setIsEditing(false);
      Alert.alert('Success', 'Profile updated successfully');
    } catch (error) {
      Alert.alert('Error', 'Failed to update profile');
    }
  };

  const handleLogout = async () => {
    Alert.alert('Logout', 'Are you sure you want to logout?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Logout',
        style: 'destructive',
        onPress: () => logout(),
      },
    ]);
  };

  const getGoalLabel = (goal: string) => {
    const labels: Record<string, string> = {
      lose_weight: 'Lose Weight',
      maintain: 'Maintain Weight',
      gain_muscle: 'Gain Muscle',
      improve_fitness: 'Improve Fitness',
    };
    return labels[goal] || goal;
  };

  const getActivityLabel = (level: string) => {
    const labels: Record<string, string> = {
      sedentary: 'Sedentary',
      light: 'Lightly Active',
      moderate: 'Moderately Active',
      active: 'Active',
      very_active: 'Very Active',
    };
    return labels[level] || level;
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.contentContainer}>
      <View style={styles.header}>
        <Text style={styles.title}>Profile</Text>
        {!isEditing ? (
          <TouchableOpacity style={styles.editButton} onPress={() => setIsEditing(true)}>
            <Ionicons name="create" size={20} color={colors.primary} />
            <Text style={styles.editButtonText}>Edit</Text>
          </TouchableOpacity>
        ) : (
          <TouchableOpacity style={styles.saveButton} onPress={handleSave}>
            <Text style={styles.saveButtonText}>Save</Text>
          </TouchableOpacity>
        )}
      </View>

      {/* Profile Avatar */}
      <View style={styles.avatarSection}>
        <View style={styles.avatar}>
          <Text style={styles.avatarText}>
            {user?.email?.charAt(0).toUpperCase() || 'U'}
          </Text>
        </View>
        <Text style={styles.email}>{user?.email}</Text>
      </View>

      {/* Personal Info */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Personal Information</Text>
        
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Age</Text>
          {isEditing ? (
            <TextInput
              style={styles.infoInput}
              value={formData.age}
              onChangeText={(text) => setFormData({ ...formData, age: text })}
              keyboardType="number-pad"
            />
          ) : (
            <Text style={styles.infoValue}>{profile?.age || '-'} years</Text>
          )}
        </View>

        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Height</Text>
          {isEditing ? (
            <TextInput
              style={styles.infoInput}
              value={formData.height}
              onChangeText={(text) => setFormData({ ...formData, height: text })}
              keyboardType="decimal-pad"
            />
          ) : (
            <Text style={styles.infoValue}>{profile?.height || '-'} cm</Text>
          )}
        </View>

        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Weight</Text>
          {isEditing ? (
            <TextInput
              style={styles.infoInput}
              value={formData.weight}
              onChangeText={(text) => setFormData({ ...formData, weight: text })}
              keyboardType="decimal-pad"
            />
          ) : (
            <Text style={styles.infoValue}>{profile?.weight || '-'} kg</Text>
          )}
        </View>

        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Sex</Text>
          {isEditing ? (
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
          ) : (
            <Text style={styles.infoValue}>{profile?.sex || '-'}</Text>
          )}
        </View>
      </View>

      {/* Goals */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Goals & Activity</Text>
        
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Goal</Text>
          <Text style={styles.infoValue}>{getGoalLabel(profile?.goal || '')}</Text>
        </View>

        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Activity Level</Text>
          <Text style={styles.infoValue}>{getActivityLabel(profile?.activityLevel || '')}</Text>
        </View>

        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>Target Weight</Text>
          <Text style={styles.infoValue}>{profile?.targetWeight || '-'} kg</Text>
        </View>
      </View>

      {/* Nutrition Targets */}
      {profile?.dailyCalorieTarget && (
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Daily Nutrition Targets</Text>
          
          <View style={styles.nutritionGrid}>
            <View style={styles.nutritionItem}>
              <Text style={styles.nutritionValue}>{profile.dailyCalorieTarget}</Text>
              <Text style={styles.nutritionLabel}>Calories</Text>
            </View>
            <View style={styles.nutritionItem}>
              <Text style={styles.nutritionValue}>{profile.dailyProteinTarget}g</Text>
              <Text style={styles.nutritionLabel}>Protein</Text>
            </View>
            <View style={styles.nutritionItem}>
              <Text style={styles.nutritionValue}>{profile.dailyCarbTarget}g</Text>
              <Text style={styles.nutritionLabel}>Carbs</Text>
            </View>
            <View style={styles.nutritionItem}>
              <Text style={styles.nutritionValue}>{profile.dailyFatTarget}g</Text>
              <Text style={styles.nutritionLabel}>Fat</Text>
            </View>
          </View>
        </View>
      )}

      {/* Settings */}
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Settings</Text>
        
        <TouchableOpacity style={styles.settingsItem}>
          <Ionicons name="notifications" size={24} color={colors.textSecondary} />
          <Text style={styles.settingsText}>Notifications</Text>
          <Ionicons name="chevron-forward" size={20} color={colors.textMuted} />
        </TouchableOpacity>

        <TouchableOpacity style={styles.settingsItem}>
          <Ionicons name="lock-closed" size={24} color={colors.textSecondary} />
          <Text style={styles.settingsText}>Change Password</Text>
          <Ionicons name="chevron-forward" size={20} color={colors.textMuted} />
        </TouchableOpacity>

        <TouchableOpacity style={styles.settingsItem}>
          <Ionicons name="help-circle" size={24} color={colors.textSecondary} />
          <Text style={styles.settingsText}>Help & Support</Text>
          <Ionicons name="chevron-forward" size={20} color={colors.textMuted} />
        </TouchableOpacity>
      </View>

      {/* Logout */}
      <TouchableOpacity style={styles.logoutButton} onPress={handleLogout}>
        <Ionicons name="log-out" size={24} color={colors.error} />
        <Text style={styles.logoutText}>Logout</Text>
      </TouchableOpacity>

      <Text style={styles.version}>ThriveLens v1.0.0</Text>
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
  editButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: borderRadius.full,
    backgroundColor: colors.primary + '20',
  },
  editButtonText: {
    ...typography.bodySmall,
    color: colors.primary,
    fontWeight: '600',
  },
  saveButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    borderRadius: borderRadius.full,
  },
  saveButtonText: {
    ...typography.button,
  },
  avatarSection: {
    alignItems: 'center',
    marginBottom: spacing.xl,
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: spacing.md,
  },
  avatarText: {
    fontSize: 32,
    fontWeight: '700',
    color: colors.white,
  },
  email: {
    ...typography.body,
    color: colors.textSecondary,
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
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.surfaceBorder,
  },
  infoLabel: {
    ...typography.body,
    color: colors.textSecondary,
  },
  infoValue: {
    ...typography.body,
    fontWeight: '500',
  },
  infoInput: {
    backgroundColor: colors.surfaceLight,
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: borderRadius.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    minWidth: 100,
    color: colors.text,
    textAlign: 'right',
  },
  segmentControl: {
    flexDirection: 'row',
    backgroundColor: colors.surfaceLight,
    borderRadius: borderRadius.sm,
    padding: 2,
  },
  segmentOption: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: borderRadius.sm - 2,
  },
  segmentOptionActive: {
    backgroundColor: colors.primary,
  },
  segmentText: {
    ...typography.bodySmall,
    color: colors.textSecondary,
  },
  segmentTextActive: {
    color: colors.white,
    fontWeight: '600',
  },
  nutritionGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.md,
  },
  nutritionItem: {
    flex: 1,
    minWidth: '42%',
    backgroundColor: colors.surfaceLight,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    alignItems: 'center',
  },
  nutritionValue: {
    ...typography.h3,
    color: colors.primary,
  },
  nutritionLabel: {
    ...typography.caption,
    marginTop: spacing.xs,
  },
  settingsItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.surfaceBorder,
    gap: spacing.md,
  },
  settingsText: {
    ...typography.body,
    flex: 1,
  },
  logoutButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.error + '20',
    borderRadius: borderRadius.md,
    padding: spacing.lg,
    marginTop: spacing.lg,
    gap: spacing.sm,
  },
  logoutText: {
    ...typography.button,
    color: colors.error,
  },
  version: {
    ...typography.caption,
    textAlign: 'center',
    marginTop: spacing.xl,
    marginBottom: spacing.xxl,
  },
});