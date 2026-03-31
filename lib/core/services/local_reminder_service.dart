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
/// Le rappel est schedulé via [zonedSchedule] à l'heure exacte configurée
/// par l'utilisateur et utilise les horaires [PlanningAgent.start/end].
class LocalReminderService {
  static final LocalReminderService _instance = LocalReminderService._internal();
  factory LocalReminderService() => _instance;
  LocalReminderService._internal();

  static const int _kNotificationId = 42;
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

  /// Annule le rappel quotidien schedulé.
  Future<void> cancelReminder() async {
    await _plugin.cancel(_kNotificationId);
    debugPrint('🔔 [LocalReminder] Rappel quotidien annulé');
  }

  /// Annule puis replanifie le rappel quotidien selon les préférences de [user].
  Future<void> reschedule(User user) async {
    await cancelReminder();
    await scheduleReminder(user);
  }

  /// Planifie le rappel quotidien si [user.personalAlertEnabled] est vrai
  /// et que l'utilisateur a des astreintes dans les prochaines 24h.
  ///
  /// Si aucune astreinte n'est trouvée, aucune notification n'est schedulée.
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
      final now = DateTime.now();
      final windowEnd = now.add(const Duration(hours: 24));

      final plannings = await PlanningRepository().getByStationInRange(
        user.station,
        now,
        windowEnd,
      );

      final activeShifts = _computeActiveShiftsForUser(plannings, user.id);

      if (activeShifts.isEmpty) {
        debugPrint('🔔 [LocalReminder] Aucune astreinte dans les 24h — pas de rappel');
        return;
      }

      final replacingCount = activeShifts.where((s) => s.isReplacement).length;
      final baseCount = activeShifts.length - replacingCount;

      final String body;
      if (baseCount > 0 && replacingCount > 0) {
        body = '$baseCount astreinte(s) + $replacingCount remplacement(s) dans les prochaines 24h';
      } else if (replacingCount > 0) {
        body = '$replacingCount remplacement(s) dans les prochaines 24h';
      } else {
        body = '$baseCount astreinte(s) dans les prochaines 24h';
      }

      final scheduledDate = _nextInstanceOfHour(user.personalAlertHour);

      await _plugin.zonedSchedule(
        _kNotificationId,
        '⏰ Astreintes à venir',
        body,
        scheduledDate,
        _kNotificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      debugPrint(
        '🔔 [LocalReminder] Rappel schedulé pour ${user.id} à '
        '${user.personalAlertHour}h — $body',
      );
    } catch (e) {
      debugPrint('🔔 [LocalReminder] Erreur lors du scheduling : $e');
    }
  }

  /// Retourne le prochain [TZDateTime] correspondant à [hour]:00 Europe/Paris.
  /// Si cette heure est déjà passée aujourd'hui, retourne demain à la même heure.
  tz.TZDateTime _nextInstanceOfHour(int hour) {
    final paris = tz.getLocation('Europe/Paris');
    final now = tz.TZDateTime.now(paris);
    var scheduled = tz.TZDateTime(paris, now.year, now.month, now.day, hour);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
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
