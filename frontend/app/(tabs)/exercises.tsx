import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  TextInput,
  ActivityIndicator,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { exercisesAPI } from '../../src/services/api';
import { colors, spacing, borderRadius, typography } from '../../src/utils/theme';

const BODY_PARTS = [
  { id: 'chest', name: 'Chest', icon: 'body', color: colors.chest },
  { id: 'back', name: 'Back', icon: 'body', color: colors.back },
  { id: 'shoulders', name: 'Shoulders', icon: 'body', color: colors.shoulders },
  { id: 'arms', name: 'Arms', icon: 'body', color: colors.arms },
  { id: 'legs', name: 'Legs', icon: 'body', color: colors.legs },
  { id: 'core', name: 'Core', icon: 'body', color: colors.core },
  { id: 'cardio', name: 'Cardio', icon: 'heart', color: colors.cardio },
  { id: 'full_body', name: 'Full Body', icon: 'body', color: colors.fullBody },
];

const DIFFICULTIES = ['beginner', 'intermediate', 'advanced'];

export default function ExercisesScreen() {
  const [exercises, setExercises] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedBodyPart, setSelectedBodyPart] = useState<string | null>(null);
  const [selectedDifficulty, setSelectedDifficulty] = useState<string | null>(null);

  const fetchExercises = async () => {
    try {
      setLoading(true);
      const params: any = {};
      if (searchQuery) params.search = searchQuery;
      if (selectedBodyPart) params.bodyPart = selectedBodyPart;
      if (selectedDifficulty) params.difficulty = selectedDifficulty;

      const response = await exercisesAPI.list(params);
      setExercises(response.data.data);
    } catch (error) {
      console.error('Error fetching exercises:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchExercises();
  }, [selectedBodyPart, selectedDifficulty]);

  const handleSearch = () => {
    fetchExercises();
  };

  const renderBodyPart = ({ item }: { item: typeof BODY_PARTS[0] }) => (
    <TouchableOpacity
      style={[
        styles.bodyPartChip,
        selectedBodyPart === item.id && { backgroundColor: item.color },
      ]}
      onPress={() => setSelectedBodyPart(selectedBodyPart === item.id ? null : item.id)}
    >
      <Ionicons
        name={item.icon as any}
        size={16}
        color={selectedBodyPart === item.id ? colors.white : item.color}
      />
      <Text
        style={[
          styles.bodyPartText,
          selectedBodyPart === item.id && { color: colors.white },
        ]}
      >
        {item.name}
      </Text>
    </TouchableOpacity>
  );

  const renderExercise = ({ item }: { item: any }) => (
    <TouchableOpacity style={styles.exerciseCard}>
      <View style={[styles.exerciseIcon, { backgroundColor: getBodyPartColor(item.body_part) + '20' }]}>
        <Ionicons name="fitness" size={24} color={getBodyPartColor(item.body_part)} />
      </View>
      <View style={styles.exerciseInfo}>
        <Text style={styles.exerciseName}>{item.name}</Text>
        <Text style={styles.exerciseMeta}>
          {item.body_part.replace('_', ' ').toUpperCase()} • {item.difficulty}
        </Text>
        {item.muscle_groups && item.muscle_groups.length > 0 && (
          <Text style={styles.exerciseMuscles}>
            {item.muscle_groups.slice(0, 3).join(', ')}
          </Text>
        )}
      </View>
      <Ionicons name="chevron-forward" size={20} color={colors.textMuted} />
    </TouchableOpacity>
  );

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Exercises</Text>
        <TouchableOpacity style={styles.addButton}>
          <Ionicons name="add" size={24} color={colors.white} />
        </TouchableOpacity>
      </View>

      <View style={styles.searchContainer}>
        <View style={styles.searchBox}>
          <Ionicons name="search" size={20} color={colors.textMuted} />
          <TextInput
            style={styles.searchInput}
            placeholder="Search exercises..."
            placeholderTextColor={colors.textMuted}
            value={searchQuery}
            onChangeText={setSearchQuery}
            onSubmitEditing={handleSearch}
            returnKeyType="search"
          />
        </View>
      </View>

      <View style={styles.filterContainer}>
        <FlatList
          horizontal
          data={BODY_PARTS}
          renderItem={renderBodyPart}
          keyExtractor={(item) => item.id}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.bodyPartList}
        />
      </View>

      <View style={styles.difficultyFilter}>
        {DIFFICULTIES.map((diff) => (
          <TouchableOpacity
            key={diff}
            style={[
              styles.difficultyChip,
              selectedDifficulty === diff && styles.difficultyChipActive,
            ]}
            onPress={() => setSelectedDifficulty(selectedDifficulty === diff ? null : diff)}
          >
            <Text
              style={[
                styles.difficultyText,
                selectedDifficulty === diff && styles.difficultyTextActive,
              ]}
            >
              {diff.charAt(0).toUpperCase() + diff.slice(1)}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      {loading ? (
        <ActivityIndicator size="large" color={colors.primary} style={styles.loader} />
      ) : (
        <FlatList
          data={exercises}
          renderItem={renderExercise}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.list}
          ListEmptyComponent={
            <Text style={styles.emptyText}>No exercises found</Text>
          }
        />
      )}
    </View>
  );
}

