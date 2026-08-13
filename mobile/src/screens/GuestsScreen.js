import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  ActivityIndicator,
  Alert,
  RefreshControl,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { guestAPI } from '../services/api';

export default function GuestsScreen({ navigation }) {
  const [guests, setGuests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  useFocusEffect(
    useCallback(() => {
      loadGuests();
    }, [])
  );

  const loadGuests = async () => {
    try {
      const response = await guestAPI.getAll();
      setGuests(response.data);
    } catch (error) {
      Alert.alert('Error', 'Failed to load guests');
      console.error('Load guests error:', error);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = async () => {
    setRefreshing(true);
    await loadGuests();
  };

  const renderGuest = ({ item }) => (
    <TouchableOpacity
      style={styles.guestCard}
      onPress={() => navigation.navigate('GuestDetail', { guestId: item.id })}
    >
      <View style={styles.guestHeader}>
        <View>
          <Text style={styles.guestName}>{item.name}</Text>
          <Text style={styles.guestId}>ID: {item.id_number}</Text>
        </View>
        <Text style={styles.roomCount}>
          {item.room_count} room{item.room_count !== 1 ? 's' : ''}
        </Text>
      </View>
      <View style={styles.guestFooter}>
        <Text style={styles.guestDate}>
          Check-in: {new Date(item.check_in).toLocaleDateString()}
        </Text>
        <Text style={styles.viewButton}>View Ledger →</Text>
      </View>
    </TouchableOpacity>
  );

  if (loading && guests.length === 0) {
    return (
      <View style={styles.centerContainer}>
        <ActivityIndicator size="large" color="#2196F3" />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <TouchableOpacity
        style={styles.addButton}
        onPress={() => navigation.navigate('AddGuest')}
      >
        <Text style={styles.addButtonText}>+ Add New Guest</Text>
      </TouchableOpacity>

      {guests.length === 0 ? (
        <View style={styles.emptyContainer}>
          <Text style={styles.emptyText}>No guests yet</Text>
        </View>
      ) : (
        <FlatList
          data={guests}
          renderItem={renderGuest}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.listContent}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
        />
      )}
    </View>
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
  addButton: {
    backgroundColor: '#2196F3',
    margin: 16,
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 8,
    justifyContent: 'center',
    alignItems: 'center',
  },
  addButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  listContent: {
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  guestCard: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 16,
    marginBottom: 12,
    borderLeftWidth: 4,
    borderLeftColor: '#2196F3',
  },
  guestHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 12,
  },
  guestName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 4,
  },
  guestId: {
    fontSize: 12,
    color: '#999',
  },
  roomCount: {
    fontSize: 12,
    fontWeight: '600',
    color: '#2196F3',
    backgroundColor: '#e3f2fd',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  guestFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingTop: 8,
    borderTopWidth: 1,
    borderTopColor: '#eee',
  },
  guestDate: {
    fontSize: 12,
    color: '#666',
  },
  viewButton: {
    fontSize: 12,
    color: '#2196F3',
    fontWeight: '600',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyText: {
    fontSize: 16,
    color: '#999',
  },
});
