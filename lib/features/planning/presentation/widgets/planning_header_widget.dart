import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Reusable header used by PlanningPage and HomePage.
///
/// - Shows a segmented toggle (Personnel / Centre) bound to `stationViewNotifier`.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented toggle Personnel / Centre
          ValueListenableBuilder<bool>(
            valueListenable: stationViewNotifier,
            builder: (context, stationView, _) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SegmentButton(
                          icon: Icons.person_rounded,
                          label: 'Personnel',
                          isSelected: !stationView,
                          onTap: () => stationViewNotifier.value = false,
                        ),
                        _SegmentButton(
                          icon: Icons.fire_truck_rounded,
                          label: 'Centre',
                          isSelected: stationView,
                          onTap: () => stationViewNotifier.value = true,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // Week navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _NavArrowButton(
                icon: Icons.chevron_left_rounded,
                onTap: _goToPreviousWeek,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _showWeekPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? KColors.appNameColor.withValues(alpha: 0.15)
                        : KColors.appNameColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: KColors.appNameColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${DateFormat('d MMM', 'fr_FR').format(daysOfWeek.first)} - ${DateFormat('d MMM', 'fr_FR').format(daysOfWeek.last)}",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _NavArrowButton(
                icon: Icons.chevron_right_rounded,
                onTap: _goToNextWeek,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A single segment in the toggle button
class _SegmentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? KColors.appNameColor.withValues(alpha: 0.3)
                  : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isDark ? Colors.black : Colors.black)
                        .withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? KColors.appNameColor
                  : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? KColors.appNameColor
                    : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small circular arrow button for week navigation
class _NavArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.shade200,
            ),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 22,
          ),
        ),
      ),
    );
  }
}
