import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/generation_options_model.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Écran d'aperçu des impacts d'une génération de plannings.
/// Affiche tous les changements qui seront effectués avant confirmation.
class GenerationImpactPage extends StatefulWidget {
  final GenerationImpact impact;
  final GenerationOptions options;

  /// Appelé quand l'utilisateur confirme la génération.
  final VoidCallback onConfirm;

  const GenerationImpactPage({
    super.key,
    required this.impact,
    required this.options,
    required this.onConfirm,
  });

  @override
  State<GenerationImpactPage> createState() => _GenerationImpactPageState();
}

class _GenerationImpactPageState extends State<GenerationImpactPage> {
  final _teamRepository = TeamRepository();
  final _userRepository = UserRepository();

  Map<String, Team> _teamsById = {};
  Map<String, String> _agentNamesById = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final teams = await _teamRepository.getAll();
    final agentIds = <String>{};

    for (final impact in widget.impact.subshiftImpacts) {
      agentIds.add(impact.original.replacedId);
      agentIds.add(impact.original.replacerId);
    }

    // Charger le nom complet des agents concernés
    final Map<String, String> names = {};
    for (final id in agentIds) {
      try {
        final user = await _userRepository.getById(id);
        if (user != null) {
          names[id] = '${user.firstName} ${user.lastName}';
        } else {
          names[id] = id;
        }
      } catch (_) {
        names[id] = id;
      }
    }

