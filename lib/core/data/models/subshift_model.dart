import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class Subshift {
  final String id;
  final String replacedId;
  final String replacerId;
  final DateTime start;
  final DateTime end;
  final String planningId;

  // Champs pour l'indicateur de vérification par le chef
  final bool checkedByChief;
  final DateTime? checkedAt;
  final String? checkedBy;

  // Indique si le remplacement est issu d'un échange d'astreinte
  final bool isExchange;

  Subshift({
    required this.id,
    required this.replacedId,
    required this.replacerId,
    required this.start,
    required this.end,
    required this.planningId,
    this.checkedByChief = false,
    this.checkedAt,
    this.checkedBy,
    this.isExchange = false,
  });

  factory Subshift.create({
    required String replacedId,
    required String replacerId,
    required DateTime start,
    required DateTime end,
    required String planningId,
    bool checkedByChief = false,
    DateTime? checkedAt,
    String? checkedBy,
    bool isExchange = false,
  }) {
    return Subshift(
      id: const Uuid().v4(),
      replacedId: replacedId,
      replacerId: replacerId,
      start: start,
      end: end,
      planningId: planningId,
      checkedByChief: checkedByChief,
      checkedAt: checkedAt,
      checkedBy: checkedBy,
      isExchange: isExchange,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'replacedId': replacedId,
    'replacerId': replacerId,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'planningId': planningId,
    'checkedByChief': checkedByChief,
    if (checkedAt != null) 'checkedAt': checkedAt!.toIso8601String(),
    if (checkedBy != null) 'checkedBy': checkedBy,
    'isExchange': isExchange,
  };

  factory Subshift.fromJson(Map<String, dynamic> json) {
    try {
      return Subshift(
        id: json['id'] as String? ?? '',
        replacedId: json['replacedId'] as String? ?? '',
        replacerId: json['replacerId'] as String? ?? '',
        start: _parseDateTime(json['start']),
        end: _parseDateTime(json['end']),
        planningId: json['planningId'] as String? ?? '',
        checkedByChief: json['checkedByChief'] as bool? ?? false,
        checkedAt: json['checkedAt'] != null ? _parseDateTime(json['checkedAt']) : null,
        checkedBy: json['checkedBy'] as String?,
        isExchange: json['isExchange'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('Error parsing Subshift: $e');
      debugPrint('JSON data: $json');
      rethrow;
    }
  }

  /// Crée une copie avec les champs modifiés
  Subshift copyWith({
    String? id,
    String? replacedId,
    String? replacerId,
    DateTime? start,
    DateTime? end,
    String? planningId,
    bool? checkedByChief,
    DateTime? checkedAt,
    String? checkedBy,
    bool? isExchange,
  }) {
    return Subshift(
      id: id ?? this.id,
      replacedId: replacedId ?? this.replacedId,
      replacerId: replacerId ?? this.replacerId,
      start: start ?? this.start,
      end: end ?? this.end,
      planningId: planningId ?? this.planningId,
      checkedByChief: checkedByChief ?? this.checkedByChief,
      checkedAt: checkedAt ?? this.checkedAt,
      checkedBy: checkedBy ?? this.checkedBy,
      isExchange: isExchange ?? this.isExchange,
    );
  }

  /// Parse DateTime depuis String (ISO8601) ou Timestamp (Firestore)
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) {
      return DateTime.now();
    } else if (value is Timestamp) {
      return value.toDate();
    } else if (value is String) {
      return DateTime.parse(value);
    } else {
      debugPrint('Unknown date format: ${value.runtimeType}');
      return DateTime.now();
    }
  }
}
