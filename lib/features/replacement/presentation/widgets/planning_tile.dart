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

  /// Determine if text should be dark or light based on background luminance
  Color _adaptiveTextColor(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final hasError = errorMessage != null && errorMessage!.isNotEmpty;
    final isValid = !hasError && startDateTime != null && endDateTime != null;

    // Compute actual background color to determine text color
    final backgroundColor = hasError
        ? Colors.red.shade50
        : isValid
        ? Colors.green.shade50
        : Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3);

    final adaptiveTextColor = _adaptiveTextColor(backgroundColor);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasError
              ? Colors.red.shade50
              : isValid
              ? Colors.green.shade50
              : Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasError
                ? Colors.red.shade300
                : isValid
                ? Colors.green.shade300
                : Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: hasError
                      ? Colors.red
                      : isValid
                      ? Colors.green.shade700
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Astreinte ${planning.team}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: hasError
                          ? Colors.red.shade700
                          : isValid
                          ? Colors.green.shade700
                          : null,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.edit, size: 16, color: Colors.black54),
              ],
            ),
            const SizedBox(height: 8),
            _buildDateRow(
              context,
              'Astreinte',
              dateFormat.format(planning.startTime),
              dateFormat.format(planning.endTime),
              isSubtitle: true,
              adaptiveTextColor: adaptiveTextColor,
            ),
            if (startDateTime != null && endDateTime != null) ...[
              const SizedBox(height: 8),
              _buildDateRow(
                context,
                'Remplacement',
                dateFormat.format(startDateTime!),
                dateFormat.format(endDateTime!),
                isHighlighted: true,
                hasError: hasError,
                isValid: isValid,
                adaptiveTextColor: adaptiveTextColor,
              ),
            ],
            if (hasError) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Périodes non couvertes (remplacements existants qui réduisent la présence)
            if (uncoveredPeriods.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Périodes à couvrir :',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...uncoveredPeriods.map((g) {
                      final s = g['start']!;
                      final e = g['end']!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${dateFormat.format(s)} → ${dateFormat.format(e)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade800,
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

  Widget _buildDateRow(
    BuildContext context,
    String label,
    String startStr,
    String endStr, {
    bool isSubtitle = false,
    bool isHighlighted = false,
    bool hasError = false,
    bool isValid = false,
    Color? adaptiveTextColor,
  }) {
    // Utiliser la même taille de police pour l'astreinte et le remplacement
    final textStyle = Theme.of(context).textTheme.bodySmall;

    final color = hasError
        ? Colors.red.shade700
        : isValid
        ? Colors.green.shade700
        : isHighlighted
        ? Theme.of(context).colorScheme.primary
        : (adaptiveTextColor ?? Colors.black);

    return Text(
      '$label : $startStr → $endStr',
      style: textStyle?.copyWith(
        fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
        color: color,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
      return null; // Pas encore de dates sélectionnées
    }

    // Vérifier que la date de début n'est pas dans le passé
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

    // Vérifier le chevauchement avec des demandes existantes
    if (existingRequests != null) {
      for (final request in existingRequests) {
        // Extraire les dates de la demande existante
        final requestStart = request['startTime'] is DateTime
            ? request['startTime'] as DateTime
            : (request['startTime'] as dynamic).toDate();
        final requestEnd = request['endTime'] is DateTime
            ? request['endTime'] as DateTime
            : (request['endTime'] as dynamic).toDate();

        // Vérifier le chevauchement
        final overlapStart = requestStart.isBefore(endDateTime);
        final overlapEnd = requestEnd.isAfter(startDateTime);

        if (overlapStart && overlapEnd) {
          return "Vous avez déjà une demande de remplacement en cours sur cette période.";
        }
      }
    }

    return null; // Tout est valide
  }
}
