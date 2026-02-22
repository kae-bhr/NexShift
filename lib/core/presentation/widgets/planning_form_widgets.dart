import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Card affichant les infos de l'astreinte en lecture seule (équipe, début, fin).
/// Widget partagé entre replacement_page, shift_exchange_page et skill_search_page.
class SharedPlanningDetailCard extends StatelessWidget {
  final Planning planning;

  const SharedPlanningDetailCard({super.key, required this.planning});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = KColors.appNameColor;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    final duration = planning.endTime.difference(planning.startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final durationLabel = minutes > 0
        ? '${hours}h${minutes.toString().padLeft(2, '0')}'
        : '${hours}h';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withValues(alpha: isDark ? 0.12 : 0.07),
            primary.withValues(alpha: isDark ? 0.05 : 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primary.withValues(alpha: isDark ? 0.28 : 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Équipe + durée
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 16, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Équipe ${planning.team}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  durationLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Début
          Row(
            children: [
              Icon(
                Icons.play_circle_outline_rounded,
                size: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
              ),
              const SizedBox(width: 7),
              Text(
                'Début : ',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                ),
              ),
              Text(
                fmt.format(planning.startTime),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey.shade200 : Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // Fin
          Row(
            children: [
              Icon(
                Icons.stop_circle_outlined,
                size: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
              ),
              const SizedBox(width: 7),
              Text(
                'Fin : ',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                ),
              ),
              Text(
                fmt.format(planning.endTime),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey.shade200 : Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Card de sélection de la période de remplacement avec pickers inline.
/// Change de couleur selon l'état : neutre → vert (valide) → rouge (erreur).
/// Widget partagé entre replacement_page et skill_search_page.
class SharedReplacementPeriodCard extends StatelessWidget {
  final DateTime? startDateTime;
  final DateTime? endDateTime;
  final String? errorMessage;
  final List<Map<String, DateTime>> uncoveredPeriods;
  final Future<bool> Function() onPickStart;
  final Future<bool> Function() onPickEnd;

  const SharedReplacementPeriodCard({
    super.key,
    required this.startDateTime,
    required this.endDateTime,
    required this.errorMessage,
    required this.uncoveredPeriods,
    required this.onPickStart,
    required this.onPickEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    final hasError = errorMessage != null && errorMessage!.isNotEmpty;
    final isValid = !hasError && startDateTime != null && endDateTime != null;

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
          : Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.3);
      borderColor = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3);
      accentColor = Theme.of(context).colorScheme.primary;
    }

    final subtleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Picker début
          _InlineDatePicker(
            label: 'Début',
            dateTime: startDateTime,
            placeholder: 'Sélectionner...',
            fmt: fmt,
            accentColor: accentColor,
            subtleColor: subtleColor,
            onTap: onPickStart,
          ),
          const SizedBox(height: 4),
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 4),
          // Picker fin
          _InlineDatePicker(
            label: 'Fin',
            dateTime: endDateTime,
            placeholder: 'Sélectionner...',
            fmt: fmt,
            accentColor: accentColor,
            subtleColor: subtleColor,
            onTap: onPickEnd,
          ),

          // Message d'erreur
          if (hasError) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                ),
                const SizedBox(width: 7),
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
          ],

          // Périodes non couvertes
          if (uncoveredPeriods.isNotEmpty) ...[
            const SizedBox(height: 10),
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
                              color: Colors.orange.shade400,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${fmt.format(s)} → ${fmt.format(e)}',
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
    );
  }
}

/// Ligne de sélection de date/heure inline.
class _InlineDatePicker extends StatelessWidget {
  final String label;
  final DateTime? dateTime;
  final String placeholder;
  final DateFormat fmt;
  final Color accentColor;
  final Color subtleColor;
  final Future<bool> Function() onTap;

  const _InlineDatePicker({
    required this.label,
    required this.dateTime,
    required this.placeholder,
    required this.fmt,
    required this.accentColor,
    required this.subtleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSet = dateTime != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: subtleColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSet
                        ? accentColor.withValues(alpha: 0.4)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.10)
                              : Colors.grey.withValues(alpha: 0.25)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: isSet ? accentColor : subtleColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isSet ? fmt.format(dateTime!) : placeholder,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                          color: isSet ? accentColor : subtleColor,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.edit_rounded,
                      size: 13,
                      color: subtleColor.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
