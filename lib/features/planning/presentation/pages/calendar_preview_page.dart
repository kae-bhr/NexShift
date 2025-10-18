import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/generated_shift_model.dart';
import 'package:nexshift_app/core/presentation/widgets/custom_app_bar.dart';
import 'package:nexshift_app/core/repositories/shift_rule_repository.dart';
import 'package:nexshift_app/core/repositories/shift_exception_repository.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/services/shift_generator.dart';
import 'package:nexshift_app/core/utils/constants.dart';

class CalendarPreviewPage extends StatefulWidget {
  const CalendarPreviewPage({super.key});

  @override
  State<CalendarPreviewPage> createState() => _CalendarPreviewPageState();
}

class _CalendarPreviewPageState extends State<CalendarPreviewPage> {
  final _ruleRepository = ShiftRuleRepository();
  final _exceptionRepository = ShiftExceptionRepository();
  final _teamRepository = TeamRepository();
  final _generator = ShiftGenerator();

  List<GeneratedShift> _shifts = [];
  bool _isLoading = true;
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _generateShifts();
  }

  Future<void> _generateShifts() async {
    setState(() => _isLoading = true);

    final rules = await _ruleRepository.getActiveRules();
    final exceptions = await _exceptionRepository.getAll();
    debugPrint('📅 [Preview] Total exceptions loaded: ${exceptions.length}');

    final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endDate = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
      23,
      59,
      59,
    );

    // Filtrer les exceptions qui chevauchent la période du mois
    final relevantExceptions = exceptions.where((e) {
      final isRelevant = e.startDateTime.isBefore(endDate.add(const Duration(days: 1))) &&
          e.endDateTime.isAfter(startDate);
      if (isRelevant) {
        debugPrint('  ✓ [Preview] Exception: ${e.reason} (${e.startDateTime} - ${e.endDateTime})');
      }
      return isRelevant;
    }).toList();

    debugPrint('📅 [Preview] Relevant exceptions for $startDate - $endDate: ${relevantExceptions.length}');

    // Étendre la génération d'un jour pour capturer les shifts qui commencent le dernier jour
    // et se terminent le jour suivant
    final extendedEndDate = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      1,
      23,
      59,
      59,
    );

    final shifts = _generator.generateShifts(
      rules: rules,
      exceptions: relevantExceptions,
      startDate: startDate,
      endDate: extendedEndDate,
    );

    setState(() {
      _shifts = shifts;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Aperçu du planning',
        bottomColor: KColors.appNameColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildMonthSelector(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                      0,
                    ).day,
                    itemBuilder: (context, index) {
                      final day = index + 1;
                      final date = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month,
                        day,
                      );
                      final dayShifts = _generator.getShiftsForDate(
                        _shifts,
                        date,
                      );

                      return _buildDayCard(date, dayShifts);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: KColors.appNameColor.withOpacity(0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month - 1,
                );
              });
              _generateShifts();
            },
          ),
          Text(
            _getMonthName(_selectedMonth.month) + ' ${_selectedMonth.year}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month + 1,
                );
              });
              _generateShifts();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(DateTime date, List<GeneratedShift> shifts) {
    final isToday =
        DateTime.now().year == date.year &&
        DateTime.now().month == date.month &&
        DateTime.now().day == date.day;

    // Déterminer s'il y a une seule équipe non vide sur le jour
    final nonEmptyTeamIds = shifts
        .where((s) => s.teamId != null && s.teamId!.isNotEmpty)
        .map((s) => s.teamId)
        .toSet();
    final singleTeamId = nonEmptyTeamIds.length == 1
        ? nonEmptyTeamIds.first
        : null;

    // Vérifier si le jour contient au moins une exception
    final hasException = shifts.any((s) => s.isException);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isToday ? KColors.appNameColor.withOpacity(0.1) : null,
      child: FutureBuilder(
        future: singleTeamId != null
            ? _teamRepository.getById(singleTeamId)
            : null,
        builder: (context, snapshot) {
          final team = snapshot.data;
          final dayColor =
              team?.color ??
              (isToday ? KColors.appNameColor : Colors.grey[300]);

          return ExpansionTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: dayColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  date.day.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            title: Text(
              _getDayName(date.weekday),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: hasException
                ? const Icon(Icons.warning, color: Colors.orange, size: 20)
                : null,
            subtitle: Text(
              shifts.isEmpty
                  ? 'Aucune astreinte'
                  : '${shifts.length} astreinte(s)',
            ),
            children: shifts.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Aucune astreinte définie pour ce jour'),
                    ),
                  ]
                : shifts.map((shift) => _buildShiftTile(shift)).toList(),
          );
        },
      ),
    );
  }

  Widget _buildShiftTile(GeneratedShift shift) {
    return FutureBuilder(
      future: _teamRepository.getById(shift.teamId ?? ''),
      builder: (context, snapshot) {
        final team = snapshot.data;
        final teamColor = team?.color ?? Colors.grey;

        // Vérifier si l'astreinte commence avant aujourd'hui
        final shiftStartsToday =
            shift.startDateTime.day == shift.endDateTime.day ||
            shift.startDateTime.hour >= shift.endDateTime.hour;

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: shift.isUnassigned ? Colors.grey : teamColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                shift.teamId ?? '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          title: Row(
            children: [
              if (!shiftStartsToday)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.arrow_back, size: 16, color: Colors.orange),
                ),
              Expanded(
                child: Text(
                  shift.isException && shift.exceptionReason != null
                      ? shift.exceptionReason!
                      : shift.ruleName,
                ),
              ),
            ],
          ),
          subtitle: Text(_getDetailedTimeRange(shift)),
          trailing: shift.isException
              ? const Icon(Icons.warning, color: Colors.orange, size: 20)
              : null,
        );
      },
    );
  }

  String _getDetailedTimeRange(GeneratedShift shift) {
    final startStr =
        '${shift.startDateTime.hour.toString().padLeft(2, '0')}:${shift.startDateTime.minute.toString().padLeft(2, '0')}';
    final endStr =
        '${shift.endDateTime.hour.toString().padLeft(2, '0')}:${shift.endDateTime.minute.toString().padLeft(2, '0')}';

    // Si l'astreinte span sur plusieurs jours
    if (shift.startDateTime.day != shift.endDateTime.day) {
      final startDate =
          '${shift.startDateTime.day.toString().padLeft(2, '0')}/${shift.startDateTime.month.toString().padLeft(2, '0')}';
      final endDate =
          '${shift.endDateTime.day.toString().padLeft(2, '0')}/${shift.endDateTime.month.toString().padLeft(2, '0')}';
      return '$startStr ($startDate) - $endStr ($endDate)';
    }

    return '$startStr - $endStr';
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Lundi';
      case DateTime.tuesday:
        return 'Mardi';
      case DateTime.wednesday:
        return 'Mercredi';
      case DateTime.thursday:
        return 'Jeudi';
      case DateTime.friday:
        return 'Vendredi';
      case DateTime.saturday:
        return 'Samedi';
      case DateTime.sunday:
        return 'Dimanche';
      default:
        return '';
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    return months[month - 1];
  }
}
