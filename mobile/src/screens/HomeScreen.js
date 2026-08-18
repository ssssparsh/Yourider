import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuthStore } from '../utils/authStore';
import { reportAPI } from '../services/api';

export default function HomeScreen({ navigation }) {
  const { user, logout } = useAuthStore();
  const [todaySummary, setTodaySummary] = useState(null);
  const [loading, setLoading] = useState(true);

  // Check if user needs to change password on first login
  useFocusEffect(
    React.useCallback(() => {
      if (user?.isDefaultPassword) {
        Alert.alert(
          'Security Required',
          'You must change your default password for security. Please set a new password.',
          [
            {
              text: 'Change Now',
              onPress: () => navigation.navigate('ChangePassword'),
            },
          ],
          { cancelable: false }
        );
      }
    }, [user?.isDefaultPassword, navigation])
  );

  useEffect(() => {
    loadTodaysSummary();
  }, []);

  const loadTodaysSummary = async () => {
    try {
      const today = new Date().toISOString().split('T')[0];
      const response = await reportAPI.getDailySummary(today);
      setTodaySummary(response.data);
    } catch (error) {
      console.error('Error loading today summary:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = async () => {
    Alert.alert('Logout', 'Are you sure you want to logout?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Logout',
        onPress: async () => {
          await logout();
        },
        style: 'destructive',
      },
    ]);
  };

  if (loading) {
    return (
      <View style={styles.centerContainer}>
        <ActivityIndicator size="large" color="#2196F3" />
      </View>
    );
  }

  return (
    <ScrollView style={styles.container}>
      <View style={styles.header}>
        <View>
          <Text style={styles.greeting}>Welcome, {user?.fullName || 'Guest'}!</Text>
          <Text style={styles.role}>{user?.role === 'owner' ? 'Owner' : 'Receptionist'}</Text>
        </View>
        <TouchableOpacity style={styles.logoutButton} onPress={handleLogout}>
          <Text style={styles.logoutText}>Logout</Text>
        </TouchableOpacity>
      </View>

      {todaySummary && (
        <View style={styles.summaryContainer}>
          <Text style={styles.sectionTitle}>Today's Summary</Text>
          <View style={styles.statsGrid}>
            <View style={[styles.statCard, styles.incomeCard]}>
              <Text style={styles.statLabel}>Cash Income</Text>
              <Text style={styles.statValue}>
                ₹{todaySummary.income.cash.toFixed(2)}
              </Text>
            </View>
            <View style={[styles.statCard, styles.cardCard]}>
              <Text style={styles.statLabel}>Card Income</Text>
              <Text style={styles.statValue}>
                ₹{todaySummary.income.card.toFixed(2)}
              </Text>
            </View>
            <View style={[styles.statCard, styles.expenseCard]}>
              <Text style={styles.statLabel}>Expenses</Text>
              <Text style={styles.statValue}>
                ₹{todaySummary.expenses.toFixed(2)}
              </Text>
            </View>
            <View style={[styles.statCard, styles.profitCard]}>
              <Text style={styles.statLabel}>Net Income</Text>
              <Text style={styles.statValue}>
                ₹{todaySummary.netIncome.toFixed(2)}
              </Text>
            </View>
          </View>
        </View>
      )}

      <View style={styles.quickActionsContainer}>
        <Text style={styles.sectionTitle}>Quick Actions</Text>
        <TouchableOpacity
          style={styles.actionButton}
          onPress={() => navigation.navigate('AddTransaction')}
        >
          <Text style={styles.actionButtonText}>➕ Add Transaction</Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={styles.actionButton}
          onPress={() => navigation.navigate('Guests')}
        >
          <Text style={styles.actionButtonText}>👥 View Guests</Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={styles.actionButton}
          onPress={() => navigation.navigate('Expenses')}
        >
          <Text style={styles.actionButtonText}>💰 Add Expense</Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={styles.actionButton}
          onPress={() => navigation.navigate('Reports')}
        >
          <Text style={styles.actionButtonText}>📊 View Reports</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    backgroundColor: '#2196F3',
    padding: 20,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  greeting: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#fff',
    marginBottom: 4,
  },
  role: {
    fontSize: 14,
    color: '#e3f2fd',
  },
  logoutButton: {
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 6,
  },
  logoutText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
  summaryContainer: {
    padding: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: '#333',
    marginBottom: 12,
  },
  statsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
  },
  statCard: {
    width: '48%',
    borderRadius: 12,
    padding: 16,
    marginBottom: 12,
  },
  incomeCard: {
    backgroundColor: '#c8e6c9',
  },
  cardCard: {
    backgroundColor: '#bbdefb',
  },
  expenseCard: {
    backgroundColor: '#ffccbc',
  },
  profitCard: {
    backgroundColor: '#f8bbd0',
  },
  statLabel: {
    fontSize: 12,
    color: '#666',
    marginBottom: 8,
  },
  statValue: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
  },
  quickActionsContainer: {
    padding: 16,
  },
  actionButton: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 16,
    marginBottom: 8,
    borderLeftWidth: 4,
    borderLeftColor: '#2196F3',
  },
  actionButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
  },
});
