import axios from 'axios';
import { Platform } from 'react-native';
import { getItem, setItem, deleteItem } from '../utils/storage';

// Derive API URL: respect env, then platform-specific fallbacks
function getApiBaseUrl(): string {
  const envUrl = process.env.EXPO_PUBLIC_API_URL;
  if (envUrl) return envUrl;
  
  // For Android emulator, localhost is 10.0.2.2
  if (Platform.OS === 'android') {
    // Use 10.0.2.2 for emulator; physical device should set EXPO_PUBLIC_API_URL to LAN IP
    return 'http://10.0.2.2:3000/api';
  }
  // iOS simulator and web can use localhost
  return 'http://localhost:3000/api';
}

const API_BASE_URL = getApiBaseUrl();

export { API_BASE_URL };

const api = axios.create({
  baseURL: API_BASE_URL,
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor to attach auth token
api.interceptors.request.use(async (config) => {
  const token = await getItem('accessToken');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  // Debug log in dev
  if (typeof __DEV__ !== 'undefined' && __DEV__) {
    console.log(`[API] ${config.method?.toUpperCase()} ${config.baseURL}${config.url}`);
  }
  return config;
});

// Response interceptor for token refresh
api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;

    if (error.response?.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true;

      try {
        const refreshToken = await getItem('refreshToken');
        if (refreshToken) {
          const response = await axios.post(`${API_BASE_URL}/auth/refresh`, {
            refreshToken,
          });

          const { accessToken, refreshToken: newRefreshToken } = response.data.data;
          await setItem('accessToken', accessToken);
          await setItem('refreshToken', newRefreshToken);

          originalRequest.headers.Authorization = `Bearer ${accessToken}`;
          return api(originalRequest);
        }
      } catch {
        await deleteItem('accessToken');
        await deleteItem('refreshToken');
      }
    }

    // Network error handling
    if (!error.response) {
      console.warn('[API] Network error:', error.message, 'URL:', API_BASE_URL);
    }

    return Promise.reject(error);
  }
);

// Auth API
export const authAPI = {
  register: (data: { email: string; password: string; confirmPassword: string }) =>
    api.post('/auth/register', data),
  login: (data: { email: string; password: string }) =>
    api.post('/auth/login', data),
  refresh: (refreshToken: string) =>
    api.post('/auth/refresh', { refreshToken }),
  logout: () => api.post('/auth/logout'),
  getMe: () => api.get('/auth/me'),
  changePassword: (data: { currentPassword: string; newPassword: string }) =>
    api.post('/auth/change-password', data),
  forgotPassword: (email: string) =>
    api.post('/auth/forgot-password', { email }),
};

// Profile API
export const profileAPI = {
  get: () => api.get('/profile'),
  createOrUpdate: (data: any) => api.post('/profile', data),
  delete: () => api.delete('/profile'),
  getNutritionTargets: () => api.get('/profile/nutrition-targets'),
};

// Exercises API
export const exercisesAPI = {
  list: (params?: any) => api.get('/exercises', { params }),
  getById: (id: string) => api.get(`/exercises/${id}`),
  getBodyParts: () => api.get('/exercises/body-parts'),
  create: (data: any) => api.post('/exercises', data),
  update: (id: string, data: any) => api.put(`/exercises/${id}`, data),
  delete: (id: string) => api.delete(`/exercises/${id}`),
};

// Workouts API
export const workoutsAPI = {
  list: (params?: any) => api.get('/workouts', { params }),
  getUpcoming: () => api.get('/workouts/upcoming'),
  getHistory: (params?: any) => api.get('/workouts/history', { params }),
  getById: (id: string) => api.get(`/workouts/${id}`),
  create: (data: any) => api.post('/workouts', data),
  update: (id: string, data: any) => api.put(`/workouts/${id}`, data),
  complete: (id: string) => api.patch(`/workouts/${id}/complete`),
  delete: (id: string) => api.delete(`/workouts/${id}`),
  updateSet: (sessionId: string, exerciseId: string, setId: string, data: any) =>
    api.patch(`/workouts/${sessionId}/exercises/${exerciseId}/sets/${setId}`, data),
};

// Meals API
export const mealsAPI = {
  list: (params?: any) => api.get('/meals', { params }),
  getDailySummary: (date?: string) => api.get('/meals/daily-summary', { params: { date } }),
  getById: (id: string) => api.get(`/meals/${id}`),
  create: (data: any) => api.post('/meals', data),
  update: (id: string, data: any) => api.put(`/meals/${id}`, data),
  delete: (id: string) => api.delete(`/meals/${id}`),
  analyzeImage: (imageUrl: string) => api.post('/meals/analyze', { imageUrl }),
};

// Progress API
export const progressAPI = {
  getMetrics: () => api.get('/progress/metrics'),
  getWeightHistory: (limit?: number) => api.get('/progress/weight-history', { params: { limit } }),
  addWeight: (data: any) => api.post('/progress/weight', data),
  updateWeight: (id: string, data: any) => api.put(`/progress/weight/${id}`, data),
  deleteWeight: (id: string) => api.delete(`/progress/weight/${id}`),
  getWeightChartData: (weeks?: number) => api.get('/progress/charts/weight', { params: { weeks } }),
  getNutritionChartData: (days?: number) => api.get('/progress/charts/nutrition', { params: { days } }),
  getWorkoutChartData: (weeks?: number) => api.get('/progress/charts/workouts', { params: { weeks } }),
};

// AI API
export const aiAPI = {
  getTips: (params?: any) => api.get('/ai/tips', { params }),
  markTipRead: (id: string) => api.patch(`/ai/tips/${id}/read`),
  generateTips: () => api.post('/ai/generate-tips'),
  analyzeProgress: () => api.post('/ai/analyze-progress'),
  getRecipeSuggestions: (data: any) => api.post('/ai/recipe-suggestions', data),
  getWorkoutSuggestions: (data: any) => api.post('/ai/workout-suggestions', data),
};

// Recipes API
export const recipesAPI = {
  list: (params?: any) => api.get('/recipes', { params }),
  search: (params: any) => api.get('/recipes/search', { params }),
  getById: (id: string) => api.get(`/recipes/${id}`),
  create: (data: any) => api.post('/recipes', data),
  update: (id: string, data: any) => api.put(`/recipes/${id}`, data),
  delete: (id: string) => api.delete(`/recipes/${id}`),
};

// Nutrition Plans API
export const nutritionPlansAPI = {
  list: () => api.get('/nutrition-plans'),
  getActive: () => api.get('/nutrition-plans/active'),
  getById: (id: string) => api.get(`/nutrition-plans/${id}`),
  create: (data: any) => api.post('/nutrition-plans', data),
  update: (id: string, data: any) => api.put(`/nutrition-plans/${id}`, data),
  activate: (id: string) => api.patch(`/nutrition-plans/${id}/activate`),
  delete: (id: string) => api.delete(`/nutrition-plans/${id}`),
  generate: () => api.post('/nutrition-plans/generate'),
};

// Workout Plans API
export const workoutPlansAPI = {
  list: () => api.get('/workout-plans'),
  getActive: () => api.get('/workout-plans/active'),
  getById: (id: string) => api.get(`/workout-plans/${id}`),
  create: (data: any) => api.post('/workout-plans', data),
  update: (id: string, data: any) => api.put(`/workout-plans/${id}`, data),
  activate: (id: string) => api.patch(`/workout-plans/${id}/activate`),
  delete: (id: string) => api.delete(`/workout-plans/${id}`),
  generate: () => api.post('/workout-plans/generate'),
};

export default api;