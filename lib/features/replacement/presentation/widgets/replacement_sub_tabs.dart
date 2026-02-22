import 'package:flutter/material.dart';

/// Enum pour les sous-onglets de remplacement/échange
enum ReplacementSubTab {
  pending,      // Demandes en attente
  myRequests,   // Mes demandes
  toValidate,   // À valider (chef)
  history,      // Historique
}

/// Enum pour les sous-onglets de recherche d'agent (AgentQuery)
enum AgentQuerySubTab {
  pending,     // Recherches en attente (notifié)
  myRequests,  // Mes demandes (créées par moi)
  history,     // Historique (matchées, annulées)
}

/// Configuration d'un sous-onglet de remplacement
class SubTabConfig {
  final ReplacementSubTab type;
  final IconData icon;
  final String label;

  const SubTabConfig({
    required this.type,
    required this.icon,
    required this.label,
  });
}

/// Configuration d'un sous-onglet de recherche d'agent
class AgentQuerySubTabConfig {
  final AgentQuerySubTab type;
  final IconData icon;
  final String label;

  const AgentQuerySubTabConfig({
    required this.type,
    required this.icon,
    required this.label,
  });
}

/// Liste des sous-onglets disponibles (remplacements)
const List<SubTabConfig> replacementSubTabs = [
  SubTabConfig(
    type: ReplacementSubTab.pending,
    icon: Icons.hourglass_empty,
    label: 'En attente',
  ),
  SubTabConfig(
    type: ReplacementSubTab.myRequests,
    icon: Icons.person_search_rounded,
    label: 'Mes demandes',
  ),
  SubTabConfig(
    type: ReplacementSubTab.toValidate,
    icon: Icons.check_circle_outline,
    label: 'À valider',
  ),
  SubTabConfig(
    type: ReplacementSubTab.history,
    icon: Icons.history,
    label: 'Historique',
  ),
];

/// Liste des sous-onglets de recherche d'agent
const List<AgentQuerySubTabConfig> agentQuerySubTabs = [
  AgentQuerySubTabConfig(
    type: AgentQuerySubTab.pending,
    icon: Icons.hourglass_empty,
    label: 'En attente',
  ),
  AgentQuerySubTabConfig(
    type: AgentQuerySubTab.myRequests,
    icon: Icons.person_search_rounded,
    label: 'Mes demandes',
  ),
  AgentQuerySubTabConfig(
    type: AgentQuerySubTab.history,
    icon: Icons.history,
    label: 'Historique',
  ),
];
