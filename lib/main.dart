import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_storage/get_storage.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:nexshift_app/config/theme.dart';
import 'package:nexshift_app/config/environment.dart';
import 'package:nexshift_app/config/environment_banner.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/presentation/widgets/value_listenable_builder_widget.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/services/firebase_auth_service.dart';
import 'package:nexshift_app/core/services/push_notification_service.dart';
import 'package:nexshift_app/core/services/debug_logger.dart';
import 'package:nexshift_app/core/services/connectivity_service.dart';
import 'package:nexshift_app/core/services/log_service.dart';
import 'package:nexshift_app/core/presentation/pages/offline_page.dart';
import 'package:nexshift_app/core/presentation/pages/maintenance_page.dart';
import 'package:nexshift_app/core/presentation/pages/subscription_expired_page.dart';
import 'package:nexshift_app/core/services/maintenance_service.dart';
import 'package:nexshift_app/core/services/subscription_service.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/widget_tree.dart';
import 'package:nexshift_app/features/auth/presentation/pages/welcome_page.dart';
import 'package:nexshift_app/features/auth/presentation/pages/profile_completion_page.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/replacement_request_dialog.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/replacement_requests_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexshift_app/firebase_options.dart';

// Global key for navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize DebugLogger FIRST to capture all logs
  DebugLogger();
  debugPrint('🚀 Application starting...');
  debugPrint('🌍 Environment: ${Environment.name}');

  // Initialize Log Service
  try {
    await LogService().initialize();
    debugPrint('Log service initialized successfully');
  } catch (e) {
    debugPrint('Error initializing log service: $e');
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Firebase (vérifie si déjà initialisé pour éviter duplicate-app)
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('Firebase initialized successfully');
      await LogService().log('Firebase initialized', level: LogLevel.info);
    } else {
      debugPrint('Firebase already initialized by native plugin');
      await LogService().log(
        'Firebase already initialized',
        level: LogLevel.info,
      );
    }
  } catch (e) {
    // Sur iOS, Firebase peut être initialisé par le plugin natif avant Dart
    // L'erreur duplicate-app est normale et peut être ignorée
    final errorStr = e.toString();
    if (errorStr.contains('duplicate-app')) {
      debugPrint('Firebase already initialized by iOS plugin - OK');
      await LogService().log(
        'Firebase ready (native init)',
        level: LogLevel.info,
      );
    } else {
      debugPrint('Error initializing Firebase: $e');
      await LogService().log(
        'Firebase initialization error: $e',
        level: LogLevel.error,
      );
    }
  }

  // Initialize Push Notifications
  try {
    final pushNotificationService = PushNotificationService();
    await pushNotificationService.initialize();

    // Set up notification tap handler
    pushNotificationService.onNotificationTap = (data) {
      debugPrint('📱 Notification tapped with data: $data');
      LogService().log('Notification tapped: $data', level: LogLevel.info);
      _handleNotificationTap(data);
    };

    debugPrint('Push notifications initialized successfully');
    await LogService().log(
      'Push notifications initialized',
      level: LogLevel.info,
    );
  } catch (e) {
    debugPrint('Error initializing push notifications: $e');
    await LogService().log(
      'Push notifications error: $e',
      level: LogLevel.error,
    );
  }

  try {
    await GetStorage.init();
  } catch (e) {
    // En cas d'erreur (ex: path_provider non prêt sur simulateur)
    debugPrint('Error initializing GetStorage: $e');
    await LogService().log(
      'GetStorage initialization error: $e',
      level: LogLevel.error,
    );
  }

  runApp(const NexShift());
}

