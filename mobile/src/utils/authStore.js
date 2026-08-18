import create from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { authAPI } from '../services/api';

export const useAuthStore = create((set) => ({
  user: null,
  token: null,
  isLoading: false,
  error: null,

  // Login with username and password
  login: async (username, password) => {
    set({ isLoading: true, error: null });
    try {
      const response = await authAPI.login(username, password);
      const { token, user } = response.data;

      await AsyncStorage.setItem('authToken', token);
      await AsyncStorage.setItem('user', JSON.stringify(user));

      set({ user, token, isLoading: false });
      return true;
    } catch (error) {
      const errorMessage =
        error.response?.data?.error || 'Login failed';
      set({ error: errorMessage, isLoading: false });
      return false;
    }
  },

  // Change password
  changePassword: async (currentPassword, newPassword, confirmPassword) => {
    set({ isLoading: true, error: null });
    try {
      const response = await authAPI.changePassword(
        currentPassword,
        newPassword,
        confirmPassword
      );
      set({ isLoading: false });
      return { success: true, message: response.data.message };
    } catch (error) {
      const errorMessage =
        error.response?.data?.error || 'Failed to change password';
      set({ error: errorMessage, isLoading: false });
      return { success: false, message: errorMessage };
    }
  },

  logout: async () => {
    await AsyncStorage.removeItem('authToken');
    await AsyncStorage.removeItem('user');
    set({ user: null, token: null });
  },

  restoreSession: async () => {
    try {
      const token = await AsyncStorage.getItem('authToken');
      const userJson = await AsyncStorage.getItem('user');

      if (token && userJson) {
        const user = JSON.parse(userJson);
        set({ token, user });
        return true;
      }
    } catch (error) {
      console.error('Restore session error:', error);
    }
    return false;
  },

  setError: (error) => set({ error }),
  clearError: () => set({ error: null }),
}));
