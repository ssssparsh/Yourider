import axios from 'axios';
import AsyncStorage from '@react-native-async-storage/async-storage';

const API_URL = 'http://localhost:5000/api'; // Change to your server URL

const apiClient = axios.create({
  baseURL: API_URL,
  timeout: 10000,
});

// Add token to requests
apiClient.interceptors.request.use(
  async (config) => {
    const token = await AsyncStorage.getItem('authToken');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// Auth API
export const authAPI = {
  login: (username, pin) =>
    apiClient.post('/auth/login', { username, pin }),
  getCurrentUser: () =>
    apiClient.get('/auth/me'),
};

// Guest API
export const guestAPI = {
  getAll: () =>
    apiClient.get('/guests'),
  getById: (guestId) =>
    apiClient.get(`/guests/${guestId}`),
  create: (data) =>
    apiClient.post('/guests', data),
  update: (guestId, data) =>
    apiClient.put(`/guests/${guestId}`, data),
  addRoom: (guestId, roomData) =>
    apiClient.post(`/guests/${guestId}/rooms`, roomData),
};

// Transaction API
export const transactionAPI = {
  create: (data) =>
    apiClient.post('/transactions', data),
  getByGuest: (guestId) =>
    apiClient.get(`/transactions/guest/${guestId}`),
  getById: (transactionId) =>
    apiClient.get(`/transactions/${transactionId}`),
  update: (transactionId, data) =>
    apiClient.put(`/transactions/${transactionId}`, data),
  delete: (transactionId, reason) =>
    apiClient.delete(`/transactions/${transactionId}`, {
      data: { deletionReason: reason },
    }),
  getDailyReport: (startDate, endDate) =>
    apiClient.get('/transactions/report/daily', {
      params: { startDate, endDate },
    }),
};

// Expense API
export const expenseAPI = {
  create: (data) =>
    apiClient.post('/expenses', data),
  getAll: (params) =>
    apiClient.get('/expenses', { params }),
  getById: (expenseId) =>
    apiClient.get(`/expenses/${expenseId}`),
  update: (expenseId, data) =>
    apiClient.put(`/expenses/${expenseId}`, data),
  delete: (expenseId, reason) =>
    apiClient.delete(`/expenses/${expenseId}`, {
      data: { deletionReason: reason },
    }),
  getSummary: (startDate, endDate) =>
    apiClient.get('/expenses/summary/category', {
      params: { startDate, endDate },
    }),
};

// Reports API
export const reportAPI = {
  getDailySummary: (date) =>
    apiClient.get('/reports/daily-summary', { params: { date } }),
  getRevenueByGuest: (startDate, endDate) =>
    apiClient.get('/reports/revenue-by-guest', {
      params: { startDate, endDate },
    }),
  getRevenueByType: (startDate, endDate) =>
    apiClient.get('/reports/revenue-by-type', {
      params: { startDate, endDate },
    }),
  getStaffActivity: (userId, startDate, endDate) =>
    apiClient.get('/reports/staff-activity', {
      params: { userId, startDate, endDate },
    }),
  getAuditTrail: (entityType, entityId, startDate, endDate) =>
    apiClient.get('/reports/audit-trail', {
      params: { entityType, entityId, startDate, endDate },
    }),
  getOutstandingBalances: () =>
    apiClient.get('/reports/outstanding-balances'),
};

export default apiClient;
