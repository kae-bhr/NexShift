import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle pour les codes d'authentification permettant de créer une station
/// Structure: /sdis/{sdisId}/auth_codes/{authCodeId}
class AuthCode {
  final String code;
  final String stationName;
  final bool consumed;
  final DateTime? consumedAt;
  final String? consumedBy;
  final bool trial;

  AuthCode({
    required this.code,
    required this.stationName,
    this.consumed = false,
    this.consumedAt,
    this.consumedBy,
    this.trial = false,
  });

  AuthCode copyWith({
    String? code,
    String? stationName,
    bool? consumed,
    DateTime? consumedAt,
    String? consumedBy,
    bool? trial,
  }) {
    return AuthCode(
      code: code ?? this.code,
      stationName: stationName ?? this.stationName,
      consumed: consumed ?? this.consumed,
      consumedAt: consumedAt ?? this.consumedAt,
      consumedBy: consumedBy ?? this.consumedBy,
      trial: trial ?? this.trial,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'stationName': stationName,
        'consumed': consumed,
        'consumedAt': consumedAt != null ? Timestamp.fromDate(consumedAt!) : null,
        'consumedBy': consumedBy,
        'trial': trial,
      };

  factory AuthCode.fromJson(Map<String, dynamic> json) => AuthCode(
        code: json['code'] as String,
        stationName: json['stationName'] as String,
        consumed: json['consumed'] as bool? ?? false,
        consumedAt: json['consumedAt'] != null
            ? (json['consumedAt'] as Timestamp).toDate()
            : null,
        consumedBy: json['consumedBy'] as String?,
        trial: json['trial'] as bool? ?? false,
      );
}
