import React from 'react';
import { Redirect } from 'expo-router';
import { useAuthStore } from '../src/context/AuthStore';
import { View, ActivityIndicator } from 'react-native';
import { colors } from '../src/utils/theme';

export default function Index() {
  const { isAuthenticated, isLoading, profile } = useAuthStore();

  if (isLoading) {
    return (
      <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: colors.background }}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  if (!isAuthenticated) {
    return <Redirect href="/(auth)/login" />;
  }

  // If authenticated but no profile, go to onboarding
  if (!profile) {
    return <Redirect href="/onboarding" />;
  }

  return <Redirect href="/(tabs)/home" />;
}