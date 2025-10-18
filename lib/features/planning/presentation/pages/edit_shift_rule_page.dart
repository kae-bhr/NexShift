import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/shift_rule_model.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/repositories/shift_rule_repository.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:uuid/uuid.dart';

class EditShiftRulePage extends StatefulWidget {
  final ShiftRule? rule; // null = création, non-null = édition

  const EditShiftRulePage({super.key, this.rule});

  @override
  State<EditShiftRulePage> createState() => _EditShiftRulePageState();
}

class _EditShiftRulePageState extends State<EditShiftRulePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _repository = ShiftRuleRepository();
  final _uuid = const Uuid();

  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late ShiftRotationType _rotationType;
  late List<String> _selectedTeams;
  late DaysOfWeek _selectedDays;
  late bool _spansNextDay;
  late int _rotationInterval;
  late DateTime _startDate;
  late DateTime _endDate;

  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.rule != null;

    if (_isEditing) {
      try {
        debugPrint('EditShiftRulePage: Loading rule ${widget.rule!.id}');
        _nameController.text = widget.rule!.name;
        _startTime = widget.rule!.startTime;
        _endTime = widget.rule!.endTime;
        _rotationType = widget.rule!.rotationType;
        _selectedTeams = List.from(widget.rule!.teamIds);
        _selectedDays = widget.rule!.applicableDays;
        _spansNextDay = widget.rule!.spansNextDay;
        _rotationInterval = widget.rule!.rotationIntervalDays;
        _startDate = widget.rule!.startDate;
        _endDate =
            widget.rule!.endDate ??
            widget.rule!.startDate.add(const Duration(days: 365));
        debugPrint('EditShiftRulePage: Rule loaded successfully');
      } catch (e, stackTrace) {
        debugPrint('EditShiftRulePage: Error loading rule: $e');
        debugPrint('StackTrace: $stackTrace');
        // Fallback sur valeurs par défaut
        _nameController.text = '';
        _startTime = const TimeOfDay(hour: 19, minute: 0);
        _endTime = const TimeOfDay(hour: 6, minute: 0);
        _rotationType = ShiftRotationType.daily;
        _selectedTeams = ['A', 'B', 'C', 'D'];
        _selectedDays = DaysOfWeek.weekdays;
        _spansNextDay = true;
        _rotationInterval = 1;
        _startDate = DateTime.now();
        _endDate = DateTime.now().add(const Duration(days: 365));
      }
    } else {
      _nameController.text = '';
      _startTime = const TimeOfDay(hour: 19, minute: 0);
      _endTime = const TimeOfDay(hour: 6, minute: 0);
      _rotationType = ShiftRotationType.daily;
      _selectedTeams = ['A', 'B', 'C', 'D'];
      _selectedDays = DaysOfWeek.weekdays;
      _spansNextDay = true;
      _rotationInterval = 1;
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(const Duration(days: 365));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: _isEditing ? 'Modifier la règle' : 'Nouvelle règle',
        bottomColor: KColors.appNameColor,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Nom
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nom de la règle',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Veuillez saisir un nom';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Date de départ et de fin
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Période de la rotation',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
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
                              _endDate = _startDate.add(
                                const Duration(days: 365),
                              );
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        'Début: ${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}',
                      ),
                    ),
                    const SizedBox(height: 8),
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
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Plage horaire
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Plage horaire',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: _startTime,
                              );
                              if (time != null) {
                                setState(() => _startTime = time);
                              }
                            },
                            icon: const Icon(Icons.access_time),
                            label: Text('Début: ${_startTime.format(context)}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: _endTime,
                              );
                              if (time != null) {
                                setState(() => _endTime = time);
                              }
                            },
                            icon: const Icon(Icons.access_time),
                            label: Text('Fin: ${_endTime.format(context)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _spansNextDay,
                      onChanged: (value) {
                        setState(() => _spansNextDay = value ?? false);
                      },
                      title: const Text('Se termine le lendemain'),
                      contentPadding: EdgeInsets.zero,
                      activeColor: KColors.appNameColor,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Type de rotation
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Type de rotation',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ShiftRotationType>(
                      value: _rotationType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: ShiftRotationType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(
                            type.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _rotationType = value!;
                          if (_rotationType == ShiftRotationType.none) {
                            _selectedTeams = [];
                          }
                        });
                      },
                    ),
                    if (_rotationType == ShiftRotationType.custom) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: _rotationInterval.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Intervalle (jours)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          _rotationInterval = int.tryParse(value) ?? 1;
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Équipes
            if (_rotationType != ShiftRotationType.none) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Équipes participantes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['A', 'B', 'C', 'D'].map((team) {
                          final isSelected = _selectedTeams.contains(team);
                          return FilterChip(
                            label: Text('Équipe $team'),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedTeams.add(team);
                                } else {
                                  _selectedTeams.remove(team);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      if (_selectedTeams.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Ordre de rotation (glissez pour réorganiser)',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'La première équipe de la liste commencera à la date de départ.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 8),
                        _buildTeamOrderList(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Jours de la semaine
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Jours applicables',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _buildDayChip('Lun', _selectedDays.monday, (v) {
                      setState(() {
                        _selectedDays = _selectedDays.copyWith(monday: v);
                      });
                    }),
                    _buildDayChip('Mar', _selectedDays.tuesday, (v) {
                      setState(() {
                        _selectedDays = _selectedDays.copyWith(tuesday: v);
                      });
                    }),
                    _buildDayChip('Mer', _selectedDays.wednesday, (v) {
                      setState(() {
                        _selectedDays = _selectedDays.copyWith(wednesday: v);
                      });
                    }),
                    _buildDayChip('Jeu', _selectedDays.thursday, (v) {
                      setState(() {
                        _selectedDays = _selectedDays.copyWith(thursday: v);
                      });
                    }),
                    _buildDayChip('Ven', _selectedDays.friday, (v) {
                      setState(() {
                        _selectedDays = _selectedDays.copyWith(friday: v);
                      });
                    }),
                    _buildDayChip('Sam', _selectedDays.saturday, (v) {
                      setState(() {
                        _selectedDays = _selectedDays.copyWith(saturday: v);
                      });
                    }),
                    _buildDayChip('Dim', _selectedDays.sunday, (v) {
                      setState(() {
                        _selectedDays = _selectedDays.copyWith(sunday: v);
                      });
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Boutons d'action
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _saveRule,
                    child: Text(_isEditing ? 'Modifier' : 'Créer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayChip(String label, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(label),
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeColor: KColors.appNameColor,
    );
  }

  Widget _buildTeamOrderList() {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) {
            newIndex -= 1;
          }
          final team = _selectedTeams.removeAt(oldIndex);
          _selectedTeams.insert(newIndex, team);
        });
      },
      children: _selectedTeams.asMap().entries.map((entry) {
        final index = entry.key;
        final team = entry.value;
        return ListTile(
          key: ValueKey(team),
          leading: CircleAvatar(
            backgroundColor: KColors.appNameColor,
            child: Text(
              '${index + 1}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text('Équipe $team'),
          subtitle: index == 0
              ? const Text(
                  'Commence en premier',
                  style: TextStyle(fontStyle: FontStyle.italic),
                )
              : null,
          trailing: const Icon(Icons.drag_handle),
        );
      }).toList(),
    );
  }

  Future<void> _saveRule() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_selectedDays.hasAnyDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner au moins un jour')),
      );
      return;
    }

    if (_rotationType != ShiftRotationType.none && _selectedTeams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner au moins une équipe'),
        ),
      );
      return;
    }

    final rule = ShiftRule(
      id: _isEditing ? widget.rule!.id : _uuid.v4(),
      name: _nameController.text,
      startTime: _startTime,
      endTime: _endTime,
      spansNextDay: _spansNextDay,
      rotationType: _rotationType,
      teamIds: _selectedTeams,
      rotationIntervalDays: _rotationInterval,
      applicableDays: _selectedDays,
      isActive: true,
      startDate: _startDate,
      endDate: _endDate,
      priority: _isEditing ? widget.rule!.priority : 0,
    );

    await _repository.upsert(rule);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }
}
