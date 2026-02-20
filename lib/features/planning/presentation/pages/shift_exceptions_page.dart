import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/shift_exception_model.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/team_model.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/repositories/shift_exception_repository.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ShiftExceptionsPage extends StatefulWidget {
  const ShiftExceptionsPage({super.key});

  @override
  State<ShiftExceptionsPage> createState() => _ShiftExceptionsPageState();
}

class _ShiftExceptionsPageState extends State<ShiftExceptionsPage> {
  final _repository = ShiftExceptionRepository();
  late int _selectedYear;
  List<ShiftException> _exceptions = [];
  bool _isLoading = false;
  bool _canManage = false;
  String? _currentUserStation;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _loadExceptions();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final user = await UserStorageHelper.loadUser();
    if (mounted) {
      setState(() {
        _canManage = user != null && (user.admin || user.status == KConstants.statusLeader);
        _currentUserStation = user?.station;
      });
    }
  }

  Future<void> _loadExceptions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final exceptions = await _repository.getByYear(_selectedYear, stationId: _currentUserStation);
      if (!mounted) return;
      setState(() {
        _exceptions = exceptions;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading exceptions: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteException(ShiftException exception) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l\'exception'),
        content: Text('Supprimer "${exception.reason}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _repository.delete(exception.id, stationId: _currentUserStation);
      _loadExceptions();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Exception supprimée')));
      }
    }
  }

  Future<void> _deleteAllForYear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer toutes les exceptions'),
        content: Text(
          'Supprimer toutes les exceptions de l\'année $_selectedYear ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _repository.deleteByYear(_selectedYear, stationId: _currentUserStation);
      _loadExceptions();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Exceptions supprimées')));
      }
    }
  }

  void _addException() {
    showDialog(
      context: context,
      builder: (context) => _ExceptionDialog(
        repository: _repository,
        initialYear: _selectedYear,
        stationId: _currentUserStation,
        onSaved: _loadExceptions,
      ),
    );
  }

  void _editException(ShiftException exception) {
    showDialog(
      context: context,
      builder: (context) => _ExceptionDialog(
        repository: _repository,
        initialYear: _selectedYear,
        exception: exception,
        stationId: _currentUserStation,
        onSaved: _loadExceptions,
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${(dt.year % 100).toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildExRow(IconData icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Dates exceptionnelles'),
      body: Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Column(
            children: [
              // Sélecteur d'année
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  color: KColors.appNameColor.withValues(alpha: isDark ? 0.1 : 0.05),
                  border: Border(
                    bottom: BorderSide(
                      color: KColors.appNameColor.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() => _selectedYear--);
                        _loadExceptions();
                      },
                      icon: const Icon(Icons.chevron_left_rounded),
                      color: KColors.appNameColor,
                    ),
                    Expanded(
                      child: Text(
                        '$_selectedYear',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: KColors.appNameColor,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() => _selectedYear++);
                        _loadExceptions();
                      },
                      icon: const Icon(Icons.chevron_right_rounded),
                      color: KColors.appNameColor,
                    ),
                  ],
                ),
              ),

              // Bouton de suppression globale
              if (_exceptions.isNotEmpty && _canManage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _deleteAllForYear,
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                      label: const Text('Supprimer toutes les exceptions'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ),

              // Liste des exceptions
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _exceptions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_busy_rounded,
                              size: 56,
                              color: isDark ? Colors.grey[600] : Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Aucune exception pour $_selectedYear',
                              style: TextStyle(
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _exceptions.length,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemBuilder: (context, index) {
                          final exception = _exceptions[index];
                          final isCancelled = exception.teamId == null;
                          final accentColor = isCancelled ? Colors.red : KColors.appNameColor;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : accentColor.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: accentColor.withValues(
                                  alpha: isDark ? 0.3 : 0.2,
                                ),
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
                                    child: Icon(
                                      isCancelled
                                          ? Icons.cancel_rounded
                                          : Icons.swap_horiz_rounded,
                                      color: accentColor,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          exception.reason,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        _buildExRow(
                                          Icons.play_arrow_rounded,
                                          _formatDateTime(exception.startDateTime),
                                          isDark,
                                        ),
                                        _buildExRow(
                                          Icons.stop_rounded,
                                          _formatDateTime(exception.endDateTime),
                                          isDark,
                                        ),
                                        if (isCancelled)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'Astreinte annulée',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          )
                                        else ...[
                                          _buildExRow(
                                            Icons.group_rounded,
                                            'Équipe ${exception.teamId} · max ${exception.maxAgents} agents',
                                            isDark,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  // Actions
                                  if (_canManage)
                                    Column(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_rounded, size: 18),
                                          onPressed: () => _editException(exception),
                                          tooltip: 'Modifier',
                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                        const SizedBox(height: 8),
                                        IconButton(
                                          icon: const Icon(Icons.delete_rounded, size: 18),
                                          onPressed: () => _deleteException(exception),
                                          tooltip: 'Supprimer',
                                          color: Colors.red[400],
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              backgroundColor: KColors.appNameColor,
              foregroundColor: Colors.white,
              onPressed: _addException,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter'),
            )
          : null,
    );
  }
}

class _ExceptionDialog extends StatefulWidget {
  final ShiftExceptionRepository repository;
  final int initialYear;
  final ShiftException? exception;
  final String? stationId;
  final VoidCallback onSaved;

  const _ExceptionDialog({
    required this.repository,
    required this.initialYear,
    this.exception,
    this.stationId,
    required this.onSaved,
  });

  @override
  State<_ExceptionDialog> createState() => _ExceptionDialogState();
}

class _ExceptionDialogState extends State<_ExceptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _teamRepository = TeamRepository();

  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  String? _teamId;
  int _maxAgents = 6;
  bool _isLoadingStation = true;
  List<Team> _availableTeams = [];
  bool _isLoadingTeams = true;

  bool get _isEditing => widget.exception != null;

  @override
  void initState() {
    super.initState();
    _loadStationConfig();
    _loadTeams();
    if (_isEditing) {
      final ex = widget.exception!;
      _reasonController.text = ex.reason;
      _maxAgents = ex.maxAgents;
      _startDate = ex.startDateTime;
      _startTime = TimeOfDay.fromDateTime(ex.startDateTime);
      _endDate = ex.endDateTime;
      _endTime = TimeOfDay.fromDateTime(ex.endDateTime);
      _teamId = ex.teamId;
    } else {
      _startDate = DateTime(widget.initialYear, 1, 1);
      _startTime = const TimeOfDay(hour: 19, minute: 0);
      _endDate = DateTime(widget.initialYear, 1, 2);
      _endTime = const TimeOfDay(hour: 6, minute: 0);
      _teamId = null; // Sera défini après le chargement des équipes
    }
  }

  Future<void> _loadTeams() async {
    try {
      final user = await UserStorageHelper.loadUser();
      if (user == null || !mounted) {
        setState(() {
          _availableTeams = [];
          _isLoadingTeams = false;
        });
        return;
      }

      final stationTeams = await _teamRepository.getByStation(user.station);
      stationTeams.sort((a, b) => a.order.compareTo(b.order));

      if (mounted) {
        setState(() {
          _availableTeams = stationTeams;
          _isLoadingTeams = false;

          // Si on est en création et qu'il n'y a pas d'équipe sélectionnée,
          // sélectionner la première équipe disponible
          if (!_isEditing && _teamId == null && stationTeams.isNotEmpty) {
            _teamId = stationTeams.first.id;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading teams: $e');
      if (mounted) {
        setState(() {
          _availableTeams = [];
          _isLoadingTeams = false;
        });
      }
    }
  }

  Future<void> _loadStationConfig() async {
    try {
      final user = await UserStorageHelper.loadUser();
      if (user == null || !mounted) return;

      final stationDoc = await FirebaseFirestore.instance
          .collection('stations')
          .doc(user.station)
          .get();

      if (!mounted) return;

      if (stationDoc.exists) {
        final station = Station.fromJson({
          'id': stationDoc.id,
          ...stationDoc.data()!,
        });
        setState(() {
          _maxAgents = station.maxAgentsPerShift;
          _isLoadingStation = false;
        });
      } else {
        setState(() => _isLoadingStation = false);
      }
    } catch (e) {
      debugPrint('Error loading station config: $e');
      if (mounted) {
        setState(() => _isLoadingStation = false);
      }
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(widget.initialYear - 5),
      lastDate: DateTime(widget.initialYear + 5),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        // Ajuster la date de fin si elle devient avant la date de début
        if (_endDate.isBefore(picked)) {
          _endDate = picked.add(const Duration(days: 1));
        }
      });
    }
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime(widget.initialYear + 5),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final startDateTime = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    final endDateTime = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    if (endDateTime.isBefore(startDateTime) ||
        endDateTime.isAtSameMomentAs(startDateTime)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La date de fin doit être après la date de début'),
          ),
        );
      }
      return;
    }

    try {
      final exception = ShiftException(
        id: _isEditing
            ? widget.exception!.id
            : '${DateTime.now().millisecondsSinceEpoch}',
        startDateTime: startDateTime,
        endDateTime: endDateTime,
        teamId: _teamId,
        reason: _reasonController.text,
        maxAgents: _maxAgents,
      );

      await widget.repository.upsert(exception, stationId: widget.stationId);

      if (mounted) {
        widget.onSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Exception modifiée' : 'Exception ajoutée',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditing ? 'Modifier l\'exception' : 'Ajouter une exception',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Motif *',
                  hintText: 'Ex: Noël, Formation...',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez saisir un motif';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Text('Début', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectStartDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectStartTime,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(
                        '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Fin', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectEndDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        '${_endDate.day.toString().padLeft(2, '0')}/${_endDate.month.toString().padLeft(2, '0')}/${_endDate.year}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectEndTime,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(
                        '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_isLoadingTeams)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                DropdownButtonFormField<String?>(
                  value: _teamId,
                  decoration: const InputDecoration(
                    labelText: 'Équipe de garde *',
                    helperText: 'Sélectionner "Aucune" annule l\'astreinte',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Aucune')),
                    ..._availableTeams.map(
                      (team) => DropdownMenuItem(
                        value: team.id,
                        child: Text(team.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _teamId = value),
                ),
              const SizedBox(height: 16),
              if (_isLoadingStation)
                const Center(child: CircularProgressIndicator())
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: KColors.appNameColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: KColors.appNameColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.group_rounded,
                        size: 20,
                        color: KColors.appNameColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Maximum d\'agents',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Défini dans Administration',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$_maxAgents agents',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: KColors.appNameColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEditing ? 'Modifier' : 'Ajouter'),
        ),
      ],
    );
  }
}
