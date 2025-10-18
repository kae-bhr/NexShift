import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/shift_rule_model.dart';
import 'package:nexshift_app/core/repositories/shift_rule_repository.dart';
import 'package:nexshift_app/core/repositories/shift_exception_repository.dart';
import 'package:nexshift_app/core/services/planning_generation_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/features/planning/presentation/pages/edit_shift_rule_page.dart';
import 'package:nexshift_app/features/planning/presentation/pages/calendar_preview_page.dart';
import 'package:nexshift_app/features/planning/presentation/pages/shift_exceptions_page.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';

class PlanningRulesListPage extends StatefulWidget {
  const PlanningRulesListPage({super.key});

  @override
  State<PlanningRulesListPage> createState() => _PlanningRulesListPageState();
}

class _PlanningRulesListPageState extends State<PlanningRulesListPage> {
  final _repository = ShiftRuleRepository();
  final _generationService = PlanningGenerationService();
  final _exceptionRepository = ShiftExceptionRepository();
  List<ShiftRule> _rules = [];
  List<ShiftRule> _activeRules = [];
  bool _isLoading = true;
  bool _isGenerating = false;
  User? _currentUser;
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

  Future<void> _loadRules() async {
    if (!mounted) return;
    final stopwatch = Stopwatch()..start();
    setState(() => _isLoading = true);
    try {
      final rules = await _repository.getAll();
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
              backgroundColor: Theme.of(context).colorScheme.primary,
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
              icon: const Icon(Icons.add),
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
                      padding: const EdgeInsets.all(16),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.appNameColor.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CalendarPreviewPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.calendar_month, size: 20),
                  label: const Text('Aperçu'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
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
                  label: const Text('Exceptions'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rule, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Aucune règle d\'astreinte',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Créez une règle pour commencer',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await _repository.resetToDefaultRules();
              _loadRules();
            },
            icon: const Icon(Icons.restore),
            label: const Text('Charger les règles par défaut'),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(ShiftRule rule, {Key? key}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          SwitchListTile(
            value: rule.isActive,
            onChanged: _canManageRules
                ? (value) async {
                    await _repository.toggleActive(rule.id);
                    _loadRules();
                  }
                : null,
            activeColor: KColors.appNameColor,
            title: Text(
              rule.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: rule.isActive ? null : Colors.grey,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        rule.getTimeRangeString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.groups, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        rule.rotationType == ShiftRotationType.none
                            ? 'Non affectée'
                            : '${rule.teamIds.join(", ")} - ${rule.rotationType.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.today, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        rule.applicableDays.toDisplayString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.date_range, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        rule.endDate != null
                            ? 'Du ${rule.startDate.day.toString().padLeft(2, '0')}/${rule.startDate.month.toString().padLeft(2, '0')}/${(rule.startDate.year % 100).toString().padLeft(2, '0')}'
                                  ' au ${rule.endDate!.day.toString().padLeft(2, '0')}/${rule.endDate!.month.toString().padLeft(2, '0')}/${(rule.endDate!.year % 100).toString().padLeft(2, '0')}'
                            : 'Du ${rule.startDate.day.toString().padLeft(2, '0')}/${rule.startDate.month.toString().padLeft(2, '0')}/${(rule.startDate.year % 100).toString().padLeft(2, '0')}'
                                  ' au ${rule.startDate.add(const Duration(days: 365)).day.toString().padLeft(2, '0')}/${rule.startDate.add(const Duration(days: 365)).month.toString().padLeft(2, '0')}/${(rule.startDate.add(const Duration(days: 365)).year % 100).toString().padLeft(2, '0')}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.group, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Max ${rule.maxAgents} agents',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: rule.isActive
                    ? colorScheme.primary.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.event_repeat,
                color: rule.isActive ? colorScheme.primary : Colors.grey,
              ),
            ),
          ),
          const Divider(height: 1),
          ButtonBar(
            children: [
              TextButton.icon(
                onPressed: _canManageRules
                    ? () async {
                        debugPrint(
                          'PlanningRulesListPage: Opening edit page for rule ${rule.id} "${rule.name}"',
                        );
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditShiftRulePage(rule: rule),
                          ),
                        );
                        debugPrint(
                          'PlanningRulesListPage: Edit page returned: $result',
                        );
                        if (result == true) {
                          _loadRules();
                        }
                      }
                    : null,
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Modifier'),
              ),
              TextButton.icon(
                onPressed: _canManageRules
                    ? () => _showDeleteDialog(rule)
                    : null,
                icon: Icon(
                  Icons.delete,
                  size: 18,
                  color: _canManageRules ? Colors.red : Colors.grey,
                ),
                label: Text(
                  'Supprimer',
                  style: TextStyle(
                    color: _canManageRules ? Colors.red : Colors.grey,
                  ),
                ),
              ),
            ],
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
              await _repository.delete(rule.id);
              Navigator.pop(context);
              _loadRules();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Règle "${rule.name}" supprimée')),
                );
              }
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  void _showGenerateDialog() {
    // Utiliser les règles actives pré-calculées
    DateTime defaultStartDate;
    DateTime defaultEndDate;

    if (_activeRules.isEmpty) {
      // Aucune règle : date du jour et +1 an
      defaultStartDate = DateTime.now();
      defaultEndDate = DateTime.now().add(const Duration(days: 365));
    } else {
      // Trouver la date de début la plus ancienne et la date de fin la plus éloignée
      defaultStartDate = _activeRules
          .map((r) => r.startDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);

      // Pour la date de fin, prendre la plus éloignée (en gérant les null)
      final endDates = _activeRules
          .map((r) => r.endDate)
          .where((d) => d != null)
          .map((d) => d!)
          .toList();

      if (endDates.isEmpty) {
        // Aucune date de fin définie : +1 an à partir de maintenant
        defaultEndDate = DateTime.now().add(const Duration(days: 365));
      } else {
        defaultEndDate = endDates.reduce((a, b) => a.isAfter(b) ? a : b);
      }
    }

    showDialog(
      context: context,
      builder: (context) => _GeneratePlanningsDialog(
        activeRulesCount: _activeRules.length,
        defaultStartDate: defaultStartDate,
        defaultEndDate: defaultEndDate,
        onGenerate: (startDate, endDate) async {
          await _generatePlannings(startDate, endDate);
        },
      ),
    );
  }

  Future<void> _generatePlannings(DateTime startDate, DateTime endDate) async {
    setState(() => _isGenerating = true);

    try {
      // Charger les exceptions pour la période
      final allExceptions = await _exceptionRepository.getAll();
      debugPrint('📅 Total exceptions loaded: ${allExceptions.length}');

      final relevantExceptions = allExceptions.where((e) {
        final isRelevant = e.startDateTime.isBefore(endDate) &&
            e.endDateTime.isAfter(startDate);
        if (isRelevant) {
          debugPrint('  ✓ Exception: ${e.reason} (${e.startDateTime} - ${e.endDateTime})');
        }
        return isRelevant;
      }).toList();

      debugPrint('📅 Relevant exceptions for period $startDate - $endDate: ${relevantExceptions.length}');

      final duration = endDate.difference(startDate);
      final result = await _generationService.generatePlannings(
        fromDate: startDate,
        duration: duration,
        exceptions: relevantExceptions,
      );

      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.planningsGenerated} plannings générés\n'
              '${result.planningsDeleted} plannings remplacés',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Voir',
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CalendarPreviewPage(),
                  ),
                );
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }
}

