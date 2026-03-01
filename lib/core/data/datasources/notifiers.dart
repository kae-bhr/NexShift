import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/services/subscription_service.dart';
import 'package:nexshift_app/features/planning/presentation/widgets/view_mode.dart';

// Custom ValueNotifier avec logs pour debugging
class LoggingBoolNotifier extends ValueNotifier<bool> {
  final String name;

  LoggingBoolNotifier(super.value, this.name);

  @override
  set value(bool newValue) {
    debugPrint('🔔 [NOTIFIER] $name changed: ${super.value} -> $newValue');
    super.value = newValue;
  }
}

class LoggingUserNotifier extends ValueNotifier<User?> {
  LoggingUserNotifier(super.value);

  @override
  set value(User? newValue) {
    final oldStr = super.value != null ? '${super.value!.firstName} ${super.value!.lastName} (${super.value!.id})' : 'NULL';
    final newStr = newValue != null ? '${newValue.firstName} ${newValue.lastName} (${newValue.id})' : 'NULL';
    debugPrint('🔔 [NOTIFIER] userNotifier changed: $oldStr -> $newStr');
    super.value = newValue;
  }
}

// App-wide notifiers (centralized)
ValueNotifier<bool> isDarkModeNotifier = LoggingBoolNotifier(false, 'isDarkModeNotifier');
ValueNotifier<bool> isUserAuthentifiedNotifier = LoggingBoolNotifier(false, 'isUserAuthentifiedNotifier');
ValueNotifier<User?> userNotifier = LoggingUserNotifier(null);

// Navigation / UI notifiers (moved from app-scoped datasource)
final ValueNotifier<int> selectedPageNotifier = ValueNotifier<int>(0);
final ValueNotifier<double> durationDaysNotifier = ValueNotifier<double>(7);
// Toggle used by Planning header and Home to switch between personal / centre view
final ValueNotifier<bool> stationViewNotifier = ValueNotifier<bool>(false);

// Team data change notifier - increment this value to trigger reload across the app
final ValueNotifier<int> teamDataChangedNotifier = ValueNotifier<int>(0);

// Subscription status notifier - état de l'abonnement de la caserne
final ValueNotifier<SubscriptionStatus> subscriptionStatusNotifier =
    ValueNotifier<SubscriptionStatus>(SubscriptionStatus.unknown);

// Notifiers partagés entre HomePage et PlanningPage (persistance inter-pages)
final ValueNotifier<ViewMode> viewModeNotifier = ValueNotifier<ViewMode>(ViewMode.week);
final ValueNotifier<DateTime> currentMonthNotifier = ValueNotifier<DateTime>(
  DateTime(DateTime.now().year, DateTime.now().month),
);
final ValueNotifier<String?> selectedTeamNotifier = ValueNotifier<String?>(null);

DateTime _getStartOfCurrentWeek() {
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day);
}

final ValueNotifier<DateTime> currentWeekStartNotifier =
    ValueNotifier<DateTime>(_getStartOfCurrentWeek());

// Indique qu'une tentative de restauration de session est en cours au démarrage.
// Démarre à true, passe à false une fois la vérification terminée (succès ou non).
// Utilisé par WelcomePage pour afficher un indicateur de chargement et bloquer
// les boutons pendant la réauthentification automatique.
final ValueNotifier<bool> isRestoringSessionNotifier = ValueNotifier<bool>(true);
