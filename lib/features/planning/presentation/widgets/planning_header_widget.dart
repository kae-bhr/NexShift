import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';

/// Reusable header used by PlanningPage and HomePage.
///
/// - Shows a switch (Personnel / Centre) bound to `stationViewNotifier`.
/// - Shows the week range with prev/next buttons and exposes week changes
///   through [onWeekChanged].
class PlanningHeader extends StatefulWidget {
  final DateTime? currentWeekStart;
  final ValueChanged<DateTime>? onWeekChanged;

  const PlanningHeader({super.key, this.currentWeekStart, this.onWeekChanged});

  @override
  State<PlanningHeader> createState() => _PlanningHeaderState();
}

class _PlanningHeaderState extends State<PlanningHeader> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = widget.currentWeekStart ?? _getStartOfWeek(DateTime.now());
  }

  static DateTime _getStartOfWeek(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  void _goToPreviousWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
    });
    widget.onWeekChanged?.call(_weekStart);
  }

  void _goToNextWeek() {
    setState(() {
      _weekStart = _weekStart.add(const Duration(days: 7));
    });
    widget.onWeekChanged?.call(_weekStart);
  }

  Future<void> _showWeekPicker() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Sélectionner une date',
      cancelText: 'Annuler',
      confirmText: 'Confirmer',
    );

    if (selectedDate != null && mounted) {
      final newWeekStart = _getStartOfWeek(selectedDate);
      setState(() {
        _weekStart = newWeekStart;
      });
      widget.onWeekChanged?.call(_weekStart);
    }
  }

  @override
  void didUpdateWidget(covariant PlanningHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentWeekStart != null &&
        widget.currentWeekStart != oldWidget.currentWeekStart) {
      setState(() {
        _weekStart = widget.currentWeekStart!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysOfWeek = List.generate(
      7,
      (i) => _weekStart.add(Duration(days: i)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: stationViewNotifier,
            builder: (context, stationView, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: () {
                          stationViewNotifier.value = false;
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.person,
                            color: !stationView
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: stationView,
                        activeColor: Theme.of(context).colorScheme.primary,
                        onChanged: (bool value) {
                          stationViewNotifier.value = value;
                        },
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () {
                          stationViewNotifier.value = true;
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.fire_truck,
                            color: stationView
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                            size: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  Icons.chevron_left,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: _goToPreviousWeek,
              ),
              GestureDetector(
                onTap: _showWeekPicker,
                child: Text(
                  "Semaine du ${DateFormat('d MMM', 'fr_FR').format(daysOfWeek.first)} au ${DateFormat('d MMM', 'fr_FR').format(daysOfWeek.last)}",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: Theme.of(context).textTheme.titleMedium!.fontSize,
                    fontFamily: null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: _goToNextWeek,
              ),
            ],
          ),
          const Divider(thickness: 1, height: 16),
        ],
      ),
    );
  }
}
