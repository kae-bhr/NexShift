import 'package:flutter/material.dart';
import 'package:releve/core/data/models/user_model.dart';
import 'package:releve/core/data/models/planning_model.dart';
import 'package:releve/core/data/models/subshift_model.dart';
import 'package:releve/core/services/replacement_notification_service.dart';

/// Service pour la logique commune de recherche de remplaçants
class ReplacementSearchService {
  /// Trie les utilisateurs par nom de famille puis prénom
  static int sortByLastName(User a, User b) {
    final la = a.lastName.toLowerCase();
    final lb = b.lastName.toLowerCase();
    final cmp = la.compareTo(lb);
    return cmp != 0
        ? cmp
        : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
  }

  /// Filtre les membres de l'équipe qui ne sont pas dans l'astreinte
  static List<User> getTeamMembersNotInPlanning(
    List<User> allUsers,
    Planning planning,
  ) {
    return allUsers
        .where(
          (u) => u.team == planning.team && !planning.agentsId.contains(u.id),
        )
        .toList()
      ..sort(sortByLastName);
  }

  /// Récupère les agents de l'astreinte triés
  static List<User> getPlanningAgentsSorted(
    List<User> allUsers,
    Planning planning,
  ) {
    return planning.agentsId
        .map((id) => allUsers.firstWhere((u) => u.id == id, orElse: User.empty))
        .where((u) => u.id.isNotEmpty)
        .toList()
      ..sort(sortByLastName);
  }

  /// Récupère les utilisateurs qui agissent actuellement comme remplaçants
  static List<User> getReplacerUsers(
    List<User> allUsers,
    List<Subshift> existingSubshifts,
    Planning planning,
  ) {
    final planningStart = planning.startTime;
    final planningEnd = planning.endTime;

    return existingSubshifts
        .where(
          (s) =>
              s.planningId == planning.id &&
              s.end.isAfter(planningStart) &&
              s.start.isBefore(planningEnd),
        )
        .map((s) => s.replacerId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .map((id) => allUsers.firstWhere((u) => u.id == id, orElse: User.empty))
        .where((u) => u.id.isNotEmpty)
        .toList()
      ..sort(sortByLastName);
  }

  /// Vérifie si un agent est entièrement remplacé sur la période du planning
  static bool _isFullyReplaced(
    String agentId,
    List<Subshift> subshifts,
    Planning planning,
  ) {
    // Récupérer tous les subshifts qui remplacent cet agent sur ce planning
    final relevantSubshifts = subshifts
        .where((s) =>
            s.planningId == planning.id &&
            s.replacedId == agentId &&
            s.end.isAfter(planning.startTime) &&
            s.start.isBefore(planning.endTime))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (relevantSubshifts.isEmpty) return false;

    // Vérifier que les subshifts couvrent entièrement la période du planning
    var coveredUntil = planning.startTime;
    for (final s in relevantSubshifts) {
      if (s.start.isAfter(coveredUntil)) return false; // Trou non couvert
      if (s.end.isAfter(coveredUntil)) {
        coveredUntil = s.end;
      }
    }

    return !coveredUntil.isBefore(planning.endTime);
  }

  /// Construit la liste des candidats remplacés (effectif effectif de l'astreinte).
  /// Utilise planning.agents comme source unique de vérité.
  static List<User> getReplacedCandidates(
    List<User> allUsers,
    List<Subshift> existingSubshifts,
    Planning planning,
  ) {
    // Collecter tous les IDs d'agents uniques présents dans planning.agents
    final agentIds = planning.agents
        .map((a) => a.agentId)
        .toSet();

    final replacedCandidates = agentIds
        .map((id) => allUsers.firstWhere((u) => u.id == id, orElse: User.empty))
        .where((u) => u.id.isNotEmpty)
        .toList()
      ..sort(sortByLastName);

    return replacedCandidates;
  }

  /// Récupère les utilisateurs qui ne sont pas dans l'astreinte et pas de la même équipe
  static List<User> getNonPlanningNotTeam(
    List<User> allUsers,
    Planning planning,
  ) {
    return allUsers
        .where(
          (u) => !planning.agentsId.contains(u.id) && u.team != planning.team,
        )
        .toList()
      ..sort(sortByLastName);
  }

  /// Construit les items du dropdown pour les remplaçants disponibles
  static List<DropdownMenuItem<String>> buildAvailableReplacersDropdown(
    List<User> allUsers,
    Planning planning,
  ) {
    final teamMembers = getTeamMembersNotInPlanning(allUsers, planning);
    final nonTeamMembers = getNonPlanningNotTeam(allUsers, planning);

    final List<DropdownMenuItem<String>> items = [];

    if (teamMembers.isNotEmpty) {
      items.add(
        const DropdownMenuItem<String>(
          value: '__team_header__',
          enabled: false,
          child: Text(
            "Membres de l'équipe (hors astreinte)",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      items.addAll(
        teamMembers.map((u) {
          return DropdownMenuItem(
            value: u.id,
            child: Text(u.displayName),
          );
        }),
      );
      items.add(
        const DropdownMenuItem<String>(
          value: '__divider__',
          enabled: false,
          child: Divider(),
        ),
      );
    }

    items.addAll(
      nonTeamMembers.map((u) {
        return DropdownMenuItem(
          value: u.id,
          child: Text(u.displayName),
        );
      }),
    );

    return items;
  }

  /// Lance la recherche de remplaçant en créant une demande et envoyant les notifications
  static Future<void> searchForReplacer(
    BuildContext context, {
    required String requesterId,
    required String planningId,
    required DateTime? startDateTime,
    required DateTime? endDateTime,
    required String station,
    String? team,
    bool isSOS = false,
    VoidCallback? onValidate,
  }) async {
    if (onValidate != null) {
      onValidate();
    }

    if (startDateTime == null || endDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez sélectionner les horaires.")),
      );
      return;
    }

    // Afficher un indicateur de chargement
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Envoi des notifications... 📤"),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // Créer la demande de remplacement et envoyer les notifications
      final notificationService = ReplacementNotificationService();
      await notificationService.createReplacementRequest(
        requesterId: requesterId,
        planningId: planningId,
        startTime: startDateTime,
        endTime: endDateTime,
        station: station,
        team: team,
        isSOS: isSOS,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Notifications envoyées avec succès !"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
        // Fermer la page après l'envoi des notifications
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Erreur : $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
