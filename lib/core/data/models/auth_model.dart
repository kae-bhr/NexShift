import 'package:cloud_firestore/cloud_firestore.dart';

class Auth {
  final String licence;
  final String id;
  final String station;
  final String? sdisId;
  final bool consumed;
  final DateTime? consumedAt;

  Auth({
    required this.licence,
    required this.id,
    required this.station,
    this.sdisId,
    this.consumed = false,
    this.consumedAt,
  });

  // Permet de dupliquer l'objet avec un champ modifié
  Auth copyWith({
    String? licence,
    String? id,
    String? station,
    String? sdisId,
    bool? consumed,
    DateTime? consumedAt,
  }) {
    return Auth(
      licence: licence ?? this.licence,
      id: id ?? this.id,
      station: station ?? this.station,
      sdisId: sdisId ?? this.sdisId,
      consumed: consumed ?? this.consumed,
      consumedAt: consumedAt ?? this.consumedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'licence': licence,
        'id': id,
        'station': station,
        if (sdisId != null) 'sdisId': sdisId,
        'consumed': consumed,
        'consumedAt': consumedAt != null ? Timestamp.fromDate(consumedAt!) : null,
      };

  factory Auth.fromJson(Map<String, dynamic> json) => Auth(
        licence: json['licence'] as String,
        id: json['id'] as String,
        station: json['station'] as String,
        sdisId: json['sdisId'] as String?,
        consumed: json['consumed'] as bool? ?? false,
        consumedAt: json['consumedAt'] != null
            ? (json['consumedAt'] as Timestamp).toDate()
            : null,
      );
}
