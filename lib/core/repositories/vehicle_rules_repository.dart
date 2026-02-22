import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nexshift_app/core/data/models/vehicle_rule_set_model.dart';
import 'package:nexshift_app/core/utils/default_vehicle_rules.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository for managing vehicle crew rules
/// Handles both default rules and station-specific overrides
class VehicleRulesRepository {
  static const _collectionName = 'vehicle_rule_sets';
  final FirestoreService _firestore = FirestoreService();

  /// Retourne le chemin de collection selon l'environnement
  String _getCollectionPath(String? stationId) {
    return EnvironmentConfig.getCollectionPath(_collectionName, stationId);
  }

  // In-memory storage for station-specific rules (cache)
  static final Map<String, VehicleRuleSet> _stationRules = {};
  static const String _prefsPrefix = 'vehicle_rules::';

  String _key(String stationId, String vehicleType) =>
      '$_prefsPrefix$stationId::$vehicleType';

  /// Get rules for a vehicle type
  /// If station-specific rules exist, return them; otherwise return defaults
  Future<VehicleRuleSet?> getRules({
    required String vehicleType,
    String? stationId,
  }) async {
    // If stationId provided, try to get station-specific rules first
    if (stationId != null) {
      final customRules = await _getStationRules(vehicleType, stationId);
      if (customRules != null) {
        return customRules;
      }
    }

    // Fallback to default rules
    return KDefaultVehicleRules.getDefaultRuleSet(vehicleType);
  }

  /// Get station-specific rules from Firestore
  Future<VehicleRuleSet?> _getStationRules(
    String vehicleType,
    String stationId,
  ) async {
    final key = '${stationId}_$vehicleType';

    // First check in-memory cache
    final inMemory = _stationRules[key];
    if (inMemory != null) return inMemory;

    // Try Firestore
    try {
      final collectionPath = _getCollectionPath(stationId);
      final data = await _firestore.getById(collectionPath, key);
      if (data != null) {
        final rs = VehicleRuleSet.fromJson(data);
        _stationRules[key] = rs; // warm the cache
        return rs;
      }
    } catch (e) {
      debugPrint('Firestore error in _getStationRules: $e');
      // Try SharedPreferences as fallback for migration
      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getString(_key(stationId, vehicleType));
      if (persisted != null) {
        try {
          final map = jsonDecode(persisted) as Map<String, dynamic>;
          final rs = VehicleRuleSet.fromJson(map);
          _stationRules[key] = rs; // warm the cache
          // Migrate to Firestore
          try {
            final collectionPath = _getCollectionPath(stationId);
            await _firestore.upsert(collectionPath, key, rs.toJson());
            await prefs.remove(_key(stationId, vehicleType)); // Clean old data
          } catch (_) {}
          return rs;
        } catch (_) {
          // If decoding fails, ignore and fallback to defaults
        }
      }
    }

    return null;
  }

  /// Save station-specific rules
  Future<void> saveStationRules(VehicleRuleSet ruleSet) async {
    if (ruleSet.stationId == null) {
      throw ArgumentError('Cannot save rules without stationId');
    }

    final key = '${ruleSet.stationId}_${ruleSet.vehicleType}';
    _stationRules[key] = ruleSet;

    // Save to Firestore
    try {
      final collectionPath = _getCollectionPath(ruleSet.stationId);
      await _firestore.upsert(collectionPath, key, ruleSet.toJson());
    } catch (e) {
      debugPrint('Firestore error during saveStationRules: $e');
      rethrow;
    }
  }

  /// Delete station-specific rules (revert to defaults)
  Future<void> deleteStationRules({
    required String vehicleType,
    required String stationId,
  }) async {
    final key = '${stationId}_$vehicleType';
    _stationRules.remove(key);

    // Delete from Firestore
    try {
      final collectionPath = _getCollectionPath(stationId);
      await _firestore.delete(collectionPath, key);
    } catch (e) {
      debugPrint('Firestore error during deleteStationRules: $e');
      rethrow;
    }
  }

  /// Get all station-specific rules for a station
  Future<List<VehicleRuleSet>> getAllStationRules(String stationId) async {
    try {
      final collectionPath = _getCollectionPath(stationId);

      final data = await _firestore.getAll(collectionPath);
      final result = <VehicleRuleSet>[];

      for (final item in data) {
        try {
          final rs = VehicleRuleSet.fromJson(item);
          result.add(rs);
          final key = '${stationId}_${rs.vehicleType}';
          _stationRules[key] = rs;
        } catch (_) {
          // Skip malformed entries
        }
      }

      return result;
    } catch (e) {
      debugPrint('Firestore error in getAllStationRules: $e');
      rethrow;
    }
  }

  /// Check if station has custom rules for a vehicle type
  Future<bool> hasCustomRules({
    required String vehicleType,
    required String stationId,
  }) async {
    final key = '${stationId}_$vehicleType';
    if (_stationRules.containsKey(key)) return true;

    // Check Firestore
    try {
      final collectionPath = _getCollectionPath(stationId);
      final data = await _firestore.getById(collectionPath, key);
      return data != null;
    } catch (e) {
      debugPrint('Firestore error in hasCustomRules: $e');
      return false;
    }
  }

  /// Create default rules for a station (copy from defaults with stationId)
  Future<VehicleRuleSet?> createDefaultRulesForStation({
    required String vehicleType,
    required String stationId,
  }) async {
    final defaultRules = KDefaultVehicleRules.getDefaultRuleSet(vehicleType);
    if (defaultRules == null) return null;

    final stationRules = VehicleRuleSet(
      vehicleType: vehicleType,
      modes: defaultRules.modes,
      defaultModeId: defaultRules.defaultModeId,
      stationId: stationId,
    );

    await saveStationRules(stationRules);
    return stationRules;
  }
}
