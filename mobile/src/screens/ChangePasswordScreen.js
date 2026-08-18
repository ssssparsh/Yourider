import React, { useState } from 'react';
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

export default function ChangePasswordScreen({ navigation }) {
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showCurrent, setShowCurrent] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const { user, changePassword, isLoading } = useAuthStore();

  const handleChangePassword = async () => {
    if (!currentPassword || !newPassword || !confirmPassword) {
      Alert.alert('Error', 'Please fill all fields');
      return;
    }

    if (newPassword !== confirmPassword) {
      Alert.alert('Error', 'New passwords do not match');
      return;
    }

    if (currentPassword === newPassword) {
      Alert.alert('Error', 'New password must be different from current password');
      return;
    }

    const result = await changePassword(currentPassword, newPassword, confirmPassword);

    if (result.success) {
      Alert.alert('Success', 'Password changed successfully', [
        {
          text: 'OK',
          onPress: () => {
            navigation.navigate('Home');
          },
        },
      ]);
    } else {
      Alert.alert('Error', result.message);
    }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.scrollContent}>
      <View style={styles.headerContainer}>
        <Text style={styles.title}>Change Password</Text>
        <Text style={styles.subtitle}>Update your account password</Text>
      </View>

      <View style={styles.formContainer}>
        {/* Current Password */}
        <View style={styles.inputGroup}>
          <Text style={styles.label}>Current Password</Text>
          <View style={styles.passwordContainer}>
            <TextInput
              style={styles.passwordInput}
              placeholder="Enter current password"
              value={currentPassword}
              onChangeText={setCurrentPassword}
              secureTextEntry={!showCurrent}
              editable={!isLoading}
              placeholderTextColor="#999"
            />
            <TouchableOpacity
              style={styles.togglePassword}
              onPress={() => setShowCurrent(!showCurrent)}
            >
              <Text style={styles.toggleText}>{showCurrent ? '👁️' : '🔒'}</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* New Password */}
        <View style={styles.inputGroup}>
          <Text style={styles.label}>New Password</Text>
          <View style={styles.passwordContainer}>
            <TextInput
              style={styles.passwordInput}
              placeholder="Enter new password"
              value={newPassword}
              onChangeText={setNewPassword}
              secureTextEntry={!showNew}
              editable={!isLoading}
              placeholderTextColor="#999"
            />
            <TouchableOpacity
              style={styles.togglePassword}
              onPress={() => setShowNew(!showNew)}
            >
              <Text style={styles.toggleText}>{showNew ? '👁️' : '🔒'}</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Confirm Password */}
        <View style={styles.inputGroup}>
          <Text style={styles.label}>Confirm Password</Text>
          <View style={styles.passwordContainer}>
            <TextInput
              style={styles.passwordInput}
              placeholder="Confirm new password"
              value={confirmPassword}
              onChangeText={setConfirmPassword}
              secureTextEntry={!showConfirm}
              editable={!isLoading}
              placeholderTextColor="#999"
            />
            <TouchableOpacity
              style={styles.togglePassword}
              onPress={() => setShowConfirm(!showConfirm)}
            >
              <Text style={styles.toggleText}>{showConfirm ? '👁️' : '🔒'}</Text>
            </TouchableOpacity>
          </View>
        </View>

        <TouchableOpacity
          style={[styles.submitButton, isLoading && styles.disabledButton]}
          onPress={handleChangePassword}
          disabled={isLoading}
        >
          {isLoading ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.submitButtonText}>Change Password</Text>
          )}
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.cancelButton}
          onPress={() => navigation.goBack()}
          disabled={isLoading}
        >
          <Text style={styles.cancelButtonText}>Cancel</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.passwordPolicyContainer}>
        <Text style={styles.policyTitle}>🔐 Password Requirements</Text>
        <Text style={styles.policyText}>✓ Minimum 6 characters</Text>
        <Text style={styles.policyText}>✓ At least 1 uppercase letter</Text>
        <Text style={styles.policyText}>✓ At least 1 number</Text>
        <Text style={styles.policyText}>✓ Different from current password</Text>
      </View>

      <View style={styles.infoContainer}>
        <Text style={styles.infoTitle}>ℹ️ Security Tips</Text>
        <Text style={styles.infoText}>
          • Use a strong, unique password
        </Text>
        <Text style={styles.infoText}>
          • Don't share your password with others
        </Text>
        <Text style={styles.infoText}>
          • Change it periodically for better security
        </Text>
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
  },
  headerContainer: {
    marginBottom: 24,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#1976D2',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 14,
    color: '#666',
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
  submitButton: {
    backgroundColor: '#1976D2',
    borderRadius: 8,
    paddingVertical: 14,
    marginTop: 20,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  disabledButton: {
    backgroundColor: '#bbb',
  },
  submitButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  cancelButton: {
    backgroundColor: '#f5f5f5',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    paddingVertical: 14,
    justifyContent: 'center',
    alignItems: 'center',
  },
  cancelButtonText: {
    color: '#666',
    fontSize: 16,
    fontWeight: '600',
  },
  passwordPolicyContainer: {
    backgroundColor: '#F3E5F5',
    borderRadius: 8,
    padding: 16,
    marginBottom: 16,
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
  infoContainer: {
    backgroundColor: '#E3F2FD',
    borderRadius: 8,
    padding: 16,
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
  },
});
