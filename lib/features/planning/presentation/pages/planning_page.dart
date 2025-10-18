import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/repositories/subshift_repositories.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/subshift_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/data/models/availability_model.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/planning_bar.dart';
import 'package:nexshift_app/features/planning/presentation/pages/planning_team_details_page.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/planning_header_widget.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/repositories/team_repository.dart';
import 'package:nexshift_app/core/utils/subshift_normalizer.dart';

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  DateTime _currentWeekStart = _getStartOfWeek(DateTime.now());
  List<Planning> _plannings = [];
  List<Subshift> _subshifts = [];
  List<Availability> _availabilities = [];
  User? _currentUser;
  Map<String, Color> _teamColorById = {};
  Color? _userTeamColor;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null).then((_) {
      _loadUserAndPlanning();
    });
    stationViewNotifier.addListener(_onStationViewChanged);
    teamDataChangedNotifier.addListener(_onTeamDataChanged);
  }

  @override
  void dispose() {
    stationViewNotifier.removeListener(_onStationViewChanged);
    teamDataChangedNotifier.removeListener(_onTeamDataChanged);
    super.dispose();
  }

  void _onStationViewChanged() {
    // when the toggle changes, reload plannings to reflect personal/centre view
    _loadUserAndPlanning();
  }

  void _onTeamDataChanged() {
    // Reload team colors when teams are modified
    _loadUserAndPlanning();
  }

  Future<void> _loadUserAndPlanning() async {
    final user = await UserStorageHelper.loadUser();
    if (user != null) {
      final repo = LocalRepository();
      final isStationView = stationViewNotifier.value;
      // Load subshifts first (used to include extra plannings for replacer mode)
      final rawSubshifts = await SubshiftRepository().getAll();
      // Résoudre les cascades de remplacements pour affichage correct
      final subshifts = resolveReplacementCascades(rawSubshifts);
      // Load teams to colorize bars by team in station view
      Color? userTeamColor;
      try {
        final teams = await TeamRepository().getAll();
        _teamColorById = {for (final t in teams) t.id: t.color};
        // Récupérer la couleur de l'équipe de l'utilisateur
        final userTeam = teams.firstWhere(
          (t) => t.id == user.team,
          orElse: () => teams.first,
        );
        userTeamColor = userTeam.color;
      } catch (_) {
        _teamColorById = {};
        userTeamColor = null;
      }
      final weekStart = _currentWeekStart;
      final weekEnd = weekStart.add(const Duration(days: 7));

      List<Planning> plannings;
      List<Availability> availabilities = [];
      if (isStationView) {
        // Centre view: show all plannings that overlap the selected week
        plannings = await repo.getAllPlanningsInRange(weekStart, weekEnd);
      } else {
        // Personal view: start with user's own plannings in the selected week
        plannings = await repo.getPlanningsForUserInRange(
          user,
          true,
          weekStart,
          weekEnd,
        );
        // Ensure we also include plannings where the user is a replacer
        final replacerPlanningIds = subshifts
            .where((s) => s.replacerId == user.id)
            .map((s) => s.planningId)
            .toSet();
        final missingIds = replacerPlanningIds
            .where((id) => !plannings.any((p) => p.id == id))
            .toList();
        for (final id in missingIds) {
          final p = await repo.getPlanningById(id);
          if (p != null) plannings.add(p);
        }

        // Load user's availabilities for personal view
        final allAvailabilities = await repo.getAvailabilities();
        final userAvailabilities = allAvailabilities
            .where(
              (a) =>
                  a.agentId == user.id &&
                  a.end.isAfter(weekStart) &&
                  a.start.isBefore(weekEnd),
            )
            .toList();

        // Fusionner les disponibilités qui se chevauchent
        availabilities = _mergeOverlappingAvailabilities(userAvailabilities);
      }

      setState(() {
        _plannings = plannings;
        _subshifts = subshifts;
        _availabilities = availabilities;
        _currentUser = user;
        _userTeamColor = userTeamColor;
      });
    }
  }

  static DateTime _getStartOfWeek(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  // Week navigation is handled by [PlanningHeader]; PlanningPage keeps
  // the current week state and passes handlers into the header.

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Découpe un planning traversant minuit en segments journaliers
  List<Map<String, dynamic>> _splitPlanningByDay(Planning planning) {
    List<Map<String, dynamic>> segments = [];

    DateTime currentStart = planning.startTime;
    DateTime end = planning.endTime;
    bool isFirstSegment = true;

    while (currentStart.isBefore(end)) {
      // Calculer la fin de la journée courante (lendemain à 00:00)
      DateTime nextDayStart = DateTime(
        currentStart.year,
        currentStart.month,
        currentStart.day + 1,
        0,
        0,
      );

      bool crossesMidnight = end.isAfter(nextDayStart);

      DateTime segmentEnd;
      if (crossesMidnight) {
        // Le planning continue après minuit
        segmentEnd = nextDayStart;
      } else {
        // Le planning se termine ce jour
        segmentEnd = end;
      }

      segments.add({
        'day': DateTime(
          currentStart.year,
          currentStart.month,
          currentStart.day,
        ),
        'start': currentStart,
        'end': segmentEnd,
        'planning': planning,
        'isRealStart': isFirstSegment,
        'isRealEnd': !crossesMidnight,
      });

      isFirstSegment = false;
      currentStart = nextDayStart;
    }

    return segments;
  }

  /// Génère les barres à afficher pour un jour donné selon le mode
  /// En mode utilisateur : segments de l'utilisateur moins ses remplacements + ses remplacements
  /// En mode caserne : tous les plannings
  List<Map<String, dynamic>> _generateBarsForDay(DateTime day) {
    final stationView = stationViewNotifier.value;
    final bars = <Map<String, dynamic>>[];

    if (stationView) {
      // Mode caserne : afficher toutes les astreintes
      for (final planning in _plannings) {
        final segments = _splitPlanningByDay(planning);
        for (final seg in segments) {
          if (_isSameDay(seg['day'], day)) {
            // Use team color from loaded map, fallback to grey if not found
            final teamColor =
                _teamColorById[planning.team] ?? const Color(0xFF757575);
            bars.add({
              'start': seg['start'],
              'end': seg['end'],
              'planning': planning,
              'type': 'station', // Pour identification si besoin
              'color': teamColor,
              'isRealStart': seg['isRealStart'] ?? true,
              'isRealEnd': seg['isRealEnd'] ?? true,
            });
          }
        }
      }
    } else {
      // Mode utilisateur
      if (_currentUser == null) return bars;

      for (final planning in _plannings) {
        final segments = _splitPlanningByDay(planning);
        for (final seg in segments) {
          if (!_isSameDay(seg['day'], day)) continue;

          final segStart = seg['start'] as DateTime;
          final segEnd = seg['end'] as DateTime;

          // Vérifier si l'utilisateur est agent sur ce planning
          final isAgent = planning.agentsId.contains(_currentUser!.id);

          if (isAgent) {
            // Trouver les remplacements qui affectent ce segment
            final replacements =
                _subshifts
                    .where(
                      (s) =>
                          s.planningId == planning.id &&
                          s.replacedId == _currentUser!.id &&
                          s.end.isAfter(segStart) &&
                          s.start.isBefore(segEnd),
                    )
                    .toList()
                  ..sort((a, b) => a.start.compareTo(b.start));

            if (replacements.isEmpty) {
              // Aucun remplacement : afficher la barre complète
              final teamColor =
                  _teamColorById[planning.team] ?? const Color(0xFF757575);
              bars.add({
                'start': segStart,
                'end': segEnd,
                'planning': planning,
                'type': 'agent',
                'color': teamColor,
                'isRealStart': seg['isRealStart'] ?? true,
                'isRealEnd': seg['isRealEnd'] ?? true,
              });
            } else {
              // Découper selon les remplacements
              DateTime currentTime = segStart;
              final isRealSegStart = seg['isRealStart'] ?? true;
              final isRealSegEnd = seg['isRealEnd'] ?? true;
              final teamColor =
                  _teamColorById[planning.team] ?? const Color(0xFF757575);

              for (final replacement in replacements) {
                final replStart = replacement.start.isBefore(segStart)
                    ? segStart
                    : replacement.start;
                final replEnd = replacement.end.isAfter(segEnd)
                    ? segEnd
                    : replacement.end;

                // Ajouter la période avant le remplacement
                if (currentTime.isBefore(replStart)) {
                  bars.add({
                    'start': currentTime,
                    'end': replStart,
                    'planning': planning,
                    'type': 'agent',
                    'color': teamColor,
                    'isRealStart': currentTime == segStart && isRealSegStart,
                    'isRealEnd':
                        true, // fin de cette période avant le remplacement
                  });
                }

                currentTime = replEnd.isAfter(currentTime)
                    ? replEnd
                    : currentTime;
              }

              // Ajouter la période après le dernier remplacement
              if (currentTime.isBefore(segEnd)) {
                bars.add({
                  'start': currentTime,
                  'end': segEnd,
                  'planning': planning,
                  'type': 'agent',
                  'color': teamColor,
                  'isRealStart':
                      true, // début de cette période après le remplacement
                  'isRealEnd': isRealSegEnd,
                });
              }
            }
          }

          // Ajouter les périodes où l'utilisateur est remplaçant
          final replacerShifts = _subshifts
              .where(
                (s) =>
                    s.planningId == planning.id &&
                    s.replacerId == _currentUser!.id &&
                    s.end.isAfter(segStart) &&
                    s.start.isBefore(segEnd),
              )
              .toList();

          for (final shift in replacerShifts) {
            final shiftStart = shift.start.isBefore(segStart)
                ? segStart
                : shift.start;
            final shiftEnd = shift.end.isAfter(segEnd) ? segEnd : shift.end;
            final teamColor =
                _teamColorById[planning.team] ?? const Color(0xFF757575);

            bars.add({
              'start': shiftStart,
              'end': shiftEnd,
              'planning': planning,
              'type': 'replacer',
              'color': teamColor,
              // Les barres de remplaçant montrent uniquement les bordures où elles commencent/finissent vraiment
              'isRealStart': shiftStart == shift.start,
              'isRealEnd': shiftEnd == shift.end,
            });
          }
        }
      }

      // Ajouter les disponibilités de l'utilisateur en mode personnel
      for (final availability in _availabilities) {
        final segments = _splitAvailabilityByDay(availability);
        for (final seg in segments) {
          if (_isSameDay(seg['day'], day)) {
            bars.add({
              'start': seg['start'],
              'end': seg['end'],
              'availability': availability,
              'type': 'availability',
              'color': _getShade400(
                _userTeamColor ?? Colors.grey,
              ), // Couleur de l'équipe de l'utilisateur en shade400
              'isRealStart': seg['isRealStart'] ?? true,
              'isRealEnd': seg['isRealEnd'] ?? true,
            });
          }
        }
      }
    }

    return bars;
  }

  /// Découpe une disponibilité traversant minuit en segments journaliers
  List<Map<String, dynamic>> _splitAvailabilityByDay(
    Availability availability,
  ) {
    List<Map<String, dynamic>> segments = [];

    DateTime currentStart = availability.start;
    DateTime end = availability.end;
    bool isFirstSegment = true;

    while (currentStart.isBefore(end)) {
      // Calculer la fin de la journée courante (lendemain à 00:00)
      DateTime nextDayStart = DateTime(
        currentStart.year,
        currentStart.month,
        currentStart.day + 1,
        0,
        0,
      );

      bool crossesMidnight = end.isAfter(nextDayStart);

      DateTime segmentEnd;
      if (crossesMidnight) {
        // La disponibilité continue après minuit
        segmentEnd = nextDayStart;
      } else {
        // La disponibilité se termine ce jour
        segmentEnd = end;
      }

      segments.add({
        'day': DateTime(
          currentStart.year,
          currentStart.month,
          currentStart.day,
        ),
        'start': currentStart,
        'end': segmentEnd,
        'availability': availability,
        'isRealStart': isFirstSegment,
        'isRealEnd': !crossesMidnight,
      });

      isFirstSegment = false;
      currentStart = nextDayStart;
    }

    return segments;
  }

  /// Fusionne les disponibilités qui se chevauchent ou sont adjacentes
  List<Availability> _mergeOverlappingAvailabilities(
    List<Availability> availabilities,
  ) {
    if (availabilities.isEmpty) return [];

    // Trier par heure de début
    final sorted = List<Availability>.from(availabilities)
      ..sort((a, b) => a.start.compareTo(b.start));

    final merged = <Availability>[];
    Availability current = sorted.first;

    for (int i = 1; i < sorted.length; i++) {
      final next = sorted[i];

      // Vérifier si les périodes se chevauchent ou sont adjacentes (écart < 1 minute)
      if (next.start.isBefore(current.end) ||
          next.start.difference(current.end).inMinutes < 1) {
        // Fusionner : étendre la période courante
        current = Availability(
          id: current.id, // Garder l'ID de la première disponibilité
          agentId: current.agentId,
          start: current.start,
          end: next.end.isAfter(current.end) ? next.end : current.end,
          planningId: current.planningId,
        );
      } else {
        // Pas de chevauchement : ajouter la période courante et commencer une nouvelle
        merged.add(current);
        current = next;
      }
    }

    // Ajouter la dernière période
    merged.add(current);

    return merged;
  }

  Color _barColorForType(BuildContext context, String? type) {
    final scheme = Theme.of(context).colorScheme;
    switch (type) {
      case 'replacer':
      case 'agent':
        return scheme.primary;
      case 'station':
      default:
        return scheme.primaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysOfWeek = List.generate(
      7,
      (i) => _currentWeekStart.add(Duration(days: i)),
    );

    return Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: stationViewNotifier,
        builder: (context, stationView, _) {
          return Column(
            children: [
              PlanningHeader(
                currentWeekStart: _currentWeekStart,
                onWeekChanged: (dt) {
                  setState(() => _currentWeekStart = dt);
                  _loadUserAndPlanning();
                },
              ),
              SizedBox(height: 12.0),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadUserAndPlanning,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 80),
                    child: Column(
                      children: daysOfWeek.map((currentDay) {
                        final dailyBars = _generateBarsForDay(currentDay);
                        final index = daysOfWeek.indexOf(currentDay);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Text(
                                "${DateFormat.EEEE('fr_FR').format(currentDay)} ${DateFormat('d MMM', 'fr_FR').format(currentDay)}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 35,
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (details) {
                                      final leftMargin = 16.0;
                                      final totalWidth =
                                          MediaQuery.of(context).size.width -
                                          (leftMargin * 2);
                                      final dx =
                                          details.localPosition.dx - leftMargin;
                                      final clamped = dx.clamp(0.0, totalWidth);
                                      final ratio = (totalWidth > 0)
                                          ? (clamped / totalWidth)
                                          : 0.0;
                                      final hourDouble = ratio * 24.0;
                                      final hour = hourDouble.floor();
                                      final minute = ((hourDouble - hour) * 60)
                                          .round();
                                      final at = DateTime(
                                        currentDay.year,
                                        currentDay.month,
                                        currentDay.day,
                                        hour,
                                        minute,
                                      );

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              PlanningTeamDetailsPage(at: at),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      height: 35,
                                    ),
                                  ),

                                  for (final bar in dailyBars)
                                    PlanningBar(
                                      start: bar['start'],
                                      end: bar['end'],
                                      color:
                                          (bar['color'] as Color?) ??
                                          _barColorForType(
                                            context,
                                            bar['type'] as String?,
                                          ),
                                      isSubtle:
                                          true, // enable colored borders for all bars
                                      showLeftBorder:
                                          bar['isRealStart'] ?? true,
                                      showRightBorder: bar['isRealEnd'] ?? true,
                                      isAvailability:
                                          bar['type'] == 'availability',
                                      onTap: (at) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                PlanningTeamDetailsPage(at: at),
                                          ),
                                        );
                                      },
                                    ),

                                  // legend removed from Stack to avoid being clipped; rendered below the timeline
                                ],
                              ),
                            ),
                            // legend only on Sunday (last day) with 0h/6h/12h/18h/24h spaced evenly
                            if (index == daysOfWeek.length - 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: SizedBox(
                                  height: 16,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: const [
                                      Text(
                                        '0h',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        '6h',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        '12h',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        '18h',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        '24h',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Fonction helper pour convertir une couleur en shade400 (version plus douce)
Color _getShade400(Color color) {
  // Si c'est déjà un MaterialColor, utiliser shade400
  if (color is MaterialColor) {
    return color.shade400;
  }
  // Sinon, éclaircir la couleur en mélangeant avec du blanc
  return Color.lerp(color, Colors.white, 0.4) ?? color;
}
