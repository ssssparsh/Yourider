import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TextInput,
  TouchableOpacity,
  Picker,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { transactionAPI, guestAPI } from '../services/api';

export default function AddTransactionScreen({ navigation }) {
  const [guests, setGuests] = useState([]);
  const [selectedGuest, setSelectedGuest] = useState('');
  const [type, setType] = useState('room');
  const [paymentMethod, setPaymentMethod] = useState('cash');
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    loadGuests();
  }, []);

  const loadGuests = async () => {
    try {
      const response = await guestAPI.getAll();
      setGuests(response.data);
      if (response.data.length > 0) {
        setSelectedGuest(response.data[0].id);
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to load guests');
      console.error('Load guests error:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async () => {
    if (!selectedGuest || !amount) {
      Alert.alert('Error', 'Please fill all required fields');
      return;
    }

    setSubmitting(true);
    try {
      await transactionAPI.create({
        guestId: selectedGuest,
        type,
        paymentMethod,
        amount: parseFloat(amount),
        description: description || undefined,
      });

      Alert.alert('Success', 'Transaction recorded successfully', [
        {
          text: 'OK',
          onPress: () => {
            setAmount('');
            setDescription('');
            setType('room');
            setPaymentMethod('cash');
          },
        },
      ]);
    } catch (error) {
      Alert.alert('Error', 'Failed to create transaction');
      console.error('Create transaction error:', error);
    } finally {
      setSubmitting(false);
    }
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
      <View style={styles.form}>
        <Text style={styles.title}>Record Transaction</Text>

        <View style={styles.formGroup}>
          <Text style={styles.label}>Guest *</Text>
          <Picker
            selectedValue={selectedGuest}
            onValueChange={setSelectedGuest}
            style={styles.picker}
          >
            <Picker.Item label="Select Guest" value="" />
            {guests.map((guest) => (
              <Picker.Item key={guest.id} label={guest.name} value={guest.id} />
            ))}
          </Picker>
        </View>

        <View style={styles.formGroup}>
          <Text style={styles.label}>Type *</Text>
          <Picker
            selectedValue={type}
            onValueChange={setType}
            style={styles.picker}
          >
            <Picker.Item label="Room Charge" value="room" />
            <Picker.Item label="Food/Beverage" value="food" />
            <Picker.Item label="Service Charge" value="service" />
          </Picker>
        </View>

        <View style={styles.formGroup}>
          <Text style={styles.label}>Amount *</Text>
          <TextInput
            style={styles.input}
            placeholder="Enter amount"
            value={amount}
            onChangeText={setAmount}
            keyboardType="decimal-pad"
            editable={!submitting}
          />
        </View>

        <View style={styles.formGroup}>
          <Text style={styles.label}>Payment Method *</Text>
          <Picker
            selectedValue={paymentMethod}
            onValueChange={setPaymentMethod}
            style={styles.picker}
          >
            <Picker.Item label="Cash" value="cash" />
            <Picker.Item label="Card" value="card" />
          </Picker>
        </View>

        <View style={styles.formGroup}>
          <Text style={styles.label}>Description</Text>
          <TextInput
            style={[styles.input, styles.textArea]}
            placeholder="Enter description (optional)"
            value={description}
            onChangeText={setDescription}
            multiline
            numberOfLines={3}
            editable={!submitting}
          />
        </View>

        <TouchableOpacity
          style={[styles.submitButton, submitting && styles.disabledButton]}
          onPress={handleSubmit}
          disabled={submitting}
        >
          {submitting ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.submitButtonText}>Record Transaction</Text>
          )}
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
  form: {
    backgroundColor: '#fff',
    margin: 16,
    borderRadius: 12,
    padding: 20,
  },
  title: {
    fontSize: 20,
    fontWeight: '700',
    color: '#333',
    marginBottom: 24,
  },
  formGroup: {
    marginBottom: 20,
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
  textArea: {
    minHeight: 80,
    paddingTop: 12,
  },
  picker: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
  },
  submitButton: {
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
  submitButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
