import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { useAuthStore } from '../utils/authStore';

export default function LoginScreen() {
  const [username, setUsername] = useState('receptionist1');
  const [pin, setPin] = useState('1234');
  const { login, isLoading, error } = useAuthStore();

  const handleLogin = async () => {
    if (!username || !pin) {
      Alert.alert('Error', 'Please enter username and PIN');
      return;
    }

    const success = await login(username, pin);
    if (!success && error) {
      Alert.alert('Login Failed', error);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Guest Facility Manager</Text>
      <Text style={styles.subtitle}>Secure Income & Expense Tracking</Text>

      <View style={styles.formContainer}>
        <View style={styles.inputGroup}>
          <Text style={styles.label}>Username</Text>
          <TextInput
            style={styles.input}
            placeholder="Enter username"
            value={username}
            onChangeText={setUsername}
            editable={!isLoading}
            autoCapitalize="none"
          />
        </View>

        <View style={styles.inputGroup}>
          <Text style={styles.label}>PIN</Text>
          <TextInput
            style={styles.input}
            placeholder="Enter PIN"
            value={pin}
            onChangeText={setPin}
            secureTextEntry
            editable={!isLoading}
            keyboardType="numeric"
          />
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

        {error && <Text style={styles.errorText}>{error}</Text>}
      </View>

      <View style={styles.credentialsContainer}>
        <Text style={styles.credentialsTitle}>Demo Credentials:</Text>
        <Text style={styles.credentials}>Receptionist: receptionist1 / 1234</Text>
        <Text style={styles.credentials}>Owner: owner / 5678</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
    padding: 20,
    justifyContent: 'center',
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#333',
    textAlign: 'center',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
    marginBottom: 40,
  },
  formContainer: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 24,
    marginBottom: 24,
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
  loginButton: {
    backgroundColor: '#2196F3',
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
  },
  credentialsContainer: {
    backgroundColor: '#fff3e0',
    borderRadius: 8,
    padding: 12,
  },
  credentialsTitle: {
    fontWeight: '600',
    color: '#f57c00',
    marginBottom: 8,
  },
  credentials: {
    fontSize: 12,
    color: '#666',
    marginBottom: 4,
  },
});