function getBodyPartColor(bodyPart: string): string {
  const colors: Record<string, string> = {
    chest: '#FF6B6B',
    back: '#4ECDC4',
    shoulders: '#45B7D1',
    arms: '#96CEB4',
    legs: '#FFEAA7',
    core: '#DDA0DD',
    cardio: '#FF8A80',
    full_body: '#B39DDB',
  };
  return colors[bodyPart] || colors.primary;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: spacing.lg,
    paddingTop: spacing.xxl + 40,
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
  searchContainer: {
    paddingHorizontal: spacing.lg,
    marginBottom: spacing.md,
  },
  searchBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    paddingHorizontal: spacing.md,
    gap: spacing.sm,
  },
  searchInput: {
    flex: 1,
    height: 48,
    color: colors.text,
    fontSize: 16,
  },
  filterContainer: {
    marginBottom: spacing.md,
  },
  bodyPartList: {
    paddingHorizontal: spacing.lg,
    gap: spacing.sm,
  },
  bodyPartChip: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: borderRadius.full,
    gap: spacing.xs,
  },
  bodyPartText: {
    ...typography.bodySmall,
    fontWeight: '500',
  },
  difficultyFilter: {
    flexDirection: 'row',
    paddingHorizontal: spacing.lg,
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  difficultyChip: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: borderRadius.full,
    backgroundColor: colors.surface,
  },
  difficultyChipActive: {
    backgroundColor: colors.primary,
  },
  difficultyText: {
    ...typography.bodySmall,
    color: colors.textSecondary,
  },
  difficultyTextActive: {
    color: colors.white,
    fontWeight: '600',
  },
  list: {
    padding: spacing.lg,
    gap: spacing.sm,
  },
  exerciseCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    marginBottom: spacing.sm,
  },
  exerciseIcon: {
    width: 48,
    height: 48,
    borderRadius: borderRadius.sm,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: spacing.md,
  },
  exerciseInfo: {
    flex: 1,
  },
  exerciseName: {
    ...typography.body,
    fontWeight: '500',
  },
  exerciseMeta: {
    ...typography.caption,
    marginTop: spacing.xs,
    textTransform: 'uppercase',
  },
  exerciseMuscles: {
    ...typography.caption,
    color: colors.textSecondary,
    marginTop: spacing.xs,
  },
  loader: {
    flex: 1,
    justifyContent: 'center',
  },
  emptyText: {
    ...typography.body,
    color: colors.textMuted,
    textAlign: 'center',
    padding: spacing.xxl,
  },
});