    if (mounted) {
      setState(() {
        _teamsById = {for (final t in teams) t.id: t};
        _agentNamesById = names;
        _loading = false;
      });
    }
  }

  Color _teamColor(String teamId) =>
      _teamsById[teamId]?.color ?? Colors.grey.shade400;

  String _teamName(String teamId) =>
      _teamsById[teamId]?.name ?? 'Équipe $teamId';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Aperçu des impacts',
        bottomColor: KColors.appNameColor,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final impact = widget.impact;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _buildSummaryChips(impact),
        const SizedBox(height: 20),
        if (impact.planningsToDelete.isNotEmpty) ...[
          _ImpactSection(
            icon: Icons.delete_outline,
            label: 'PLANNINGS SUPPRIMÉS',
            color: Colors.red.shade700,
            count: impact.planningsToDelete.length,
            children: _buildPlanningTiles(impact.planningsToDelete, isDelete: true),
          ),
          const SizedBox(height: 12),
        ],
        if (impact.planningsToAdd.isNotEmpty) ...[
          _ImpactSection(
            icon: Icons.add_circle_outline,
            label: 'PLANNINGS CRÉÉS',
            color: Colors.green.shade700,
            count: impact.planningsToAdd.length,
            children: _buildPlanningTiles(impact.planningsToAdd, isDelete: false),
          ),
          const SizedBox(height: 12),
        ],
        if (impact.hasReplacementImpacts) ...[
          _buildReplacementsSection(impact),
        ],
        if (impact.planningsToDelete.isEmpty &&
            impact.planningsToAdd.isEmpty &&
            !impact.hasReplacementImpacts)
          _buildNoImpact(),
      ],
    );
  }

  Widget _buildSummaryChips(GenerationImpact impact) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(
          label: '${impact.planningsToDelete.length} supprimés',
          color: Colors.red.shade600,
          icon: Icons.remove_circle_outline,
        ),
        _SummaryChip(
          label: '${impact.planningsToAdd.length} créés',
          color: Colors.green.shade600,
          icon: Icons.add_circle_outline,
        ),
        if (impact.partiallyPreservedCount > 0)
          _SummaryChip(
            label: '${impact.partiallyPreservedCount} rempl. ajustés',
            color: Colors.orange.shade700,
            icon: Icons.tune,
          ),
        if (impact.orphanedCount > 0)
          _SummaryChip(
            label: '${impact.orphanedCount} rempl. orphelins',
            color: Colors.grey.shade600,
            icon: Icons.link_off,
          ),
        if (impact.overwrittenCount > 0)
          _SummaryChip(
            label: '${impact.overwrittenCount} rempl. écrasés',
            color: Colors.deepOrange.shade600,
            icon: Icons.delete_forever_outlined,
          ),
      ],
    );
  }

  List<Widget> _buildPlanningTiles(List<Planning> plannings, {required bool isDelete}) {
    final sorted = List<Planning>.from(plannings)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return sorted.map((p) {
      final color = _teamColor(p.team);
      final fmt = DateFormat('dd/MM HH:mm');
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_teamName(p.team)} — ${fmt.format(p.startTime.toUtc())} → ${fmt.format(p.endTime.toUtc())}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildReplacementsSection(GenerationImpact impact) {
    final preserved = impact.subshiftImpacts
        .where((s) => s.type == SubshiftImpactType.preserved)
        .toList();
    final adjusted = impact.subshiftImpacts
        .where((s) => s.type == SubshiftImpactType.partiallyPreserved)
        .toList();
    final orphaned = impact.subshiftImpacts
        .where((s) => s.type == SubshiftImpactType.orphaned)
        .toList();
    final overwritten = impact.subshiftImpacts
        .where((s) => s.type == SubshiftImpactType.overwritten)
        .toList();

    return _ImpactSection(
      icon: Icons.swap_horiz,
      label: 'REMPLACEMENTS',
      color: Colors.blueGrey.shade700,
      count: impact.subshiftImpacts.length,
      children: [
        if (preserved.isNotEmpty) ...[
          _SubshiftSubHeader(
            label: 'Conservés (${preserved.length})',
            color: Colors.green.shade600,
            icon: Icons.check_circle_outline,
          ),
          ...preserved.map((s) => _SubshiftTile(
                subshift: s.original,
                agentNames: _agentNamesById,
                trailing: null,
              )),
          const SizedBox(height: 8),
        ],
        if (adjusted.isNotEmpty) ...[
          _SubshiftSubHeader(
            label: 'Ajustés (${adjusted.length})',
            color: Colors.orange.shade700,
            icon: Icons.tune,
          ),
          ...adjusted.map((s) => _SubshiftTile(
                subshift: s.original,
                agentNames: _agentNamesById,
                trailing: s.adjusted,
              )),
          const SizedBox(height: 8),
        ],
        if (orphaned.isNotEmpty) ...[
          _SubshiftSubHeader(
            label: 'Orphelins (${orphaned.length})',
            color: Colors.grey.shade600,
            icon: Icons.link_off,
          ),
          ...orphaned.map((s) => _SubshiftTile(
                subshift: s.original,
                agentNames: _agentNamesById,
                trailing: null,
              )),
          const SizedBox(height: 8),
        ],
        if (overwritten.isNotEmpty) ...[
          _SubshiftSubHeader(
            label: 'Écrasés (${overwritten.length})',
            color: Colors.deepOrange.shade600,
            icon: Icons.delete_forever_outlined,
          ),
          ...overwritten.map((s) => _SubshiftTile(
                subshift: s.original,
                agentNames: _agentNamesById,
                trailing: null,
              )),
        ],
      ],
    );
  }

  Widget _buildNoImpact() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Aucun impact détecté',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Les plannings existants correspondent déjà\naux règles configurées.',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onConfirm();
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Confirmer et générer'),
                style: FilledButton.styleFrom(
                  backgroundColor: KColors.appNameColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets internes
// ---------------------------------------------------------------------------

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _SummaryChip({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ImpactSection extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int count;
  final List<Widget> children;

  const _ImpactSection({
    required this.icon,
    required this.label,
    required this.color,
    required this.count,
    required this.children,
  });

  @override
  State<_ImpactSection> createState() => _ImpactSectionState();
}

class _ImpactSectionState extends State<_ImpactSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(widget.icon, size: 16, color: widget.color),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: widget.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: widget.color,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}

class _SubshiftSubHeader extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _SubshiftSubHeader({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubshiftTile extends StatelessWidget {
  final Subshift subshift;
  final Map<String, String> agentNames;

  /// Si non null, c'est le subshift ajusté (cas de chevauchement partiel).
  final Subshift? trailing;

  const _SubshiftTile({
    required this.subshift,
    required this.agentNames,
    required this.trailing,
  });

  String _name(String id) => agentNames[id] ?? id;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm');
    final replaced = _name(subshift.replacedId);
    final replacer = _name(subshift.replacerId);
    final originalPeriod =
        '${fmt.format(subshift.start.toUtc())} → ${fmt.format(subshift.end.toUtc())}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$replacer remplace $replaced',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          if (trailing == null)
            Text(
              originalPeriod,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            )
          else ...[
            Text(
              'Avant : $originalPeriod',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            Text(
              'Après : ${fmt.format(trailing!.start.toUtc())} → ${fmt.format(trailing!.end.toUtc())}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
