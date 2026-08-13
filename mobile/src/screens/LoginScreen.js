import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Alert,
  ScrollView,
} from 'react-native';
import { useAuthStore } from '../utils/authStore';

export default function LoginScreen({ navigation }) {
  const [username, setUsername] = useState('receptionist1');
  const [password, setPassword] = useState('Reception@123');
  const [showPassword, setShowPassword] = useState(false);
  const { login, isLoading, error, user } = useAuthStore();

  useEffect(() => {
    if (user?.isDefaultPassword) {
      Alert.alert(
        'Change Password Required',
        'You must change your default password on first login for security.'
      );
    }
  }, [user?.isDefaultPassword]);

  const handleLogin = async () => {
    if (!username || !password) {
      Alert.alert('Error', 'Please enter username and password');
      return;
    }

    const success = await login(username, password);
    if (!success && error) {
      Alert.alert('Login Failed', error);
    }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.scrollContent}>
      <View style={styles.headerContainer}>
        <Text style={styles.title}>Guest Facility Manager</Text>
        <Text style={styles.subtitle}>Secure Income & Expense Tracking</Text>
      </View>

      <View style={styles.formContainer}>
        <View style={styles.inputGroup}>
          <Text style={styles.label}>Username</Text>
          <TextInput
            style={styles.input}
            placeholder="Enter your username"
            value={username}
            onChangeText={setUsername}
            editable={!isLoading}
            autoCapitalize="none"
            placeholderTextColor="#999"
          />
        </View>

        <View style={styles.inputGroup}>
          <Text style={styles.label}>Password</Text>
          <View style={styles.passwordContainer}>
            <TextInput
              style={styles.passwordInput}
              placeholder="Enter your password"
              value={password}
              onChangeText={setPassword}
              secureTextEntry={!showPassword}
              editable={!isLoading}
              placeholderTextColor="#999"
            />
            <TouchableOpacity
              style={styles.togglePassword}
              onPress={() => setShowPassword(!showPassword)}
            >
              <Text style={styles.toggleText}>{showPassword ? '👁️' : '🔒'}</Text>
            </TouchableOpacity>
          </View>
        </View>

        <TouchableOpacity
          style={[styles.loginButton, isLoading && styles.disabledButton]}
          onPress={handleLogin}
          disabled={isLoading}
        >
          {isLoading ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.loginButtonText}>Login</Text>
          )}
        </TouchableOpacity>

        {error && <Text style={styles.errorText}>❌ {error}</Text>}
      </View>

      <View style={styles.infoContainer}>
        <Text style={styles.infoTitle}>📋 Default Credentials</Text>
        <Text style={styles.infoText}>
          <Text style={styles.bold}>Receptionist 1:</Text> receptionist1 / Reception@123
        </Text>
        <Text style={styles.infoText}>
          <Text style={styles.bold}>Receptionist 2:</Text> receptionist2 / Reception@456
        </Text>
        <Text style={styles.infoText}>
          <Text style={styles.bold}>Owner:</Text> owner / Owner@5678
        </Text>
        <Text style={styles.warningText}>
          ⚠️ You MUST change your password on first login for security.
        </Text>
      </View>

      <View style={styles.passwordPolicyContainer}>
        <Text style={styles.policyTitle}>🔐 Password Requirements</Text>
        <Text style={styles.policyText}>✓ Minimum 6 characters</Text>
        <Text style={styles.policyText}>✓ At least 1 uppercase letter</Text>
        <Text style={styles.policyText}>✓ At least 1 number</Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollContent: {
    padding: 16,
    paddingTop: 40,
  },
  headerContainer: {
    marginBottom: 32,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#1976D2',
    textAlign: 'center',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
  },
  formContainer: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 20,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  inputGroup: {
    marginBottom: 16,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
    marginBottom: 8,
  },
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
    color: '#333',
  },
  passwordContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    paddingRight: 8,
  },
  passwordInput: {
    flex: 1,
    padding: 12,
    fontSize: 16,
    color: '#333',
  },
  togglePassword: {
    padding: 8,
  },
  toggleText: {
    fontSize: 18,
  },
  loginButton: {
    backgroundColor: '#1976D2',
    borderRadius: 8,
    paddingVertical: 14,
    marginTop: 20,
    justifyContent: 'center',
    alignItems: 'center',
  },
  disabledButton: {
    backgroundColor: '#bbb',
  },
  loginButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  errorText: {
    color: '#d32f2f',
    marginTop: 12,
    textAlign: 'center',
    fontSize: 14,
    fontWeight: '500',
  },
  infoContainer: {
    backgroundColor: '#E3F2FD',
    borderRadius: 8,
    padding: 16,
    marginBottom: 16,
    borderLeftWidth: 4,
    borderLeftColor: '#1976D2',
  },
  infoTitle: {
    fontSize: 14,
    fontWeight: '700',
    color: '#1565C0',
    marginBottom: 10,
  },
  infoText: {
    fontSize: 12,
    color: '#444',
    marginBottom: 6,
    fontFamily: 'monospace',
  },
  bold: {
    fontWeight: '600',
    color: '#1565C0',
  },
  warningText: {
    fontSize: 12,
    color: '#D32F2F',
    marginTop: 10,
    fontWeight: '600',
  },
  passwordPolicyContainer: {
    backgroundColor: '#F3E5F5',
    borderRadius: 8,
    padding: 16,
    borderLeftWidth: 4,
    borderLeftColor: '#7B1FA2',
  },
  policyTitle: {
    fontSize: 14,
    fontWeight: '700',
    color: '#6A1B9A',
    marginBottom: 10,
  },
  policyText: {
    fontSize: 12,
    color: '#444',
    marginBottom: 6,
  },
});
