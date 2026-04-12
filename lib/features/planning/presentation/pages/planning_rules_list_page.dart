import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/models/shift_rule_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/repositories/shift_rule_repository.dart';
import 'package:nexshift_app/core/repositories/shift_exception_repository.dart';
import 'package:nexshift_app/core/services/planning_generation_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/planning/presentation/pages/edit_shift_rule_page.dart';
import 'package:nexshift_app/core/data/models/generation_options_model.dart';
import 'package:nexshift_app/core/data/models/shift_exception_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/features/planning/presentation/pages/generation_impact_page.dart';
import 'package:nexshift_app/features/planning/presentation/pages/shift_exceptions_page.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/config/environment_config.dart';

class PlanningRulesListPage extends StatefulWidget {
  const PlanningRulesListPage({super.key});

  @override
  State<PlanningRulesListPage> createState() => _PlanningRulesListPageState();
}

class _PlanningRulesListPageState extends State<PlanningRulesListPage> {
  final _repository = ShiftRuleRepository();
  final _generationService = PlanningGenerationService();
  List<ShiftRule> _rules = [];
  List<ShiftRule> _activeRules = [];
  bool _isLoading = true;
  bool _isGenerating = false;
  User? _currentUser;
  Station? _stationConfig;
  bool _isInitialized = false;
  bool _canManageRules = false; // Mettre en cache au lieu d'un getter

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final stopwatch = Stopwatch()..start();
    try {
      _currentUser = await UserStorageHelper.loadUser();
      if (_currentUser != null) {
        await _loadStationConfig();
      }
      if (mounted) {
        await _loadRules();
        setState(() {
          _isInitialized = true;
          _updateCanManageRules();
        });
        debugPrint(
          'PlanningRulesListPage: Data loaded in ${stopwatch.elapsedMilliseconds}ms',
        );
      }
    } catch (e) {
      debugPrint('PlanningRulesListPage: Error loading data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialized = true;
          _updateCanManageRules();
        });
      }
    }
  }

  Future<void> _loadStationConfig() async {
    if (_currentUser == null) return;

    try {
      final stationDoc = await FirebaseFirestore.instance
          .collection(EnvironmentConfig.stationsCollectionPath)
          .doc(_currentUser!.station)
          .get();

      if (stationDoc.exists && mounted) {
        setState(() {
          _stationConfig = Station.fromJson({
            'id': stationDoc.id,
            ...stationDoc.data()!,
          });
        });
      }
    } catch (e) {
      debugPrint('PlanningRulesListPage: Error loading station config: $e');
    }
  }

  Future<void> _loadRules() async {
    if (!mounted || _currentUser == null) return;
    final stopwatch = Stopwatch()..start();
    setState(() => _isLoading = true);
    try {
      final rules = await _repository.getByStation(_currentUser!.station);
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _activeRules = rules.where((r) => r.isActive).toList();
        _isLoading = false;
      });
      debugPrint(
        'PlanningRulesListPage: Rules loaded (${rules.length} total, ${_activeRules.length} active) in ${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      debugPrint('PlanningRulesListPage: Error loading rules: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _updateCanManageRules() {
    if (!_isInitialized || _currentUser == null) {
      _canManageRules = false;
    } else {
      _canManageRules =
          _currentUser!.admin ||
          _currentUser!.status == KConstants.statusLeader;
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      'PlanningRulesListPage: Building widget (loading=$_isLoading, rules=${_rules.length})',
    );
    return Scaffold(
      floatingActionButton: _canManageRules
          ? FloatingActionButton.extended(
              backgroundColor: KColors.appNameColor,
              foregroundColor: Colors.white,
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EditShiftRulePage(),
                  ),
                );
                if (result == true) {
                  _loadRules();
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nouvelle règle'),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                if (_rules.isNotEmpty) _buildActionButtons(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadRules,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: _rules.length,
                      itemBuilder: (context, index) {
                        final rule = _rules[index];
                        return _buildRuleCard(rule, key: ValueKey(rule.id));
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildActionButtons() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.appNameColor.withValues(alpha: isDark ? 0.08 : 0.04),
        border: Border(
          bottom: BorderSide(
            color: KColors.appNameColor.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ShiftExceptionsPage(),
                  ),
                );
              },
              icon: const Icon(Icons.event_busy, size: 20),
              label: const Text('Gérer les exceptions'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canManageRules && !_isGenerating
                  ? _showGenerateDialog
                  : null,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.more_time, size: 20),
              label: Text(
                _isGenerating ? 'Génération...' : 'Générer les plannings',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: KColors.appNameColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rule_rounded,
            size: 56,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune règle d\'astreinte',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Créez une règle pour commencer',
            style: TextStyle(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await _repository.resetToDefaultRules(
                stationId: _currentUser!.station,
              );
              _loadRules();
            },
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Charger les règles par défaut'),
            style: FilledButton.styleFrom(backgroundColor: KColors.appNameColor),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(ShiftRule rule, {Key? key}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = rule.isActive ? KColors.appNameColor : Colors.grey;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

    final dateRange = rule.endDate != null
        ? 'Du ${_fmtDate(rule.startDate)} au ${_fmtDate(rule.endDate!)}'
        : 'Du ${_fmtDate(rule.startDate)} au ${_fmtDate(rule.startDate.add(const Duration(days: 365)))}';

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : accentColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: isDark ? 0.3 : 0.2),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon badge
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.event_repeat_rounded, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),

            // Contenu
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: rule.isActive
                          ? (isDark ? Colors.white : Colors.black87)
                          : subtitleColor,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _buildInfoRow(Icons.access_time_rounded, rule.getTimeRangeString(), subtitleColor),
                  _buildInfoRow(
                    Icons.groups_rounded,
                    rule.rotationType == ShiftRotationType.none
                        ? 'Non affectée'
                        : '${rule.teamIds.join(", ")} · ${rule.rotationType.label}',
                    subtitleColor,
                  ),
                  _buildInfoRow(Icons.today_rounded, rule.applicableDays.toDisplayString(), subtitleColor),
                  _buildInfoRow(Icons.date_range_rounded, dateRange, subtitleColor),
                  _buildInfoRow(
                    Icons.group_rounded,
                    'Max ${_stationConfig?.maxAgentsPerShift ?? 6} agents',
                    subtitleColor,
                  ),
                ],
              ),
            ),

            // Actions à droite : switch + icônes modifier/supprimer
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_canManageRules)
                  Switch(
                    value: rule.isActive,
                    onChanged: (value) async {
                      await _repository.toggleActive(
                        rule.id,
                        stationId: _currentUser!.station,
                      );
                      _loadRules();
                    },
                    activeThumbColor: KColors.appNameColor,
                    activeTrackColor: KColors.appNameColor.withValues(alpha: 0.4),
                  ),
                if (_canManageRules) ...[
                  const SizedBox(height: 4),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditShiftRulePage(rule: rule),
                        ),
                      );
                      if (result == true) _loadRules();
                    },
                    tooltip: 'Modifier',
                    color: subtitleColor,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_rounded, size: 18),
                    onPressed: () => _showDeleteDialog(rule),
                    tooltip: 'Supprimer',
                    color: Colors.red[400],
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';

  Widget _buildInfoRow(IconData icon, String text, Color? color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(ShiftRule rule) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la règle'),
        content: Text(
          'Voulez-vous vraiment supprimer la règle "${rule.name}" ?\n\nCette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              await _repository.delete(rule.id, stationId: _currentUser!.station);
              nav.pop();
              _loadRules();
              messenger.showSnackBar(
                SnackBar(content: Text('Règle "${rule.name}" supprimée')),
              );
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  void _showGenerateDialog() {
    DateTime defaultStartDate;
    DateTime defaultEndDate;

    if (_activeRules.isEmpty) {
      defaultStartDate = DateTime.now();
      defaultEndDate = DateTime.now().add(const Duration(days: 365));
    } else {
      defaultStartDate = _activeRules
          .map((r) => r.startDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);

      final endDates = _activeRules
          .map((r) => r.endDate)
          .where((d) => d != null)
          .map((d) => d!)
          .toList();

      defaultEndDate = endDates.isEmpty
          ? DateTime.now().add(const Duration(days: 365))
          : endDates.reduce((a, b) => a.isAfter(b) ? a : b);
    }

    showDialog(
      context: context,
      builder: (context) => _GenerationOptionsDialog(
        activeRulesCount: _activeRules.length,
        defaultStartDate: defaultStartDate,
        defaultEndDate: defaultEndDate,
        station: _currentUser?.station,
        onSimulate: (options, exceptions) => _simulateAndNavigate(options, exceptions),
      ),
    );
  }

  Future<void> _simulateAndNavigate(
    GenerationOptions options,
    List<ShiftException> exceptions,
  ) async {
    setState(() => _isGenerating = true);

    try {
      final impact = await _generationService.simulateGeneration(
        options,
        station: _currentUser?.station,
        exceptions: exceptions,
      );

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GenerationImpactPage(
            impact: impact,
            options: options,
            onConfirm: () => _executeGeneration(options, exceptions, impact),
          ),
        ),
      );

      // Rafraîchir la page après retour (que la génération ait eu lieu ou non)
      if (mounted) _loadRules();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la simulation : $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _executeGeneration(
    GenerationOptions options,
    List<ShiftException> exceptions,
    GenerationImpact precomputedImpact,
  ) async {
    setState(() => _isGenerating = true);

    try {
      final result = await _generationService.generatePlannings(
        options: options,
        station: _currentUser?.station,
        exceptions: exceptions,
        precomputedImpact: precomputedImpact,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.planningsGenerated} plannings générés · '
            '${result.planningsDeleted} supprimés',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }
}

/// Dialogue de configuration de la génération — remplace l'ancien _GeneratePlanningsDialog
class _GenerationOptionsDialog extends StatefulWidget {
  final int activeRulesCount;
  final DateTime defaultStartDate;
  final DateTime defaultEndDate;
  final String? station;
  final Future<void> Function(GenerationOptions options, List<ShiftException> exceptions) onSimulate;

  const _GenerationOptionsDialog({
    required this.activeRulesCount,
    required this.defaultStartDate,
    required this.defaultEndDate,
    required this.station,
    required this.onSimulate,
  });

  @override
  State<_GenerationOptionsDialog> createState() => _GenerationOptionsDialogState();
}

class _GenerationOptionsDialogState extends State<_GenerationOptionsDialog> {
  late DateTime _startDate;
  late DateTime _endDate;
  GenerationMode _mode = GenerationMode.total;
  bool _generateFromRules = true;
  bool _generateFromExceptions = true;
  bool _preserveReplacements = true;
  List<Team> _availableTeams = [];
  Set<String> _selectedTeams = {};
  bool _filterByTeam = false;
  bool _loadingTeams = false;
  final _exceptionRepository = ShiftExceptionRepository();
  final _teamRepository = TeamRepository();

  @override
  void initState() {
    super.initState();
    _startDate = widget.defaultStartDate;
    _endDate = widget.defaultEndDate;
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() => _loadingTeams = true);
    try {
      final teams = widget.station != null
          ? await _teamRepository.getByStation(widget.station!)
          : await _teamRepository.getAll();
      if (mounted) {
        setState(() {
          _availableTeams = teams;
          _selectedTeams = teams.map((t) => t.id).toSet();
          _loadingTeams = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTeams = false);
    }
  }

  Future<void> _onSimulate() async {
    Navigator.pop(context);

    final allExceptions = await _exceptionRepository.getAll(stationId: widget.station);
    // _endDate est minuit du jour sélectionné — on prend le lendemain minuit
    // pour inclure toutes les exceptions qui démarrent dans la journée de fin.
    final endDateInclusive = _endDate.add(const Duration(days: 1));
    final relevantExceptions = allExceptions
        .where((e) =>
            e.startDateTime.isBefore(endDateInclusive) && e.endDateTime.isAfter(_startDate))
        .toList();

    final options = GenerationOptions(
      startDate: _startDate,
      endDate: _endDate,
      mode: _mode,
      generateFromRules: _generateFromRules,
      generateFromExceptions: _generateFromExceptions,
      teamFilter: _filterByTeam ? _selectedTeams.toList() : null,
      preserveReplacements: _preserveReplacements,
    );

    await widget.onSimulate(options, relevantExceptions);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.more_time, color: KColors.appNameColor),
          SizedBox(width: 8),
          Text('Générer les plannings'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel('PÉRIODE'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _startDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) {
                    setState(() {
                      _startDate = date;
                      if (_endDate.isBefore(_startDate)) {
                        _endDate = _startDate.add(const Duration(days: 365));
                      }
                    });
                  }
                },
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  'Début : ${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _endDate,
                    firstDate: _startDate,
                    lastDate: DateTime(2030),
                  );
                  if (date != null) setState(() => _endDate = date);
                },
                icon: const Icon(Icons.event, size: 16),
                label: Text(
                  'Fin : ${_endDate.day.toString().padLeft(2, '0')}/${_endDate.month.toString().padLeft(2, '0')}/${_endDate.year}',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
              const SizedBox(height: 16),

              _SectionLabel('MODE'),
              const SizedBox(height: 4),
              _RadioOption<GenerationMode>(
                value: GenerationMode.total,
                groupValue: _mode,
                label: 'Total',
                subtitle: 'Supprime et régénère tous les plannings de la période',
                onChanged: (v) => setState(() => _mode = v!),
              ),
              _RadioOption<GenerationMode>(
                value: GenerationMode.differential,
                groupValue: _mode,
                label: 'Différentiel',
                subtitle: 'Régénère uniquement les plannings dont les règles ont changé',
                onChanged: (v) => setState(() => _mode = v!),
              ),
              const SizedBox(height: 12),

              _SectionLabel('CONTENU À GÉNÉRER'),
              const SizedBox(height: 4),
              _CheckOption(
                value: _generateFromRules,
                label: 'Plannings par règles',
                subtitle: '${widget.activeRulesCount} règle(s) active(s)',
                onChanged: (v) => setState(() => _generateFromRules = v ?? true),
              ),
              _CheckOption(
                value: _generateFromExceptions,
                label: 'Plannings par exceptions',
                onChanged: (v) => setState(() => _generateFromExceptions = v ?? true),
              ),
              const SizedBox(height: 12),

              _SectionLabel('ÉQUIPES'),
              const SizedBox(height: 4),
              _CheckOption(
                value: _filterByTeam,
                label: 'Filtrer par équipe',
                subtitle: 'Par défaut : toutes les équipes',
                onChanged: (v) => setState(() => _filterByTeam = v ?? false),
              ),
              if (_filterByTeam) ...[
                const SizedBox(height: 6),
                if (_loadingTeams)
                  const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _availableTeams.map((team) {
                      final selected = _selectedTeams.contains(team.id);
                      return FilterChip(
                        label: Text(team.name),
                        selected: selected,
                        selectedColor: KColors.appNameColor.withValues(alpha: 0.2),
                        checkmarkColor: KColors.appNameColor,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selectedTeams.add(team.id);
                          } else {
                            _selectedTeams.remove(team.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
              ],
              const SizedBox(height: 12),

              _SectionLabel('REMPLACEMENTS EXISTANTS'),
              const SizedBox(height: 4),
              _RadioOption<bool>(
                value: true,
                groupValue: _preserveReplacements,
                label: 'Conserver (recommandé)',
                subtitle: 'Ajuste les remplacements selon le chevauchement',
                onChanged: (v) => setState(() => _preserveReplacements = v!),
              ),
              _RadioOption<bool>(
                value: false,
                groupValue: _preserveReplacements,
                label: 'Écraser',
                subtitle: 'Supprime tous les remplacements sur les plannings régénérés',
                onChanged: (v) => setState(() => _preserveReplacements = v!),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _onSimulate,
          icon: const Icon(Icons.preview, size: 16),
          label: const Text('Simuler'),
          style: FilledButton.styleFrom(backgroundColor: KColors.appNameColor),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: Colors.grey.shade500,
      ),
    );
  }
}

class _RadioOption<T> extends StatelessWidget {
  final T value;
  final T groupValue;
  final String label;
  final String? subtitle;
  final ValueChanged<T?> onChanged;

  const _RadioOption({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          Radio<T>(
            value: value,
            groupValue: groupValue,
            onChanged: onChanged,
            activeColor: KColors.appNameColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckOption extends StatelessWidget {
  final bool value;
  final String label;
  final String? subtitle;
  final ValueChanged<bool?> onChanged;

  const _CheckOption({
    required this.value,
    required this.label,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: KColors.appNameColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
