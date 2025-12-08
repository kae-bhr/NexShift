import 'package:cloud_firestore/cloud_firestore.dart';

class Position {
  final String id;
  final String name;
  final String stationId;
  final int order;
  final String? description;
  final String? iconName;

  Position({
    required this.id,
    required this.name,
    required this.stationId,
    required this.order,
    this.description,
    this.iconName,
  });

  factory Position.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Position(
      id: doc.id,
      name: data['name'] as String,
      stationId: data['stationId'] as String,
      order: data['order'] as int,
      description: data['description'] as String?,
      iconName: data['iconName'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'stationId': stationId,
      'order': order,
      if (description != null) 'description': description,
      if (iconName != null) 'iconName': iconName,
    };
  }

  Position copyWith({
    String? id,
    String? name,
    String? stationId,
    int? order,
    String? description,
    String? iconName,
  }) {
    return Position(
      id: id ?? this.id,
      name: name ?? this.name,
      stationId: stationId ?? this.stationId,
      order: order ?? this.order,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
    );
  }

  @override
  String toString() {
    return 'Position(id: $id, name: $name, stationId: $stationId, order: $order, description: $description, iconName: $iconName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Position &&
        other.id == id &&
        other.name == name &&
        other.stationId == stationId &&
        other.order == order &&
        other.description == description &&
        other.iconName == iconName;
  }

  @override
  int get hashCode {
    return Object.hash(id, name, stationId, order, description, iconName);
  }
}
