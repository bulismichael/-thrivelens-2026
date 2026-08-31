import { create } from 'zustand';
import * as SecureStore from 'expo-secure-store';
import { authAPI } from '../services/api';

interface User {
  id: string;
  email: string;
  createdAt: string;
}

interface Profile {
  id: string;
  userId: string;
  age: number;
  height: number;
  sex: 'male' | 'female' | 'other';
  weight: number;
  activityLevel: string;
  goal: string;
  targetWeight?: number;
  dailyCalorieTarget?: number;
  dailyProteinTarget?: number;
  dailyCarbTarget?: number;
  dailyFatTarget?: number;
}

interface AuthState {
  user: User | null;
  profile: Profile | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;

  // Actions
  initialize: () => Promise<void>;
  register: (email: string, password: string, confirmPassword: string) => Promise<void>;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  setProfile: (profile: Profile) => void;
  clearError: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  profile: null,
  isAuthenticated: false,
  isLoading: true,
  error: null,

  initialize: async () => {
    try {
      const token = await SecureStore.getItemAsync('accessToken');
      if (token) {
        const response = await authAPI.getMe();
        set({
          user: response.data.data.user,
          profile: response.data.data.profile,
          isAuthenticated: true,
          isLoading: false,
        });
      } else {
        set({ isLoading: false });
      }
    } catch {
      await SecureStore.deleteItemAsync('accessToken');
      await SecureStore.deleteItemAsync('refreshToken');
      set({ isLoading: false });
    }
  },

  register: async (email, password, confirmPassword) => {
    try {
      set({ error: null });
      const response = await authAPI.register({ email, password, confirmPassword });
      const { user, accessToken, refreshToken } = response.data.data;

      await SecureStore.setItemAsync('accessToken', accessToken);
      await SecureStore.setItemAsync('refreshToken', refreshToken);

      set({ user, isAuthenticated: true });
    } catch (error: any) {
      const message = error.response?.data?.error || 'Registration failed';
      set({ error: message });
      throw new Error(message);
    }
  },

  login: async (email, password) => {
    try {
      set({ error: null });
      const response = await authAPI.login({ email, password });
      const { user, accessToken, refreshToken } = response.data.data;

      await SecureStore.setItemAsync('accessToken', accessToken);
      await SecureStore.setItemAsync('refreshToken', refreshToken);

      set({ user, isAuthenticated: true });
    } catch (error: any) {
      const message = error.response?.data?.error || 'Login failed';
      set({ error: message });
      throw new Error(message);
    }
  },

  logout: async () => {
    try {
      await authAPI.logout();
    } catch {
      // Ignore logout errors
    } finally {
      await SecureStore.deleteItemAsync('accessToken');
      await SecureStore.deleteItemAsync('refreshToken');
      set({ user: null, profile: null, isAuthenticated: false });
    }
  },

  setProfile: (profile) => set({ profile }),

  clearError: () => set({ error: null }),
}));