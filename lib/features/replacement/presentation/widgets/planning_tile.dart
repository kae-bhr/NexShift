import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';

/// Widget commun pour afficher la tuile d'astreinte avec sélection de dates
class PlanningTile extends StatelessWidget {
  final Planning planning;
  final DateTime? startDateTime;
  final DateTime? endDateTime;
  final VoidCallback? onTap;
  final String? errorMessage;

  /// Périodes non couvertes pour l'agent sélectionné (remplacements existants)
  final List<Map<String, DateTime>> uncoveredPeriods;

  const PlanningTile({
    super.key,
    required this.planning,
    this.startDateTime,
    this.endDateTime,
    this.onTap,
    this.errorMessage,
    this.uncoveredPeriods = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final hasError = errorMessage != null && errorMessage!.isNotEmpty;
    final isValid = !hasError && startDateTime != null && endDateTime != null;

    // Couleurs adaptatives thème clair/sombre
    final Color containerColor;
    final Color borderColor;
    final Color accentColor;

    if (hasError) {
      containerColor = isDark
          ? Colors.red.withValues(alpha: 0.12)
          : Colors.red.shade50;
      borderColor = isDark
          ? Colors.red.withValues(alpha: 0.40)
          : Colors.red.shade300;
      accentColor = isDark ? Colors.red.shade300 : Colors.red.shade700;
    } else if (isValid) {
      containerColor = isDark
          ? Colors.green.withValues(alpha: 0.10)
          : Colors.green.shade50;
      borderColor = isDark
          ? Colors.green.withValues(alpha: 0.35)
          : Colors.green.shade300;
      accentColor = isDark ? Colors.green.shade300 : Colors.green.shade700;
    } else {
      containerColor = isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3);
      borderColor = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3);
      accentColor = Theme.of(context).colorScheme.primary;
    }

    final subtleTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Astreinte ${planning.team}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: subtleTextColor,
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Plage de l'astreinte
            _DateBlock(
              label: 'Astreinte',
              start: dateFormat.format(planning.startTime),
              end: dateFormat.format(planning.endTime),
              textColor: subtleTextColor,
              isSubtle: true,
            ),

            // Plage de remplacement sélectionnée
            if (startDateTime != null && endDateTime != null) ...[
              const SizedBox(height: 8),
              _DateBlock(
                label: 'Remplacement',
                start: dateFormat.format(startDateTime!),
                end: dateFormat.format(endDateTime!),
                textColor: accentColor,
                isSubtle: false,
              ),
            ],

            // Message d'erreur
            if (hasError) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.red.withValues(alpha: 0.15)
                      : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 14,
                        color: isDark ? Colors.red.shade300 : Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Périodes non couvertes
            if (uncoveredPeriods.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.withValues(alpha: 0.12)
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.orange.withValues(alpha: 0.30)
                        : Colors.orange.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Périodes à couvrir :',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.orange.shade300
                            : Colors.orange.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...uncoveredPeriods.map((g) {
                      final s = g['start']!;
                      final e = g['end']!;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 14,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.orange.shade400
                                    : Colors.orange.shade400,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${dateFormat.format(s)} → ${dateFormat.format(e)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.orange.shade300
                                      : Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  final String label;
  final String start;
  final String end;
  final Color textColor;
  final bool isSubtle;

  const _DateBlock({
    required this.label,
    required this.start,
    required this.end,
    required this.textColor,
    required this.isSubtle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textColor.withValues(alpha: isSubtle ? 0.7 : 1.0),
            ),
          ),
        ),
        Expanded(
          child: Text(
            '$start → $end',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSubtle ? FontWeight.w400 : FontWeight.w600,
              color: textColor,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Service pour gérer la logique de sélection des dates
class DateTimePickerService {
  /// Affiche les pickers de date et heure
  static Future<DateTime?> pickDateTime({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (date == null) return null;

    if (!context.mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  /// Valide les dates de remplacement par rapport à l'astreinte
  static String? validateReplacementDates({
    required DateTime? startDateTime,
    required DateTime? endDateTime,
    required Planning planning,
    List<dynamic>? existingRequests,
  }) {
    if (startDateTime == null || endDateTime == null) {
      return null;
    }

    if (startDateTime.isBefore(DateTime.now())) {
      return "La date de début ne peut pas être dans le passé.";
    }

    if (endDateTime.isBefore(startDateTime)) {
      return "L'heure de fin ne peut pas être antérieure à l'heure de début.";
    }

    if (startDateTime.isBefore(planning.startTime)) {
      return "La date de début ne peut pas précéder celle de l'astreinte.";
    }

    if (endDateTime.isAfter(planning.endTime)) {
      return "La date de fin ne peut pas dépasser celle de l'astreinte.";
    }

    if (existingRequests != null) {
      for (final request in existingRequests) {
        final requestStart = request['startTime'] is DateTime
            ? request['startTime'] as DateTime
            : (request['startTime'] as dynamic).toDate();
        final requestEnd = request['endTime'] is DateTime
            ? request['endTime'] as DateTime
            : (request['endTime'] as dynamic).toDate();

        final overlapStart = requestStart.isBefore(endDateTime);
        final overlapEnd = requestEnd.isAfter(startDateTime);

        if (overlapStart && overlapEnd) {
          return "Vous avez déjà une demande de remplacement en cours sur cette période.";
        }
      }
    }

    return null;
  }
}
