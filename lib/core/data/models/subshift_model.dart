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

  Subshift({
    required this.id,
    required this.replacedId,
    required this.replacerId,
    required this.start,
    required this.end,
    required this.planningId,
  });

  factory Subshift.create({
    required String replacedId,
    required String replacerId,
    required DateTime start,
    required DateTime end,
    required String planningId,
  }) {
    return Subshift(
      id: const Uuid().v4(),
      replacedId: replacedId,
      replacerId: replacerId,
      start: start,
      end: end,
      planningId: planningId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'replacedId': replacedId,
    'replacerId': replacerId,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'planningId': planningId,
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
      );
    } catch (e) {
      debugPrint('Error parsing Subshift: $e');
      debugPrint('JSON data: $json');
      rethrow;
    }
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
