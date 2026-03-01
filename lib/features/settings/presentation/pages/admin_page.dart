import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/position_model.dart';
import 'package:nexshift_app/core/data/models/membership_request_model.dart';
import 'package:nexshift_app/core/data/models/on_call_level_model.dart';
import 'package:nexshift_app/core/repositories/position_repository.dart';
import 'package:nexshift_app/core/repositories/station_repository.dart';
import 'package:nexshift_app/core/repositories/on_call_level_repository.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/utils/station_name_cache.dart';
import 'package:nexshift_app/core/services/cloud_functions_service.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final PositionRepository _positionRepository = PositionRepository();
  final StationRepository _stationRepository = StationRepository();
  final CloudFunctionsService _cloudFunctionsService = CloudFunctionsService();
  final OnCallLevelRepository _onCallLevelRepository = OnCallLevelRepository();

  Station? _currentStation;
  bool _isLoading = true;
  int _pendingRequestsCount = 0;
  List<OnCallLevel> _onCallLevels = [];
  List<Position> _positions = [];

  @override
  void initState() {
    super.initState();
    _loadStationConfig();
  }

  Future<void> _loadStationConfig() async {
    final user = userNotifier.value;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final station = await _stationRepository.getById(user.station);

      if (station != null) {
        setState(() {
          _currentStation = station;
        });
        // Charger les niveaux d'astreinte séparément pour ne pas bloquer la station
        try {
          final levels = await _onCallLevelRepository.getAll(user.station);
          if (mounted) setState(() { _onCallLevels = levels; });
        } catch (e) {
          debugPrint('⚠️ [ADMIN] Error loading on-call levels: $e');
        }
        try {
          final positions = await _positionRepository
              .getPositionsByStation(user.station)
              .first;
          if (mounted) setState(() { _positions = positions; });
        } catch (e) {
          debugPrint('⚠️ [ADMIN] Error loading positions: $e');
        }
      } else {
        // Charger le nom de la station depuis le cache
        final sdisId = SDISContext().currentSDISId;
        final stationName = sdisId != null
            ? await StationNameCache().getStationName(sdisId, user.station)
            : user.station;

        // Créer la station si elle n'existe pas
        _currentStation = Station(id: user.station, name: stationName);
        await _saveStationConfig();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur de chargement: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveStationConfig() async {
    if (_currentStation == null) return;

    try {
      // Nettoyer les skillWeights pour supprimer les clés vides
      final cleanedWeights = Map<String, double>.from(
        _currentStation!.skillWeights,
      );
      cleanedWeights.removeWhere((key, value) => key.isEmpty);

      // Créer une station avec les poids nettoyés
      final cleanedStation = _currentStation!.copyWith(
        skillWeights: cleanedWeights,
      );

      await _stationRepository.upsert(cleanedStation);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration sauvegardée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur de sauvegarde: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: "Administration",
        bottomColor: KColors.appNameColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentStation == null
          ? const Center(child: Text('Erreur de chargement de la caserne'))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildSectionHeader(context, 'Configuration de la caserne'),
                _buildStationConfigSection(context),
                const SizedBox(height: 24),
                _buildSectionHeader(context, 'Demandes d\'adhésion'),
                _buildMembershipRequestsSection(context),
                const SizedBox(height: 24),
                _buildSectionHeader(context, 'Niveaux d\'astreinte'),
                _buildOnCallLevelsSection(context),
                const SizedBox(height: 24),
                _buildSectionHeader(context, 'Mode de remplacement'),
                _buildReplacementModeSection(context),
                const SizedBox(height: 24),
                _buildSectionHeader(context, 'Pondération des compétences'),
                _buildSkillWeightsSection(context),
                const SizedBox(height: 24),
                _buildSectionHeader(context, 'Gestion des postes'),
                _buildPositionsSection(context),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildStationConfigSection(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.groups),
            title: const Text('Nombre max d\'agents par garde'),
            subtitle: Text('${_currentStation!.maxAgentsPerShift} agents'),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _editMaxAgentsPerShift(context),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('Délai entre les vagues'),
            subtitle: Text(
              '${_currentStation!.notificationWaveDelayMinutes} minutes',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _editWaveDelay(context),
            ),
          ),
          const Divider(height: 1),
          // Section Pause nocturne
          SwitchListTile(
            secondary: const Icon(Icons.nightlight_round),
            title: const Text('Pause nocturne des notifications'),
            subtitle: Text(
              _currentStation!.nightPauseEnabled
                  ? 'De ${_currentStation!.nightPauseStart} à ${_currentStation!.nightPauseEnd}'
                  : 'Désactivée',
            ),
            value: _currentStation!.nightPauseEnabled,
            activeThumbColor: KColors.appNameColor,
            activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
            onChanged: (value) {
              setState(() {
                _currentStation = _currentStation!.copyWith(
                  nightPauseEnabled: value,
                );
              });
              _saveStationConfig();
            },
          ),
          // Afficher les heures uniquement si activé
          if (_currentStation!.nightPauseEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTimePickerTile(
                      context,
                      label: 'Début',
                      time: _currentStation!.nightPauseStart,
                      icon: Icons.bedtime,
                      onTap: () => _editNightPauseTime(context, isStart: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTimePickerTile(
                      context,
                      label: 'Fin',
                      time: _currentStation!.nightPauseEnd,
                      icon: Icons.wb_sunny,
                      onTap: () => _editNightPauseTime(context, isStart: false),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildTimePickerTile(
    BuildContext context, {
    required String label,
    required String time,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? Colors.grey[600]! : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: KColors.appNameColor),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNightPauseTime(
    BuildContext context, {
    required bool isStart,
  }) async {
    final currentTime = isStart
        ? _currentStation!.nightPauseStart
        : _currentStation!.nightPauseEnd;
    final parts = currentTime.split(':');
    final initialTime = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? (isStart ? 23 : 6),
      minute: int.tryParse(parts[1]) ?? 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final timeString =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) {
          _currentStation = _currentStation!.copyWith(
            nightPauseStart: timeString,
          );
        } else {
          _currentStation = _currentStation!.copyWith(
            nightPauseEnd: timeString,
          );
        }
      });
      await _saveStationConfig();
    }
  }

  Widget _buildMembershipRequestsSection(BuildContext context) {
    final user = userNotifier.value;
    if (user == null) return const SizedBox.shrink();

    return FutureBuilder<int>(
      future: _cloudFunctionsService.getPendingMembershipRequestsCount(
        stationId: user.station,
      ),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return Card(
          child: ListTile(
            leading: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: const Icon(Icons.person_add),
            ),
            title: const Text('Demandes en attente'),
            subtitle: Text(
              count == 0
                  ? 'Aucune demande en attente'
                  : '$count demande${count > 1 ? 's' : ''} en attente',
            ),
            trailing: count > 0
                ? FilledButton.icon(
                    onPressed: () => _showMembershipRequestsDialog(context),
                    icon: const Icon(Icons.visibility),
                    label: const Text('Voir'),
                  )
                : null,
            onTap: count > 0
                ? () => _showMembershipRequestsDialog(context)
                : null,
          ),
        );
      },
    );
  }

  Future<void> _showMembershipRequestsDialog(BuildContext context) async {
    final user = userNotifier.value;
    if (user == null) return;

    final requests = await _cloudFunctionsService.getMembershipRequests(
      stationId: user.station,
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => _MembershipRequestsDialog(
        requests: requests,
        stationId: user.station,
        onRequestHandled: () {
          setState(() {
            // Rafraîchir le compteur
          });
        },
      ),
    );
  }

  // ─── Niveaux d'astreinte ───

  Widget _buildOnCallLevelsSection(BuildContext context) {
    final user = userNotifier.value;
    if (user == null) return const SizedBox.shrink();

    return Card(
      child: Column(
        children: [
          // Liste des niveaux existants
          if (_onCallLevels.isEmpty)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Aucun niveau configuré'),
              subtitle: Text(
                'Ajoutez des niveaux d\'astreinte pour classer les agents par type de présence',
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _onCallLevels.length,
              onReorder: (oldIndex, newIndex) =>
                  _reorderLevels(oldIndex, newIndex, user.station),
              itemBuilder: (context, index) {
                final level = _onCallLevels[index];
                return ListTile(
                  key: ValueKey(level.id),
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: level.color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    level.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () =>
                            _showEditLevelDialog(context, user.station, level),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 20,
                          color: Colors.red,
                        ),
                        onPressed: () =>
                            _deleteLevel(context, user.station, level),
                      ),
                    ],
                  ),
                );
              },
            ),
          const Divider(height: 1),
          // Bouton ajouter
          ListTile(
            leading: Icon(Icons.add_circle_outline, color: KColors.appNameColor),
            title: Text(
              'Ajouter un niveau',
              style: TextStyle(
                color: KColors.appNameColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () => _showEditLevelDialog(context, user.station, null),
          ),
          // Règles de positionnement
          if (_onCallLevels.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Règles de positionnement',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Agent de garde (équipe propre)
                  _buildLevelDropdown(
                    label: 'Agent de garde (équipe propre)',
                    value: _currentStation!.defaultOnCallLevelId,
                    onChanged: (value) {
                      setState(() {
                        _currentStation = _currentStation!.copyWith(
                          defaultOnCallLevelId: value,
                        );
                      });
                      _saveStationConfig();
                    },
                  ),
                  const SizedBox(height: 16),
                  // Distinction par durée
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Distinguer par durée de remplacement',
                      style: TextStyle(fontSize: 14),
                    ),
                    value: _currentStation!.enableReplacementDurationThreshold,
                    activeThumbColor: KColors.appNameColor,
                    onChanged: (value) {
                      setState(() {
                        _currentStation = _currentStation!.copyWith(
                          enableReplacementDurationThreshold: value,
                        );
                      });
                      _saveStationConfig();
                    },
                  ),
                  if (_currentStation!.enableReplacementDurationThreshold) ...[
                    // Seuil en heures
                    Row(
                      children: [
                        const Text('Seuil : ', style: TextStyle(fontSize: 14)),
                        SizedBox(
                          width: 60,
                          child: TextFormField(
                            initialValue: _currentStation!
                                .replacementDurationThresholdHours
                                .toString(),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            onFieldSubmitted: (value) {
                              final hours = int.tryParse(value);
                              if (hours != null && hours > 0) {
                                setState(() {
                                  _currentStation = _currentStation!.copyWith(
                                    replacementDurationThresholdHours: hours,
                                  );
                                });
                                _saveStationConfig();
                              }
                            },
                          ),
                        ),
                        const Text(' heures', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildLevelDropdown(
                      label: 'Durée < seuil',
                      value: _currentStation!.shortReplacementLevelId,
                      onChanged: (value) {
                        setState(() {
                          _currentStation = _currentStation!.copyWith(
                            shortReplacementLevelId: value,
                          );
                        });
                        _saveStationConfig();
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildLevelDropdown(
                      label: 'Durée ≥ seuil',
                      value: _currentStation!.longReplacementLevelId,
                      onChanged: (value) {
                        setState(() {
                          _currentStation = _currentStation!.copyWith(
                            longReplacementLevelId: value,
                          );
                        });
                        _saveStationConfig();
                      },
                    ),
                  ] else ...[
                    _buildLevelDropdown(
                      label: 'Niveau remplaçant',
                      value: _currentStation!.replacementOnCallLevelId,
                      onChanged: (value) {
                        setState(() {
                          _currentStation = _currentStation!.copyWith(
                            replacementOnCallLevelId: value,
                          );
                        });
                        _saveStationConfig();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLevelDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: _onCallLevels.any((l) => l.id == value) ? value : null,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(),
            ),
            items: _onCallLevels.map((level) {
              return DropdownMenuItem(
                value: level.id,
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: level.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        level.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  void _reorderLevels(int oldIndex, int newIndex, String stationId) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = _onCallLevels.removeAt(oldIndex);
      _onCallLevels.insert(newIndex, item);
      // Mettre à jour les ordres
      for (int i = 0; i < _onCallLevels.length; i++) {
        _onCallLevels[i] = _onCallLevels[i].copyWith(order: i);
      }
    });
    _onCallLevelRepository.reorder(_onCallLevels, stationId);
  }

  Future<void> _showEditLevelDialog(
    BuildContext context,
    String stationId,
    OnCallLevel? existing,
  ) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    int selectedColor = existing?.colorValue ?? Colors.blue.toARGB32();

    final colorOptions = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.amber,
      Colors.indigo,
      Colors.cyan,
      Colors.brown,
      Colors.lime,
    ];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing != null ? 'Modifier le niveau' : 'Nouveau niveau'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom du niveau',
                  hintText: 'Ex: ASTR 1, DISPO 1...',
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Couleur :',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: colorOptions.map((color) {
                  final isSelected = selectedColor == color.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      setDialogState(() {
                        selectedColor = color.toARGB32();
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.black : Colors.transparent,
                          width: isSelected ? 3 : 0,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, {
                    'name': nameController.text.trim(),
                    'colorValue': selectedColor,
                  });
                }
              },
              child: Text(existing != null ? 'Modifier' : 'Créer'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        if (existing != null) {
          final updated = existing.copyWith(
            name: result['name'] as String,
            colorValue: result['colorValue'] as int,
          );
          await _onCallLevelRepository.update(updated, stationId);
          setState(() {
            final index = _onCallLevels.indexWhere((l) => l.id == existing.id);
            if (index != -1) _onCallLevels[index] = updated;
          });
        } else {
          final newLevel = OnCallLevel(
            id: '',
            name: result['name'] as String,
            colorValue: result['colorValue'] as int,
            order: _onCallLevels.length,
          );
          final id = await _onCallLevelRepository.create(newLevel, stationId);
          setState(() {
            _onCallLevels.add(newLevel.copyWith(id: id));
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Niveau sauvegardé')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteLevel(
    BuildContext context,
    String stationId,
    OnCallLevel level,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le niveau'),
        content: Text(
          'Voulez-vous vraiment supprimer le niveau "${level.name}" ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _onCallLevelRepository.delete(level.id, stationId);
        setState(() {
          _onCallLevels.removeWhere((l) => l.id == level.id);
        });
        // Nettoyer les références dans station si nécessaire
        bool stationChanged = false;
        Station updated = _currentStation!;
        if (updated.defaultOnCallLevelId == level.id) {
          updated = updated.copyWith(defaultOnCallLevelId: '');
          stationChanged = true;
        }
        if (updated.replacementOnCallLevelId == level.id) {
          updated = updated.copyWith(replacementOnCallLevelId: '');
          stationChanged = true;
        }
        if (updated.shortReplacementLevelId == level.id) {
          updated = updated.copyWith(shortReplacementLevelId: '');
          stationChanged = true;
        }
        if (updated.longReplacementLevelId == level.id) {
          updated = updated.copyWith(longReplacementLevelId: '');
          stationChanged = true;
        }
        if (stationChanged) {
          _currentStation = updated;
          _saveStationConfig();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Niveau supprimé')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e')),
          );
        }
      }
    }
  }

  Widget _buildReplacementModeSection(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.how_to_reg),
            title: const Text(
              'Acceptation automatique d\'agents sous-qualifiés',
            ),
            subtitle: const Text(
              'Permettre aux agents sous-qualifiés d\'accepter automatiquement les demandes de remplacement',
            ),
            value: _currentStation!.allowUnderQualifiedAutoAcceptance,
            activeThumbColor: KColors.appNameColor,
            activeTrackColor: KColors.appNameColor.withValues(alpha: 0.5),
            onChanged: (value) {
              setState(() {
                _currentStation = _currentStation!.copyWith(
                  allowUnderQualifiedAutoAcceptance: value,
                );
              });
              _saveStationConfig();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSkillWeightsSection(BuildContext context) {
    // Trier par catégorie pour un affichage organisé, en filtrant les skills vides
    final skillsByCategory = <String, List<String>>{};
    for (final category in KSkills.skillCategoryOrder) {
      final categorySkills = KSkills.skillLevels[category];
      if (categorySkills != null) {
        // Filtrer les skills vides
        final validSkills = categorySkills
            .where((skill) => skill.isNotEmpty)
            .toList();
        if (validSkills.isNotEmpty) {
          skillsByCategory[category] = validSkills;
        }
      }
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Pondération des compétences'),
            subtitle: const Text(
              'Ajuster l\'importance de chaque compétence dans le calcul de similarité (1.0 = normal, 2.0 = double importance)',
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bouton pour réinitialiser
                if (_currentStation!.skillWeights.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Réinitialiser tous les poids'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _currentStation = _currentStation!.copyWith(
                            skillWeights: {},
                          );
                        });
                        _saveStationConfig();
                      },
                    ),
                  ),
                // Liste des catégories de compétences
                ...KSkills.skillCategoryOrder.map((category) {
                  final categorySkills = skillsByCategory[category] ?? [];
                  if (categorySkills.isEmpty) return const SizedBox.shrink();

                  return ExpansionTile(
                    title: Text(
                      category,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    initiallyExpanded: false,
                    children: [
                      for (final skill in categorySkills)
                        if (skill.isNotEmpty) // Filtrer les skills vides
                          Builder(
                            builder: (context) {
                              final currentWeight =
                                  _currentStation!.skillWeights[skill] ?? 1.0;
                              final isModified = _currentStation!.skillWeights
                                  .containsKey(skill);

                              return ListTile(
                                dense: true,
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        skill,
                                        style: TextStyle(
                                          fontWeight: isModified
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: isModified
                                              ? KColors.appNameColor
                                              : null,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${currentWeight.toStringAsFixed(1)}x',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isModified
                                            ? KColors.appNameColor
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Slider(
                                  value: currentWeight,
                                  min: 0.0,
                                  max: 3.0,
                                  divisions: 30,
                                  activeColor: KColors.appNameColor,
                                  label: currentWeight.toStringAsFixed(1),
                                  onChanged: (value) {
                                    setState(() {
                                      final newWeights =
                                          Map<String, double>.from(
                                            _currentStation!.skillWeights,
                                          );
                                      if (value == 1.0) {
                                        // Si on revient à 1.0, retirer de la map
                                        newWeights.remove(skill);
                                      } else {
                                        newWeights[skill] = value;
                                      }
                                      _currentStation = _currentStation!
                                          .copyWith(skillWeights: newWeights);
                                    });
                                  },
                                  onChangeEnd: (value) {
                                    _saveStationConfig();
                                  },
                                ),
                              );
                            },
                          ),
                    ],
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionsSection(BuildContext context) {
    final user = userNotifier.value;
    if (user == null) return const SizedBox.shrink();

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.list),
            title: const Text('Liste des postes'),
            subtitle: Text('${_positions.length} poste(s) configuré(s)'),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                await _addPosition(context);
                if (mounted) {
                  final positions = await _positionRepository
                      .getPositionsByStation(user.station)
                      .first;
                  setState(() => _positions = positions);
                }
              },
            ),
          ),
          if (_positions.isNotEmpty) ...[
            const Divider(height: 1),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _positions.length,
              onReorder: (oldIndex, newIndex) =>
                  _reorderPositions(oldIndex, newIndex, user.station),
              itemBuilder: (context, index) {
                final position = _positions[index];
                return KeyedSubtree(
                  key: ValueKey(position.id),
                  child: _buildPositionTile(context, position),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _reorderPositions(int oldIndex, int newIndex, String stationId) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = _positions.removeAt(oldIndex);
      _positions.insert(newIndex, item);
      for (int i = 0; i < _positions.length; i++) {
        _positions[i] = _positions[i].copyWith(order: i);
      }
    });
    _positionRepository.reorderPositions(stationId, _positions);
  }

  Widget _buildPositionTile(BuildContext context, Position position) {
    final icon = position.iconName != null
        ? KSkills.positionIcons[position.iconName]
        : null;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: KColors.appNameColor.withOpacity(0.1),
        child: icon != null
            ? Icon(icon, color: KColors.appNameColor, size: 20)
            : Text(
                '${position.order + 1}',
                style: TextStyle(
                  color: KColors.appNameColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      title: Text(position.name),
      subtitle: position.description != null
          ? Text(
              position.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => _editPosition(context, position),
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
            onPressed: () => _deletePosition(context, position),
          ),
        ],
      ),
    );
  }

  Future<void> _editMaxAgentsPerShift(BuildContext context) async {
    final controller = TextEditingController(
      text: _currentStation!.maxAgentsPerShift.toString(),
    );

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre max d\'agents par garde'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nombre d\'agents',
            suffixText: 'agents',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value > 0) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _currentStation = _currentStation!.copyWith(maxAgentsPerShift: result);
      });
      await _saveStationConfig();
    }
  }

  Future<void> _editWaveDelay(BuildContext context) async {
    final controller = TextEditingController(
      text: _currentStation!.notificationWaveDelayMinutes.toString(),
    );

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Délai entre les vagues'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Délai',
            suffixText: 'minutes',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value > 0) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _currentStation = _currentStation!.copyWith(
          notificationWaveDelayMinutes: result,
        );
      });
      await _saveStationConfig();
    }
  }

  Future<void> _addPosition(BuildContext context) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String? selectedIcon;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouveau poste'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom du poste',
                    hintText: 'Ex: Pharmacie, EAP, Habillement, ...',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optionnel)',
                    hintText: 'Ex: Responsable de l\'équipe',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Icône du poste :',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: KSkills.positionIcons.entries.map((entry) {
                    final isSelected = selectedIcon == entry.key;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedIcon = entry.key;
                        });
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? KColors.appNameColor.withOpacity(0.2)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? KColors.appNameColor
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Icon(
                          entry.value,
                          size: 24,
                          color: isSelected
                              ? KColors.appNameColor
                              : Colors.grey.shade700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (selectedIcon != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    KSkills.positionIconNames[selectedIcon] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, {
                    'name': nameController.text.trim(),
                    'description': descriptionController.text.trim(),
                    if (selectedIcon != null) 'iconName': selectedIcon!,
                  });
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      final user = userNotifier.value;
      if (user == null) return;

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);

      try {
        // Récupérer le nombre actuel de positions pour définir l'ordre
        final currentPositions = await _positionRepository
            .getPositionsByStation(user.station)
            .first;

        final position = Position(
          id: '',
          name: result['name']!,
          stationId: user.station,
          order: currentPositions.length,
          description: result['description']!.isEmpty
              ? null
              : result['description'],
          iconName: result['iconName'],
        );

        await _positionRepository.createPosition(position);

        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Poste créé avec succès')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(SnackBar(content: Text('Erreur: $e')));
        }
      }
    }
  }

  Future<void> _editPosition(BuildContext context, Position position) async {
    if (!mounted) return;

    final nameController = TextEditingController(text: position.name);
    final descriptionController = TextEditingController(
      text: position.description ?? '',
    );
    String? selectedIcon = position.iconName;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Modifier le poste'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nom du poste'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optionnel)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Icône du poste :',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: KSkills.positionIcons.entries.map((entry) {
                    final isSelected = selectedIcon == entry.key;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedIcon = entry.key;
                        });
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? KColors.appNameColor.withOpacity(0.2)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? KColors.appNameColor
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Icon(
                          entry.value,
                          size: 24,
                          color: isSelected
                              ? KColors.appNameColor
                              : Colors.grey.shade700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (selectedIcon != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    KSkills.positionIconNames[selectedIcon] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, {
                    'name': nameController.text.trim(),
                    'description': descriptionController.text.trim(),
                    if (selectedIcon != null) 'iconName': selectedIcon!,
                  });
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);

      try {
        final updatedPosition = position.copyWith(
          name: result['name']!,
          description: result['description']!.isEmpty
              ? null
              : result['description'],
          iconName: result['iconName'],
        );

        await _positionRepository.updatePosition(updatedPosition);

        if (mounted) {
          final user = userNotifier.value;
          if (user != null) {
            final positions = await _positionRepository
                .getPositionsByStation(user.station)
                .first;
            setState(() => _positions = positions);
          }
          messenger.showSnackBar(
            const SnackBar(content: Text('Poste modifié avec succès')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(SnackBar(content: Text('Erreur: $e')));
        }
      }
    }
  }

  Future<void> _deletePosition(BuildContext context, Position position) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le poste'),
        content: Text(
          'Voulez-vous vraiment supprimer le poste "${position.name}" ?\n\n'
          'Les agents assignés à ce poste ne seront plus associés à un poste.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);

      try {
        await _positionRepository.deletePosition(
          position.id,
          stationId: position.stationId,
        );

        if (mounted) {
          final user = userNotifier.value;
          if (user != null) {
            final positions = await _positionRepository
                .getPositionsByStation(user.station)
                .first;
            setState(() => _positions = positions);
          }
          messenger.showSnackBar(
            const SnackBar(content: Text('Poste supprimé avec succès')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(SnackBar(content: Text('Erreur: $e')));
        }
      }
    }
  }
}