/// Dialogue pour configurer la génération des plannings
class _GeneratePlanningsDialog extends StatefulWidget {
  final int activeRulesCount;
  final DateTime defaultStartDate;
  final DateTime defaultEndDate;
  final Function(DateTime startDate, DateTime endDate) onGenerate;

  const _GeneratePlanningsDialog({
    required this.activeRulesCount,
    required this.defaultStartDate,
    required this.defaultEndDate,
    required this.onGenerate,
  });

  @override
  State<_GeneratePlanningsDialog> createState() =>
      _GeneratePlanningsDialogState();
}

class _GeneratePlanningsDialogState extends State<_GeneratePlanningsDialog> {
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = widget.defaultStartDate;
    _endDate = widget.defaultEndDate;
  }

  @override
  Widget build(BuildContext context) {
    final duration = _endDate.difference(_startDate).inDays;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.more_time, color: KColors.appNameColor),
          SizedBox(width: 8),
          Text('Générer les plannings'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Période de génération',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),

            // Date de début
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
                    // Ajuster la date de fin si elle est avant la nouvelle date de début
                    if (_endDate.isBefore(_startDate)) {
                      _endDate = _startDate.add(const Duration(days: 365));
                    }
                  });
                }
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(
                'Début: ${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),

            // Date de fin
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _endDate,
                  firstDate: _startDate,
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  setState(() => _endDate = date);
                }
              },
              icon: const Icon(Icons.event),
              label: Text(
                'Fin: ${_endDate.day.toString().padLeft(2, '0')}/${_endDate.month.toString().padLeft(2, '0')}/${_endDate.year}',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 16),

            // Résumé
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KColors.appNameColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: KColors.appNameColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cette action va :',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('• Supprimer tous les plannings entre ces dates'),
                  if (widget.activeRulesCount > 0) ...[
                    Text('• Générer $duration jours de plannings'),
                    Text(
                      '• Utiliser ${widget.activeRulesCount} règle(s) active(s)',
                    ),
                  ] else
                    const Text(
                      '• Aucune nouvelle planification (aucune règle active)',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Avertissement
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.activeRulesCount > 0
                          ? 'Les plannings existants seront remplacés. Cette action est irréversible.'
                          : 'Tous les plannings de cette période seront supprimés. Cette action est irréversible.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onGenerate(_startDate, _endDate);
          },
          child: const Text('Générer'),
        ),
      ],
    );
  }
}
