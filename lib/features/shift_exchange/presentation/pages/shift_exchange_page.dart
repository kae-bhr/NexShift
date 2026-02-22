import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/services/shift_exchange_service.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/presentation/widgets/planning_form_widgets.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Page de création d'une demande d'échange d'astreinte
/// Similaire à replacement_page.dart mais pour les échanges
class ShiftExchangePage extends StatefulWidget {
  final Planning planning;
  final User currentUser;

  const ShiftExchangePage({
    super.key,
    required this.planning,
    required this.currentUser,
  });

  @override
  State<ShiftExchangePage> createState() => _ShiftExchangePageState();
}

class _ShiftExchangePageState extends State<ShiftExchangePage> {
  final _exchangeService = ShiftExchangeService();
  bool _isSubmitting = false;

  // Liste des agents présents dans l'astreinte
  List<User> _agentsInPlanning = [];
  // ID de l'agent qui souhaite échanger (initiator)
  String? _initiatorId;

  /// Vérifie si l'utilisateur courant peut sélectionner l'agent à échanger
  bool get _canSelectInitiator =>
      widget.currentUser.admin ||
      widget.currentUser.status == KConstants.statusLeader ||
      (widget.currentUser.status == KConstants.statusChief &&
          widget.currentUser.team == widget.planning.team);

  @override
  void initState() {
    super.initState();
    _loadAgentsInPlanning();
    _initiatorId = widget.currentUser.id;
  }

  Future<void> _loadAgentsInPlanning() async {
    try {
      final users = await UserRepository().getByStation(
        widget.planning.station,
      );
      final baseAgentIds = widget.planning.agents
          .where((a) => a.replacedAgentId == null)
          .map((a) => a.agentId)
          .toSet();

      final agentsInPlanning = users
          .where((u) => baseAgentIds.contains(u.id))
          .toList();

      setState(() {
        _agentsInPlanning = agentsInPlanning;
        if (!baseAgentIds.contains(widget.currentUser.id)) {
          _initiatorId = null;
        }
      });
    } catch (e) {
      debugPrint('Erreur chargement agents: $e');
    }
  }

  bool get _isValid => _initiatorId != null && _initiatorId!.isNotEmpty;

  Future<void> _proposeExchange() async {
    if (_isSubmitting || !_isValid) return;

    setState(() => _isSubmitting = true);

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Envoi des notifications...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 500));

      await _exchangeService.createExchangeRequest(
        initiatorId: _initiatorId!,
        planningId: widget.planning.id,
        station: widget.planning.station,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifications envoyées ✅'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CustomAppBar(
        title: "Échange d'astreinte",
        bottomColor: KColors.appNameColor,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: (_isSubmitting || !_isValid) ? null : _proposeExchange,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.swap_horiz_rounded, size: 20),
            label: Text(
              _isSubmitting ? 'Envoi en cours...' : 'Proposer un échange',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: KColors.appNameColor,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Sélection de l'agent ────────────────────────────────────────
          _SectionHeader(
            icon: Icons.person_search_rounded,
            label: 'Agent demandeur',
          ),
          const SizedBox(height: 8),
          if (_canSelectInitiator)
            _StyledDropdown<String>(
              value: _initiatorId,
              hint: 'Sélectionnez un agent',
              items: _agentsInPlanning
                  .map(
                    (u) => DropdownMenuItem(
                      value: u.id,
                      child: Text(u.displayName),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _initiatorId = v),
            )
          else
            _ReadOnlyField(
              label: 'Agent à échanger',
              value: widget.currentUser.displayName,
            ),

          const SizedBox(height: 20),

          // ── Détails de l'astreinte ──────────────────────────────────────
          _SectionHeader(
            icon: Icons.event_rounded,
            label: "Astreinte à échanger",
          ),
          const SizedBox(height: 8),
          SharedPlanningDetailCard(planning: widget.planning),

          const SizedBox(height: 16),

          // ── Comment ça marche ───────────────────────────────────────────
          _SectionHeader(
            icon: Icons.info_outline_rounded,
            label: 'Comment ça marche ?',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              children: [
                _InfoStep(
                  number: '1',
                  text:
                      'Votre demande sera visible par tous les agents possédant vos compétences-clés',
                ),
                const SizedBox(height: 12),
                _InfoStep(
                  number: '2',
                  text:
                      'Les agents intéressés pourront proposer une ou plusieurs de leurs astreintes en échange',
                ),
                const SizedBox(height: 12),
                _InfoStep(
                  number: '3',
                  text:
                      'Vous sélectionnerez la proposition qui vous convient le mieux',
                ),
                const SizedBox(height: 12),
                _InfoStep(
                  number: '4',
                  text: "Les chefs des deux équipes devront valider l'échange",
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Widgets locaux réutilisables ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

class _StyledDropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _StyledDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint),
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          borderRadius: BorderRadius.circular(12),
          dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_rounded,
            size: 18,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoStep extends StatelessWidget {
  final String number;
  final String text;

  const _InfoStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: KColors.appNameColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: KColors.appNameColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }
}