class _MembershipRequestsDialog extends StatefulWidget {
  final List<MembershipRequest> requests;
  final String stationId;
  final VoidCallback onRequestHandled;

  const _MembershipRequestsDialog({
    required this.requests,
    required this.stationId,
    required this.onRequestHandled,
  });

  @override
  State<_MembershipRequestsDialog> createState() =>
      _MembershipRequestsDialogState();
}

class _MembershipRequestsDialogState extends State<_MembershipRequestsDialog> {
  final CloudFunctionsService _cloudFunctionsService = CloudFunctionsService();
  bool _isHandling = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.person_add, color: KColors.appNameColor),
          const SizedBox(width: 8),
          const Text('Demandes d\'adhésion'),
          const Spacer(),
          if (widget.requests.isNotEmpty)
            Chip(
              label: Text('${widget.requests.length}'),
              backgroundColor: KColors.appNameColor.withValues(alpha: 0.2),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.requests.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 48, color: Colors.green),
                    SizedBox(height: 16),
                    Text('Aucune demande en attente'),
                  ],
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.requests.length,
                itemBuilder: (context, index) {
                  final request = widget.requests[index];
                  return _buildRequestCard(request);
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isHandling ? null : () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }

  Widget _buildRequestCard(MembershipRequest request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: KColors.appNameColor.withValues(alpha: 0.1),
                  child: Text(
                    request.firstName[0].toUpperCase(),
                    style: const TextStyle(
                      color: KColors.appNameColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${request.firstName} ${request.lastName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Matricule: ${request.matricule}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      Text(
                        'Demande le ${_formatDate(request.requestedAt)}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _isHandling
                      ? null
                      : () => _handleRequest(request, accept: false),
                  icon: const Icon(Icons.close),
                  label: const Text('Refuser'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _isHandling
                      ? null
                      : () => _handleRequest(
                          request,
                          accept: true,
                          role: 'agent',
                        ),
                  icon: const Icon(Icons.check),
                  label: const Text('Accepter'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KColors.appNameColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} à ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _handleRequest(
    MembershipRequest request, {
    required bool accept,
    String? role,
    String? team,
  }) async {
    setState(() {
      _isHandling = true;
    });

    try {
      await _cloudFunctionsService.handleMembershipRequest(
        stationId: widget.stationId,
        requestAuthUid: request.authUid,
        accept: accept,
        role: role,
        team: team,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? '${request.firstName} ${request.lastName} a été ajouté à la caserne'
                  : 'Demande refusée',
            ),
            backgroundColor: accept ? Colors.green : Colors.orange,
          ),
        );

        // Retirer la demande de la liste
        widget.requests.remove(request);
        widget.onRequestHandled();

        if (widget.requests.isEmpty) {
          Navigator.pop(context);
        } else {
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isHandling = false;
        });
      }
    }
  }
}
