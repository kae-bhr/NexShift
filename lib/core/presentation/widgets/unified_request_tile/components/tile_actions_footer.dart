import 'package:flutter/material.dart';
import '../unified_tile_enums.dart';

/// Pied de tuile affichant les actions disponibles selon le mode de vue.
///
/// - [TileViewMode.pending] / [TileViewMode.toValidate] : 2 boutons pleine largeur
/// - [TileViewMode.myRequests] : barre d'actions tintée collée au bas de la carte
/// - [TileViewMode.history] : vide
class TileActionsFooter extends StatelessWidget {
  final TileViewMode viewMode;
  final UnifiedRequestType requestType;
  final bool canAct;

  final int? currentWave;
  final int? proposalCount;
  final bool usesWaveSystem;

  final VoidCallback? onAccept;
  final VoidCallback? onRefuse;
  final VoidCallback? onValidate;
  final VoidCallback? onDelete;
  final VoidCallback? onWaveTap;
  final VoidCallback? onHistoryTap;
  final VoidCallback? onProposalsTap;
  final VoidCallback? onResendNotifications;
  final VoidCallback? onUnlockKeySkills;
  final VoidCallback? onViewDetails;

  final String? acceptButtonText;
  final String? refuseButtonText;

  const TileActionsFooter({
    super.key,
    required this.viewMode,
    required this.requestType,
    required this.canAct,
    this.currentWave,
    this.proposalCount,
    this.usesWaveSystem = false,
    this.onAccept,
    this.onRefuse,
    this.onValidate,
    this.onDelete,
    this.onWaveTap,
    this.onHistoryTap,
    this.onProposalsTap,
    this.onResendNotifications,
    this.onUnlockKeySkills,
    this.onViewDetails,
    this.acceptButtonText,
    this.refuseButtonText,
  });

  @override
  Widget build(BuildContext context) {
    switch (viewMode) {
      case TileViewMode.history:
        return _buildTintedFooter(_historyItems());
      case TileViewMode.pending:
        return _buildTintedFooter(_pendingItems());
      case TileViewMode.toValidate:
        return _buildTintedFooter(_toValidateItems());
      case TileViewMode.myRequests:
        return _buildTintedFooter(_myRequestsItems());
    }
  }

  // ── Items par mode ────────────────────────────────────────────────────────

  List<_FooterItem> _historyItems() {
    final items = <_FooterItem>[];
    if (usesWaveSystem && currentWave != null) {
      items.add(_FooterItem(
        icon: Icons.waves_rounded,
        label: 'Vague $currentWave',
        color: Colors.blue.shade700,
        onTap: onWaveTap,
      ));
    }
    if (onHistoryTap != null) {
      items.add(_FooterItem(
        icon: Icons.history_rounded,
        label: 'Historique',
        color: Colors.grey.shade600,
        onTap: onHistoryTap,
      ));
    }
    return items;
  }

  List<_FooterItem> _pendingItems() {
    final items = <_FooterItem>[];
    if (onViewDetails != null) {
      items.add(_FooterItem(
        icon: Icons.open_in_new_rounded,
        label: 'Voir',
        color: _accentColor(),
        onTap: onViewDetails,
        showArrow: true,
      ));
    }
    if (usesWaveSystem && currentWave != null) {
      items.add(_FooterItem(
        icon: Icons.waves_rounded,
        label: 'Vague $currentWave',
        color: Colors.blue.shade700,
        onTap: onWaveTap,
      ));
    }
    if (onUnlockKeySkills != null) {
      items.add(_FooterItem(
        icon: Icons.lock_open_rounded,
        label: 'Débloquer',
        color: Colors.deepPurple.shade600,
        onTap: onUnlockKeySkills,
      ));
    }
    if (canAct) {
      if (onRefuse != null) {
        items.add(_FooterItem(
          icon: Icons.close_rounded,
          label: refuseButtonText ?? 'Refuser',
          color: Colors.red.shade600,
          onTap: onRefuse,
        ));
      }
      if (onAccept != null) {
        items.add(_FooterItem(
          icon: Icons.check_rounded,
          label: acceptButtonText ?? 'Accepter',
          color: Colors.green.shade700,
          onTap: onAccept,
        ));
      }
    }
    return items;
  }