/// Handle notification tap and navigate to appropriate page
void _handleNotificationTap(Map<String, dynamic> data) {
  debugPrint('🔔 Handling notification tap: $data');

  final type = data['type'];
  final context = navigatorKey.currentContext;

  if (context == null) {
    debugPrint('⚠️ No navigation context available');
    return;
  }

  final currentUserId = userNotifier.value?.id;
  if (currentUserId == null) {
    debugPrint('⚠️ No current user');
    return;
  }

  switch (type) {
    case 'replacement_request':
      // Notification de recherche de remplaçant : ouvrir le dialog
      final requestId = data['requestId'];
      if (requestId == null) {
        debugPrint('⚠️ No requestId in notification data');
        return;
      }

      // Récupérer le stationId depuis les données de notification ou depuis l'utilisateur courant
      final stationId = data['station'] ?? userNotifier.value?.station;
      if (stationId == null) {
        debugPrint('⚠️ No station available for replacement request');
        return;
      }

      showReplacementRequestDialog(
        context,
        requestId: requestId,
        currentUserId: currentUserId,
        stationId: stationId,
      );
      break;

    case 'manual_replacement_proposal':
    case 'replacement_found':
    case 'replacement_assigned':
    case 'replacement_completed':
    case 'replacement_completed_chief':
      // Notifications de confirmation : ouvrir la liste des remplacements
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const ReplacementRequestsListPage(),
        ),
      );
      break;

    default:
      debugPrint('⚠️ Unknown notification type: $type');
      break;
  }
}

class NexShift extends StatefulWidget {
  const NexShift({super.key});

  @override
  State<NexShift> createState() => _NexShiftState();
}

