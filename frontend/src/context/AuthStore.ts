import { create } from 'zustand';
import { getItem, setItem, deleteItem } from '../utils/storage';
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
      const token = await getItem('accessToken');
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
    } catch (error: any) {
      console.warn('Auth initialize failed:', error?.message);
      await deleteItem('accessToken');
      await deleteItem('refreshToken');
      set({ isLoading: false, isAuthenticated: false, user: null, profile: null });
    }
  },

  register: async (email, password, confirmPassword) => {
    try {
      set({ error: null, isLoading: true });
      const response = await authAPI.register({ email, password, confirmPassword });
      const { user, accessToken, refreshToken } = response.data.data;

      await setItem('accessToken', accessToken);
      await setItem('refreshToken', refreshToken);

      set({ user, isAuthenticated: true, isLoading: false });
    } catch (error: any) {
      const detail = error.response?.data?.errors?.[0]?.message;
      const message = detail || error.response?.data?.error || error.response?.data?.message || error.message || 'Registration failed';
      set({ error: message, isLoading: false });
      throw new Error(message);
    }
  },

  login: async (email, password) => {
    try {
      set({ error: null, isLoading: true });
      const response = await authAPI.login({ email, password });
      const { user, accessToken, refreshToken } = response.data.data;

      await setItem('accessToken', accessToken);
      await setItem('refreshToken', refreshToken);

      // Fetch profile after login to determine onboarding need
      try {
        const me = await authAPI.getMe();
        set({ user: me.data.data.user, profile: me.data.data.profile, isAuthenticated: true, isLoading: false });
      } catch {
        set({ user, isAuthenticated: true, isLoading: false });
      }
    } catch (error: any) {
      const detail = error.response?.data?.errors?.[0]?.message;
      const message = detail || error.response?.data?.error || error.response?.data?.message || error.message || 'Login failed';
      // Handle network errors
      if (!error.response) {
        const netMsg = 'Unable to reach server. Check your connection.';
        set({ error: netMsg, isLoading: false });
        throw new Error(netMsg);
      }
      set({ error: message, isLoading: false });
      throw new Error(message);
    }
  },

  logout: async () => {
    try {
      await authAPI.logout();
    } catch {
      // Ignore logout errors
    } finally {
      await deleteItem('accessToken');
      await deleteItem('refreshToken');
      set({ user: null, profile: null, isAuthenticated: false, isLoading: false });
    }
  },

  setProfile: (profile) => set({ profile }),

  clearError: () => set({ error: null }),
}));