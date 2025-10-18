/// Defines a crew position/role on a vehicle with required skills
class CrewPosition {
  final String id; // e.g., 'driver', 'team_leader', 'crew_member_1'
  final String label; // e.g., 'Conducteur', 'Chef d'agrès', 'Équipier 1'
  final List<String> requiredSkills; // Skills needed for this position
  final List<String>?
  fallbackSkills; // Optional: fallback skills if required skills not met
  final bool requiresAll; // true = must have ALL skills, false = at least one
  final bool
  isOptional; // true = position is optional (e.g., learners/apprenants)

  const CrewPosition({
    required this.id,
    required this.label,
    required this.requiredSkills,
    this.fallbackSkills,
    this.requiresAll = true, // by default, all skills are required
    this.isOptional = false, // by default, positions are mandatory
  });

  /// Check if a user qualifies for this position
  /// Returns [true, false] if user has required skills
  /// Returns [true, true] if user has fallback skills (when required skills not met)
  /// Returns [false, false] if user doesn't qualify at all
  ({bool canFill, bool isFallback}) canUserFillPosition(
    List<String> userSkills,
  ) {
    if (requiredSkills.isEmpty) return (canFill: true, isFallback: false);

    // Check if user has all required skills
    final hasRequired = requiresAll
        ? requiredSkills.every((skill) => userSkills.contains(skill))
        : requiredSkills.any((skill) => userSkills.contains(skill));

    if (hasRequired) {
      return (canFill: true, isFallback: false);
    }

    // If not, check fallback skills
    if (fallbackSkills != null && fallbackSkills!.isNotEmpty) {
      final hasFallback = requiresAll
          ? fallbackSkills!.every((skill) => userSkills.contains(skill))
          : fallbackSkills!.any((skill) => userSkills.contains(skill));

      if (hasFallback) {
        return (canFill: true, isFallback: true);
      }
    }

    return (canFill: false, isFallback: false);
  }

  CrewPosition copyWith({
    String? id,
    String? label,
    List<String>? requiredSkills,
    List<String>? fallbackSkills,
    bool? requiresAll,
    bool? isOptional,
  }) => CrewPosition(
    id: id ?? this.id,
    label: label ?? this.label,
    requiredSkills: requiredSkills ?? this.requiredSkills,
    fallbackSkills: fallbackSkills ?? this.fallbackSkills,
    requiresAll: requiresAll ?? this.requiresAll,
    isOptional: isOptional ?? this.isOptional,
  );
}
