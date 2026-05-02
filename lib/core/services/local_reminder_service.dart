import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
import 'package:nexshift_app/core/data/models/planning_model.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/planning_repository.dart';
import 'package:timezone/timezone.dart' as tz;

/// Résultat de filtrage d'une astreinte active pour un agent.
class _ActiveShift {
  final bool isReplacement;
  _ActiveShift({required this.isReplacement});
}

/// Service de rappel quotidien d'astreinte schedulé localement.
/// Remplace la Cloud Function `sendDailyShiftReminder` qui souffrait d'une
/// heure d'envoi imprécise et d'horaires erronés (shift complet vs horaires
/// réels de l'agent).
///
/// Au démarrage/resume, charge les astreintes des 7 prochains jours et
/// programme autant de notifications one-shot que de jours avec une astreinte
/// active. Aucune répétition native OS — chaque notification est ciblée.
class LocalReminderService {
  static final LocalReminderService _instance = LocalReminderService._internal();
  factory LocalReminderService() => _instance;
  LocalReminderService._internal();

  // IDs 42 à 48 (un par jour sur 7 jours)
  static const int _kBaseNotificationId = 42;
  static const int _kWindowDays = 7;
  static const String _kChannelId = 'nexshift_daily_reminder';
  static const String _kChannelName = 'Rappel quotidien';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const NotificationDetails _kNotificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _kChannelId,
      _kChannelName,
      channelDescription: 'Rappel quotidien des astreintes à venir',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    ),
  );

  /// Annule les 7 slots de rappel quotidien.
  Future<void> cancelReminder() async {
    for (int i = 0; i < _kWindowDays; i++) {
      await _plugin.cancel(_kBaseNotificationId + i);
    }
    debugPrint('🔔 [LocalReminder] Rappels quotidiens annulés ($_kWindowDays slots)');
  }

  /// Annule puis replanifie les rappels quotidiens selon les préférences de [user].
  Future<void> reschedule(User user) async {
    await cancelReminder();
    await scheduleReminder(user);
  }

  /// Charge les astreintes des 7 prochains jours et programme une notification
  /// one-shot pour chaque jour où [user] a une astreinte active.
  ///
  /// Si aucune astreinte n'est trouvée sur la fenêtre, aucune notification
  /// n'est schedulée.
  Future<void> scheduleReminder(User user) async {
    if (!user.personalAlertEnabled) {
      debugPrint('🔔 [LocalReminder] Rappel désactivé pour ${user.id}');
      return;
    }

    final sdisId = SDISContext().currentSDISId;
    if (sdisId == null || sdisId.isEmpty || user.station.isEmpty) {
      debugPrint('🔔 [LocalReminder] Contexte SDIS/station manquant — rappel non schedulé');
      return;
    }

    try {
      // Choisir le mode selon la permission disponible
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final canExact = await androidPlugin?.canScheduleExactNotifications() ?? true;
      final scheduleMode = canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexact;
      debugPrint('🔔 [LocalReminder] Mode scheduling : ${canExact ? "exact" : "inexact (permission manquante)"}');

      final now = DateTime.now();
      final windowEnd = now.add(Duration(days: _kWindowDays));

      // Un seul appel Firestore pour toute la fenêtre de 7 jours
      final plannings = await PlanningRepository().getByStationInRange(
        user.station,
        now,
        windowEnd,
      );

      final paris = tz.getLocation('Europe/Paris');
      int scheduled = 0;

      for (int dayOffset = 0; dayOffset < _kWindowDays; dayOffset++) {
        final dayStart = DateTime(now.year, now.month, now.day)
            .add(Duration(days: dayOffset));
        final dayEnd = dayStart.add(const Duration(days: 1));

        // Plannings qui chevauchent ce jour
        final dayPlannings = plannings
            .where((p) => p.startTime.isBefore(dayEnd) && p.endTime.isAfter(dayStart))
            .toList();

        final activeShifts = _computeActiveShiftsForUser(dayPlannings, user.id);
        if (activeShifts.isEmpty) continue;

        final scheduledDate = _instanceOfTimeOnDay(user.personalAlertHour, user.personalAlertMinute, dayStart, paris);

        // Ignorer si l'heure est déjà passée
        if (scheduledDate.isBefore(tz.TZDateTime.now(paris))) {
          debugPrint(
            '🔔 [LocalReminder] Slot J+$dayOffset ignoré (heure passée) : '
            '${scheduledDate.hour.toString().padLeft(2,'0')}:${scheduledDate.minute.toString().padLeft(2,'0')} '
            'le ${scheduledDate.day}/${scheduledDate.month}',
          );
          continue;
        }

        final replacingCount = activeShifts.where((s) => s.isReplacement).length;
        final baseCount = activeShifts.length - replacingCount;
        final body = _buildBody(baseCount, replacingCount);

        try {
          await _plugin.zonedSchedule(
            _kBaseNotificationId + dayOffset,
            '⏰ Astreintes à venir',
            body,
            scheduledDate,
            _kNotificationDetails,
            androidScheduleMode: scheduleMode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        } catch (slotError) {
          if (slotError.toString().contains('exact_alarms_not_permitted')) {
            // Retry en inexact si la permission exacte a été révoquée entre-temps
            await _plugin.zonedSchedule(
              _kBaseNotificationId + dayOffset,
              '⏰ Astreintes à venir',
              body,
              scheduledDate,
              _kNotificationDetails,
              androidScheduleMode: AndroidScheduleMode.inexact,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
            debugPrint('🔔 [LocalReminder] Slot ${_kBaseNotificationId + dayOffset} replanifié en mode inexact');
          } else {
            rethrow;
          }
        }
        debugPrint(
          '🔔 [LocalReminder] Slot ${_kBaseNotificationId + dayOffset} programmé : '
          '${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2,'0')}-${scheduledDate.day.toString().padLeft(2,'0')} '
          '${scheduledDate.hour.toString().padLeft(2,'0')}:${scheduledDate.minute.toString().padLeft(2,'0')} Europe/Paris — $body',
        );
        scheduled++;
      }

      debugPrint(
        '🔔 [LocalReminder] $scheduled rappel(s) one-shot programmé(s) '
        'sur $_kWindowDays jours pour ${user.id}',
      );
    } catch (e) {
      debugPrint('🔔 [LocalReminder] Erreur lors du scheduling : $e');
    }
  }

  /// Retourne le [TZDateTime] correspondant à [hour]:[minute] Europe/Paris pour le [day] donné.
  tz.TZDateTime _instanceOfTimeOnDay(int hour, int minute, DateTime day, tz.Location location) {
    return tz.TZDateTime(location, day.year, day.month, day.day, hour, minute);
  }

  String _buildBody(int baseCount, int replacingCount) {
    if (baseCount > 0 && replacingCount > 0) {
      return '$baseCount astreinte(s) + $replacingCount remplacement(s) dans les prochaines 24h';
    } else if (replacingCount > 0) {
      return '$replacingCount remplacement(s) dans les prochaines 24h';
    } else {
      return '$baseCount astreinte(s) dans les prochaines 24h';
    }
  }

  /// Port Dart de la logique de filtrage de `alerts.js` (lignes 88-117).
  ///
  /// Retourne la liste des astreintes actives pour [userId] parmi [plannings] :
  /// - Cas 1 : agent de base non entièrement remplacé
  /// - Cas 2 : agent remplaçant
  List<_ActiveShift> _computeActiveShiftsForUser(
    List<Planning> plannings,
    String userId,
  ) {
    final result = <_ActiveShift>[];

    for (final planning in plannings) {
      final agents = planning.agents;

      // Cas 2 : l'agent est remplaçant dans ce planning
      final isReplacing = agents.any(
        (a) => a.agentId == userId && a.replacedAgentId != null,
      );
      if (isReplacing) {
        result.add(_ActiveShift(isReplacement: true));
        continue;
      }

      // Cas 1 : l'agent est agent de base (sans replacedAgentId)
      final baseEntries = agents.where(
        (a) => a.agentId == userId && a.replacedAgentId == null,
      ).toList();
      if (baseEntries.isEmpty) continue;

      final baseEntry = baseEntries.first;

      // Vérifier si l'agent de base est entièrement remplacé
      final replacementIntervals = agents
          .where((a) => a.replacedAgentId == userId)
          .map((a) => (start: a.start, end: a.end))
          .toList();

      if (replacementIntervals.isEmpty) {
        // Pas du tout remplacé → à notifier
        result.add(_ActiveShift(isReplacement: false));
      } else if (!_checkIfFullyCovered(
        baseEntry.start,
        baseEntry.end,
        replacementIntervals,
      )) {
        // Partiellement remplacé → encore de garde
        result.add(_ActiveShift(isReplacement: false));
      }
      // Si entièrement remplacé → ne pas inclure
    }

    return result;
  }

  /// Port Dart de `planning-utils.js` `checkIfFullyCovered`.
  ///
  /// Vérifie si [intervals] couvre complètement la période [targetStart, targetEnd]
  /// en fusionnant les intervalles chevauchants et en appliquant une tolérance
  /// d'une minute.
  bool _checkIfFullyCovered(
    DateTime targetStart,
    DateTime targetEnd,
    List<({DateTime start, DateTime end})> intervals,
  ) {
    if (intervals.isEmpty) return false;

    final sorted = [...intervals]
      ..sort((a, b) => a.start.compareTo(b.start));

    // Fusionner les intervalles chevauchants ou contigus
    final merged = <({DateTime start, DateTime end})>[];
    var current = sorted.first;
    for (int i = 1; i < sorted.length; i++) {
      final next = sorted[i];
      if (!next.start.isAfter(current.end)) {
        current = (
          start: current.start.isBefore(next.start) ? current.start : next.start,
          end: current.end.isAfter(next.end) ? current.end : next.end,
        );
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);

    // Vérifier la couverture avec tolérance d'1 minute
    const tolerance = Duration(minutes: 1);
    for (final interval in merged) {
      if (!interval.start.subtract(tolerance).isAfter(targetStart) &&
          !interval.end.add(tolerance).isBefore(targetEnd)) {
        return true;
      }
    }
    return false;
  }
}
