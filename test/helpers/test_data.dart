/// Helpers pour créer des données de test réutilisables
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/services/replacement_notification_service.dart';

/// Crée une demande de remplacement de test
Map<String, dynamic> createTestReplacementRequest({
  String id = 'test-request-123',
  String requesterId = 'user-requester',
  String planningId = 'planning-123',
  DateTime? startTime,
  DateTime? endTime,
  String station = 'Saint-Vaast-La-Hougue',
  String? team = 'A',
  ReplacementRequestStatus status = ReplacementRequestStatus.pending,
  String? replacerId,
  DateTime? acceptedAt,
  DateTime? acceptedStartTime,
  DateTime? acceptedEndTime,
  int currentWave = 1,
  List<String> notifiedUserIds = const [],
  DateTime? lastWaveSentAt,
  RequestType requestType = RequestType.replacement,
  List<String>? requiredSkills,
}) {
  final now = DateTime.now();
  final defaultStartTime = startTime ?? now.add(const Duration(hours: 1));
  final defaultEndTime = endTime ?? now.add(const Duration(hours: 9));

  return {
    'id': id,
    'requesterId': requesterId,
    'planningId': planningId,
    'startTime': Timestamp.fromDate(defaultStartTime),
    'endTime': Timestamp.fromDate(defaultEndTime),
    'station': station,
    'team': team,
    'createdAt': Timestamp.fromDate(now),
    'status': status.toString().split('.').last,
    if (replacerId != null) 'replacerId': replacerId,
    if (acceptedAt != null) 'acceptedAt': Timestamp.fromDate(acceptedAt),
    if (acceptedStartTime != null)
      'acceptedStartTime': Timestamp.fromDate(acceptedStartTime),
    if (acceptedEndTime != null)
      'acceptedEndTime': Timestamp.fromDate(acceptedEndTime),
    'currentWave': currentWave,
    'notifiedUserIds': notifiedUserIds,
    if (lastWaveSentAt != null)
      'lastWaveSentAt': Timestamp.fromDate(lastWaveSentAt),
    'requestType': requestType.toString().split('.').last,
    if (requiredSkills != null) 'requiredSkills': requiredSkills,
  };
}

/// Crée un utilisateur de test
Map<String, dynamic> createTestUser({
  String id = 'user-123',
  String firstName = 'John',
  String lastName = 'Doe',
  String email = 'john.doe@test.com',
  String station = 'Saint-Vaast-La-Hougue',
  String? team = 'A',
  String status = 'active',
  List<String> skills = const [],
}) {
  return {
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'station': station,
    'team': team,
    'status': status,
    'skills': skills,
  };
}

/// Crée un planning de test
Map<String, dynamic> createTestPlanning({
  String id = 'planning-123',
  String team = 'A',
  String station = 'Saint-Vaast-La-Hougue',
  DateTime? startTime,
  DateTime? endTime,
  List<String> agentsId = const [],
}) {
  final now = DateTime.now();
  final defaultStartTime = startTime ?? now;
  final defaultEndTime = endTime ?? now.add(const Duration(hours: 24));

  return {
    'id': id,
    'team': team,
    'station': station,
    'startTime': Timestamp.fromDate(defaultStartTime),
    'endTime': Timestamp.fromDate(defaultEndTime),
    'agentsId': agentsId,
  };
}

/// Crée un subshift de test
Map<String, dynamic> createTestSubshift({
  String id = 'subshift-123',
  String planningId = 'planning-123',
  DateTime? start,
  DateTime? end,
  String replacedId = 'user-replaced',
  String replacerId = 'user-replacer',
}) {
  final now = DateTime.now();
  final defaultStart = start ?? now.add(const Duration(hours: 1));
  final defaultEnd = end ?? now.add(const Duration(hours: 9));

  return {
    'id': id,
    'planningId': planningId,
    'start': Timestamp.fromDate(defaultStart),
    'end': Timestamp.fromDate(defaultEnd),
    'replacedId': replacedId,
    'replacerId': replacerId,
  };
}
