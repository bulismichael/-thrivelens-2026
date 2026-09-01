import * as SecureStore from 'expo-secure-store';
import { Platform } from 'react-native';

const isWeb = Platform.OS === 'web';

// Fallback for web: use localStorage
const webStorage = {
  async getItemAsync(key: string): Promise<string | null> {
    try {
      if (typeof window !== 'undefined' && window.localStorage) {
        return window.localStorage.getItem(key);
      }
    } catch {}
    return null;
  },
  async setItemAsync(key: string, value: string): Promise<void> {
    try {
      if (typeof window !== 'undefined' && window.localStorage) {
        window.localStorage.setItem(key, value);
      }
    } catch {}
  },
  async deleteItemAsync(key: string): Promise<void> {
    try {
      if (typeof window !== 'undefined' && window.localStorage) {
        window.localStorage.removeItem(key);
      }
    } catch {}
  },
};

export const storage = isWeb ? webStorage : SecureStore;

export async function getItem(key: string): Promise<string | null> {
  try {
    return await storage.getItemAsync(key);
  } catch {
    return null;
  }
}

export async function setItem(key: string, value: string): Promise<void> {
  try {
    await storage.setItemAsync(key, value);
  } catch (e) {
    console.warn('storage setItem failed', e);
  }
}

export async function deleteItem(key: string): Promise<void> {
  try {
    await storage.deleteItemAsync(key);
  } catch {}
}
