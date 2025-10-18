import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';

// App-wide notifiers (centralized)
ValueNotifier<bool> isDarkModeNotifier = ValueNotifier(false);
ValueNotifier<bool> isUserAuthentifiedNotifier = ValueNotifier(false);
ValueNotifier<User?> userNotifier = ValueNotifier<User?>(null);

// Navigation / UI notifiers (moved from app-scoped datasource)
final ValueNotifier<int> selectedPageNotifier = ValueNotifier<int>(0);
final ValueNotifier<double> durationDaysNotifier = ValueNotifier<double>(7);
// Toggle used by Planning header and Home to switch between personal / centre view
final ValueNotifier<bool> stationViewNotifier = ValueNotifier<bool>(false);

// Team data change notifier - increment this value to trigger reload across the app
final ValueNotifier<int> teamDataChangedNotifier = ValueNotifier<int>(0);
