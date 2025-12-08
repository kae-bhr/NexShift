import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/models/station_model.dart';
import 'package:nexshift_app/core/data/models/position_model.dart';
import 'package:nexshift_app/core/repositories/position_repository.dart';
import 'package:nexshift_app/core/repositories/station_repository.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/utils/constants.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final PositionRepository _positionRepository = PositionRepository();
  final StationRepository _stationRepository = StationRepository();

  Station? _currentStation;
  bool _isLoading = true;

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
      } else {
        // Créer la station si elle n'existe pas
        _currentStation = Station(
          id: user.station,
          name: user.station,
        );
        await _saveStationConfig();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de chargement: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveStationConfig() async {
    if (_currentStation == null) return;

    try {
      await _stationRepository.upsert(_currentStation!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration sauvegardée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de sauvegarde: $e')),
        );
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
                    _buildSectionHeader(context, 'Mode de remplacement'),
                    _buildReplacementModeSection(context),
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
            subtitle: Text('${_currentStation!.notificationWaveDelayMinutes} minutes'),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _editWaveDelay(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplacementModeSection(BuildContext context) {
    return Card(
      child: Column(
        children: [
          RadioListTile<ReplacementMode>(
            secondary: const Icon(Icons.compare_arrows),
            title: const Text('Par similarité'),
            subtitle: const Text('Basé sur les compétences et l\'historique'),
            value: ReplacementMode.similarity,
            groupValue: _currentStation!.replacementMode,
            activeColor: KColors.appNameColor,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _currentStation = _currentStation!.copyWith(
                    replacementMode: value,
                  );
                });
                _saveStationConfig();
              }
            },
          ),
          const Divider(height: 1),
          RadioListTile<ReplacementMode>(
            secondary: const Icon(Icons.work_outline),
            title: const Text('Par poste'),
            subtitle: const Text('Basé sur la hiérarchie des postes'),
            value: ReplacementMode.position,
            groupValue: _currentStation!.replacementMode,
            activeColor: KColors.appNameColor,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _currentStation = _currentStation!.copyWith(
                    replacementMode: value,
                  );
                });
                _saveStationConfig();
              }
            },
          ),
          if (_currentStation!.replacementMode == ReplacementMode.position) ...[
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.arrow_downward),
              title: const Text('Rechercher agents sous-qualifiés'),
              subtitle: const Text('Permettre les postes inférieurs'),
              value: _currentStation!.allowUnderQualifiedReplacement,
              activeColor: KColors.appNameColor,
              activeTrackColor: KColors.appNameColor.withOpacity(0.5),
              onChanged: (value) {
                setState(() {
                  _currentStation = _currentStation!.copyWith(
                    allowUnderQualifiedReplacement: value,
                  );
                });
                _saveStationConfig();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPositionsSection(BuildContext context) {
    final user = userNotifier.value;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<List<Position>>(
      stream: _positionRepository.getPositionsByStation(user.station),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.error, color: Colors.red),
              title: const Text('Erreur de chargement'),
              subtitle: Text(snapshot.error.toString()),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final positions = snapshot.data!;

        return Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.list),
                title: const Text('Liste des postes'),
                subtitle: Text('${positions.length} poste(s) configuré(s)'),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _addPosition(context),
                ),
              ),
              if (positions.isNotEmpty) ...[
                const Divider(height: 1),
                ...positions.map((position) => _buildPositionTile(context, position)),
              ],
            ],
          ),
        );
      },
    );
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
                    hintText: 'Ex: Chef d\'agrès',
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
          description: result['description']!.isEmpty ? null : result['description'],
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
          messenger.showSnackBar(
            SnackBar(content: Text('Erreur: $e')),
          );
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
                  decoration: const InputDecoration(
                    labelText: 'Nom du poste',
                  ),
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
          description: result['description']!.isEmpty ? null : result['description'],
          iconName: result['iconName'],
        );

        await _positionRepository.updatePosition(updatedPosition);

        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Poste modifié avec succès')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Erreur: $e')),
          );
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
        await _positionRepository.deletePosition(position.id);

        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Poste supprimé avec succès')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Erreur: $e')),
          );
        }
      }
    }
  }
}