  List<_FooterItem> _toValidateItems() {
    final items = <_FooterItem>[];
    if (onViewDetails != null) {
      items.add(_FooterItem(
        icon: Icons.open_in_new_rounded,
        label: 'Voir',
        color: _accentColor(),
        onTap: onViewDetails,
        showArrow: true,
      ));
    }
    if (canAct) {
      if (onRefuse != null) {
        items.add(_FooterItem(
          icon: Icons.close_rounded,
          label: refuseButtonText ?? 'Refuser',
          color: Colors.red.shade600,
          onTap: onRefuse,
        ));
      }
      if (onValidate != null) {
        items.add(_FooterItem(
          icon: Icons.check_rounded,
          label: 'Valider',
          color: Colors.green.shade700,
          onTap: onValidate,
        ));
      }
    }
    return items;
  }

  List<_FooterItem> _myRequestsItems() {
    final items = <_FooterItem>[];
    if (onViewDetails != null) {
      items.add(_FooterItem(
        icon: Icons.open_in_new_rounded,
        label: 'Voir',
        color: _accentColor(),
        onTap: onViewDetails,
        showArrow: true,
      ));
    }
    if (usesWaveSystem && currentWave != null) {
      items.add(_FooterItem(
        icon: Icons.waves_rounded,
        label: 'Vague $currentWave',
        color: Colors.blue.shade700,
        onTap: onWaveTap,
      ));
    }
    if (proposalCount != null) {
      final hasAny = proposalCount! > 0;
      items.add(_FooterItem(
        icon: Icons.people_outline_rounded,
        label: '$proposalCount proposition${proposalCount! > 1 ? 's' : ''}',
        color: hasAny ? Colors.purple.shade700 : Colors.grey.shade500,
        onTap: hasAny ? onProposalsTap : null,
        showArrow: hasAny,
      ));
    }
    if (onResendNotifications != null) {
      items.add(_FooterItem(
        icon: Icons.notifications_active_rounded,
        label: 'Relancer',
        color: Colors.orange.shade700,
        onTap: onResendNotifications,
      ));
    }
    if (onUnlockKeySkills != null) {
      items.add(_FooterItem(
        icon: Icons.lock_open_rounded,
        label: 'Débloquer',
        color: Colors.deepPurple.shade600,
        onTap: onUnlockKeySkills,
      ));
    }
    if (onDelete != null) {
      items.add(_FooterItem(
        icon: Icons.delete_outline_rounded,
        label: 'Supprimer',
        color: Colors.red.shade600,
        onTap: onDelete,
      ));
    }
    return items;
  }

  // ── Barre tintée partagée ─────────────────────────────────────────────────

  Widget _buildTintedFooter(List<_FooterItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    final accentColor = _accentColor();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.06),
          border: Border(
            top: BorderSide(color: accentColor.withValues(alpha: 0.15), width: 1),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0)
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: accentColor.withValues(alpha: 0.12),
                  ),
                Expanded(child: _FooterActionCell(item: items[i])),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _accentColor() {
    switch (requestType) {
      case UnifiedRequestType.automaticReplacement:
        return Colors.blue;
      case UnifiedRequestType.sosReplacement:
        return Colors.red;
      case UnifiedRequestType.manualReplacement:
        return Colors.purple;
      case UnifiedRequestType.exchange:
      case UnifiedRequestType.agentQuery:
        return Colors.teal;
      case UnifiedRequestType.teamEvent:
        return const Color(0xFF8B4B44);
    }
  }
}

// ── Modèle d'item ──────────────────────────────────────────────────────────

class _FooterItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool showArrow;

  const _FooterItem({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.showArrow = false,
  });
}

// ── Cellule cliquable ──────────────────────────────────────────────────────

class _FooterActionCell extends StatelessWidget {
  final _FooterItem item;

  const _FooterActionCell({required this.item});

  @override
  Widget build(BuildContext context) {
    final enabled = item.onTap != null;

    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 15,
              color: enabled ? item.color : item.color.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 5),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: enabled ? item.color : item.color.withValues(alpha: 0.4),
                letterSpacing: -0.1,
              ),
            ),
            if (item.showArrow) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 13,
                color: item.color.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