class _NexShiftState extends State<NexShift> {
  final _authService = FirebaseAuthService();
  final _pushNotificationService = PushNotificationService();
  final _connectivityService = ConnectivityService();
  final _maintenanceService = MaintenanceService();

  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    initThemeMode();
    _checkAuthState();
    _startConnectivityMonitoring();
    _maintenanceService.startListening();
  }

  /// Démarre la surveillance de la connectivité
  void _startConnectivityMonitoring() {
    _connectivityService.startMonitoring();
    _connectivityService.connectivityStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
    // État initial
    setState(() {
      _isOnline = _connectivityService.isOnline;
    });
  }

  @override
  void dispose() {
    _connectivityService.stopMonitoring();
    _maintenanceService.stopListening();
    super.dispose();
  }

  void initThemeMode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool? themeModeStored = prefs.getBool(KConstants.themeModeKey);
    isDarkModeNotifier.value = themeModeStored ?? false;
  }

  /// Vérifie l'état d'authentification Firebase au démarrage
  void _checkAuthState() async {
    debugPrint('🟡 [AUTH_LISTENER] Setting up authStateChanges listener');
    // Écouter les changements d'état d'authentification
    _authService.authStateChanges.listen((firebaseUser) async {
      debugPrint('🟡 [AUTH_LISTENER] ========== AUTH STATE CHANGED ==========');
      if (firebaseUser != null) {
        debugPrint(
          '🟡 [AUTH_LISTENER] User authenticated: ${firebaseUser.email}',
        );
        debugPrint(
          '🟡 [AUTH_LISTENER] Current isUserAuthentifiedNotifier: ${isUserAuthentifiedNotifier.value}',
        );
        debugPrint(
          '🟡 [AUTH_LISTENER] Current userNotifier: ${userNotifier.value != null ? '${userNotifier.value!.firstName} ${userNotifier.value!.lastName} (${userNotifier.value!.id})' : 'NULL'}',
        );

        // IMPORTANT: Ne pas mettre à jour isUserAuthentifiedNotifier ici
        // pour éviter une navigation automatique pendant le processus de login
        // multi-stations. EnterApp.build() gérera la navigation après
        // la sélection de station.

        // Extraire userId et stationId de l'email Firebase
        // Format: sdisId_matricule@nexshift.app ou sdisId_matricule_station@nexshift.app
        final email = firebaseUser.email;
        if (email != null && email.endsWith('@nexshift.app')) {
          final parts = email.split('@')[0].split('_');
          if (parts.length >= 2) {
            final sdisId = parts[0];
            final matricule = parts[1];
            final stationId = parts.length > 2 ? parts[2] : null;

            debugPrint(
              '🟡 [AUTH_LISTENER] Extracted from email: sdisId=$sdisId, matricule=$matricule, station=$stationId',
            );

            // Attendre que userNotifier soit mis à jour avec le bon utilisateur
            // pour obtenir le stationId si nécessaire
            debugPrint(
              '🟡 [AUTH_LISTENER] Waiting 500ms for userNotifier update...',
            );
            await Future.delayed(Duration(milliseconds: 500));
            final currentUser = userNotifier.value;
            debugPrint(
              '🟡 [AUTH_LISTENER] After wait, userNotifier: ${currentUser != null ? '${currentUser.firstName} ${currentUser.lastName} (${currentUser.id})' : 'NULL'}',
            );

            if (currentUser != null && currentUser.id == matricule) {
              try {
                debugPrint(
                  '🟡 [AUTH_LISTENER] User match! Saving FCM token...',
                );
                DebugLogger().log(
                  '📱 Attempting to save FCM token for user: ${currentUser.id} at station ${currentUser.station}',
                );
                await _pushNotificationService.saveUserToken(
                  currentUser.id,
                  stationId: currentUser.station,
                );
                debugPrint(
                  '✅ [AUTH_LISTENER] FCM token saved for user: ${currentUser.id}',
                );
              } catch (e) {
                debugPrint('❌ [AUTH_LISTENER] Error saving FCM token: $e');
                DebugLogger().logError('Failed to save FCM token: $e');
              }
            } else {
              debugPrint(
                '⚠️ [AUTH_LISTENER] userNotifier not yet updated or mismatch - skipping FCM token save',
              );
              debugPrint(
                '   Expected userId: $matricule, Got: ${currentUser?.id}',
              );
            }
          }
        }
      } else {
        debugPrint('🟡 [AUTH_LISTENER] User NOT authenticated (null)');
        debugPrint(
          '🟡 [AUTH_LISTENER] Current isUserAuthentifiedNotifier: ${isUserAuthentifiedNotifier.value}',
        );
        debugPrint(
          '🟡 [AUTH_LISTENER] Current userNotifier: ${userNotifier.value != null ? '${userNotifier.value!.firstName} ${userNotifier.value!.lastName}' : 'NULL'}',
        );
        // NOTE: Ne pas nettoyer les notifiers ici car cela provoque un rebuild
        // intermédiaire du MaterialApp vers WelcomePage pendant un changement d'utilisateur.
        // La déconnexion explicite est gérée dans settings_page.dart.
      }
      debugPrint('🟡 [AUTH_LISTENER] ========================================');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder2<bool, bool>(
      first: isDarkModeNotifier,
      second: isUserAuthentifiedNotifier,
      builder: (context, isDarkMode, isUserAuthentified, child) {
        debugPrint(
          '🔴 [MATERIAL_APP] ValueListenableBuilder2 rebuild - isDarkMode=$isDarkMode, isUserAuthentified=$isUserAuthentified',
        );
        return ValueListenableBuilder(
          valueListenable: userNotifier,
          builder: (context, user, _) {
            return ValueListenableBuilder2<bool, String>(
              first: _maintenanceService.isMaintenanceNotifier,
              second: _maintenanceService.maintenanceMessageNotifier,
              builder: (context, isMaintenance, maintenanceMessage, _) {
                return ValueListenableBuilder<SubscriptionStatus>(
                  valueListenable: subscriptionStatusNotifier,
                  builder: (context, subscriptionStatus, _) {
                // Déterminer la page d'accueil en fonction de l'état
                Widget homePage;

                // Mode maintenance : bloquer sauf utilisateurs autorisés
                final isAllowed = _maintenanceService.isUserAllowed(user?.id);
                if (isMaintenance && !isAllowed) {
                  homePage = MaintenancePage(message: maintenanceMessage);
                } else if (!_isOnline) {
                  homePage = const OfflinePage();
                } else if (isUserAuthentified == true &&
                    user != null &&
                    subscriptionStatus == SubscriptionStatus.expired) {
                  // Abonnement expiré : bloquer l'accès
                  homePage = const SubscriptionExpiredPage();
                } else if (isUserAuthentified == true && user != null) {
                  if (user.firstName.isEmpty || user.lastName.isEmpty) {
                    homePage = ProfileCompletionPage(user: user);
                  } else {
                    homePage = const WidgetTree();
                  }
                } else {
                  homePage = const WelcomePage();
                }

                return MaterialApp(
                  navigatorKey: navigatorKey,
                  debugShowCheckedModeBanner: false,

                  // Localisation en français
                  locale: const Locale('fr', 'FR'),
                  supportedLocales: const [
                    Locale('fr', 'FR'),
                    Locale('en', 'US'),
                  ],
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],

                  theme: KTheme.lightTheme,
                  darkTheme: KTheme.darkTheme,
                  themeMode:
                      isDarkMode == true ? ThemeMode.dark : ThemeMode.light,
                  builder: (context, child) {
                    return EnvironmentBanner(
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
                  home: homePage,
                );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
