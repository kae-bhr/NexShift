import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/shift_rule_model.dart';
import 'package:nexshift_app/core/services/firestore_service.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

class ShiftRuleRepository {
  static const _collectionName = 'shift_rules';
  final FirestoreService _firestore = FirestoreService();

  /// Retourne le chemin de collection selon l'environnement
  String _getCollectionPath(String? stationId) {
    return EnvironmentConfig.getCollectionPath(_collectionName, stationId);
  }

  /// Récupère toutes les règles (legacy - sans stationId)
  Future<List<ShiftRule>> getAll() async {
    try {
      final data = await _firestore.getAll(_collectionName);
      return data.map((e) => ShiftRule.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getAll: $e');
      rethrow;
    }
  }

  /// Récupère les règles d'une station
  Future<List<ShiftRule>> getByStation(String stationId) async {
    try {
      final collectionPath = _getCollectionPath(stationId);

      // En mode dev (sous-collections), récupérer toutes les règles de la sous-collection
      final data = await _firestore.getAll(collectionPath);
      return data.map((e) => ShiftRule.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Firestore error in getByStation: $e');
      rethrow;
    }
  }

  /// Récupère une règle par ID
  Future<ShiftRule?> getById(String id, {String? stationId}) async {
    try {
      // En mode dev, stationId est requis
      if (stationId == null) {
        throw Exception('stationId required forgetById');
      }

      final collectionPath = _getCollectionPath(stationId);
      final data = await _firestore.getById(collectionPath, id);
      if (data != null) {
        return ShiftRule.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('Firestore error in getById: $e');
      rethrow;
    }
  }

  /// Récupère les règles actives d'une station
  Future<List<ShiftRule>> getActiveRules({String? stationId}) async {
    final all = stationId != null ? await getByStation(stationId) : await getAll();
    return all.where((r) => r.isActive).toList();
  }

  /// Sauvegarde toutes les règles
  Future<void> saveAll(List<ShiftRule> rules, {String? stationId}) async {
    if (stationId == null) {
      throw Exception('stationId required forsaveAll');
    }

    // Trier par priorité avant sauvegarde
    final sorted = List<ShiftRule>.from(rules)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    final collectionPath = _getCollectionPath(stationId);

    try {
      final operations = sorted.map((rule) => {
        'type': 'set',
        'collection': collectionPath,
        'id': rule.id,
        'data': rule.toJson(),
      }).toList();
      await _firestore.batchWrite(operations);
    } catch (e) {
      debugPrint('Firestore error during saveAll: $e');
      rethrow;
    }
  }

  /// Ajoute ou met à jour une règle
  Future<void> upsert(ShiftRule rule, {String? stationId}) async {
    try {
      // En mode dev, stationId est requis
      if (stationId == null) {
        throw Exception('stationId required forupsert');
      }

      final collectionPath = _getCollectionPath(stationId);
      await _firestore.upsert(collectionPath, rule.id, rule.toJson());
    } catch (e) {
      debugPrint('Firestore error during upsert: $e');
      rethrow;
    }
  }

  /// Supprime une règle
  Future<void> delete(String id, {String? stationId}) async {
    try {
      // En mode dev, stationId est requis
      if (stationId == null) {
        throw Exception('stationId required fordelete');
      }

      final collectionPath = _getCollectionPath(stationId);
      await _firestore.delete(collectionPath, id);
    } catch (e) {
      debugPrint('Firestore error during delete: $e');
      rethrow;
    }
  }

  /// Toggle l'état actif/inactif d'une règle
  Future<void> toggleActive(String id, {String? stationId}) async {
    final rule = await getById(id, stationId: stationId);
    if (rule != null) {
      final updated = rule.copyWith(isActive: !rule.isActive);
      await upsert(updated, stationId: stationId);
    }
  }

  /// Réinitialise avec des règles par défaut (exemple)
  Future<void> resetToDefaultRules({String? stationId}) async {
    if (stationId == null) {
      throw Exception('stationId required forresetToDefaultRules');
    }

    final now = DateTime.now();
    final oneYearLater = now.add(const Duration(days: 365));

    final defaultRules = <ShiftRule>[
      // Exemple : Astreinte nuit en semaine (19h-6h)
      ShiftRule(
        id: 'night_weekdays',
        name: 'Astreinte nuit semaine',
        startTime: const TimeOfDay(hour: 19, minute: 0),
        endTime: const TimeOfDay(hour: 6, minute: 0),
        spansNextDay: true,
        rotationType: ShiftRotationType.daily,
        teamIds: ['A', 'B', 'C', 'D'],
        applicableDays: DaysOfWeek.weekdays,
        startDate: now,
        endDate: oneYearLater,
        priority: 1,
      ),
      // Exemple : Journée non affectée (6h-19h)
      ShiftRule(
        id: 'day_unassigned',
        name: 'Journée (non affectée)',
        startTime: const TimeOfDay(hour: 6, minute: 0),
        endTime: const TimeOfDay(hour: 19, minute: 0),
        spansNextDay: false,
        rotationType: ShiftRotationType.none,
        teamIds: [],
        applicableDays: DaysOfWeek.all,
        startDate: now,
        endDate: oneYearLater,
        priority: 2,
      ),
    ];
    await saveAll(defaultRules, stationId: stationId);
  }

  /// Vide toutes les règles
  Future<void> clear() async {
    try {
      final all = await getAll();
      if (all.isNotEmpty) {
        final operations = all.map((r) => {
          'type': 'delete',
          'collection': _collectionName,
          'id': r.id,
        }).toList();
        await _firestore.batchWrite(operations);
      }
    } catch (e) {
      debugPrint('Firestore error during clear: $e');
      rethrow;
    }
  }
}
