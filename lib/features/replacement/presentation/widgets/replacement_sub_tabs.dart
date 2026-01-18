import 'package:flutter/material.dart';

/// Enum pour les sous-onglets de remplacement/échange
enum ReplacementSubTab {
  pending,      // Demandes en attente
  myRequests,   // Mes demandes
  toValidate,   // À valider (chef)
  history,      // Historique
}

/// Configuration d'un sous-onglet
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

/// Liste des sous-onglets disponibles
const List<SubTabConfig> replacementSubTabs = [
  SubTabConfig(
    type: ReplacementSubTab.pending,
    icon: Icons.hourglass_empty,
    label: 'En attente',
  ),
  SubTabConfig(
    type: ReplacementSubTab.myRequests,
    icon: Icons.person,
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
