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
import 'package:nexshift_app/features/auth/presentation/widgets/enter_app_widget.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/replacement_request_dialog.dart';
import 'package:nexshift_app/features/replacement/presentation/pages/replacement_requests_list_page.dart';
import 'package:nexshift_app/core/services/preferences_service.dart';
import 'package:nexshift_app/core/services/local_reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexshift_app/firebase_options.dart';
import 'package:timezone/data/latest_10y.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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

    // Set up notification tap handler via le setter qui gère le replay du
    // message initial si l'app a été lancée depuis une notification fermée.
    pushNotificationService.onNotificationTapCallback = (data) {
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

  // Initialiser la base de données timezone pour les notifications schedulées
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Paris'));

  runApp(const NexShift());
}

/// Handle notification tap and navigate to appropriate page
void _handleNotificationTap(Map<String, dynamic> data) async {
  debugPrint('🔔 Handling notification tap: $data');

  // Si l'app était fermée, la session n'est pas encore restaurée au moment où
  // cette fonction est appelée (getInitialMessage / replay). On attend max 3s.
  if (userNotifier.value == null) {
    debugPrint('🔔 Waiting for session to be restored before navigating...');
    int tries = 0;
    while (userNotifier.value == null && tries < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      tries++;
    }
    debugPrint('🔔 Session wait done (tries=$tries), user=${userNotifier.value?.id}');
  }

  final currentUserId = userNotifier.value?.id;
  if (currentUserId == null) {
    debugPrint('⚠️ No current user after wait');
    return;
  }

  final type = data['type'];

  // On utilise navigatorKey pour récupérer le contexte au dernier moment,
  // après tous les awaits, pour éviter les warnings BuildContext async gaps.
  final navigator = navigatorKey.currentState;
  if (navigator == null) {
    debugPrint('⚠️ No navigator available');
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

      // ignore: use_build_context_synchronously
      showReplacementRequestDialog(
        navigator.context,
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
      navigator.push(
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

class _NexShiftState extends State<NexShift> with WidgetsBindingObserver {
  final _authService = FirebaseAuthService();
  final _connectivityService = ConnectivityService();
  final _maintenanceService = MaintenanceService();

  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initThemeMode();
    _initPresenceViewMode();
    _checkAuthState();
    _startConnectivityMonitoring();
    _maintenanceService.startListening();
  }

  /// Détecte le retour au foreground pour rejouer les notifications en attente.
  /// Cas : app en background, tap notification → onMessageOpenedApp peut être
  /// manqué sur certains appareils Android. On vérifie ici si une notification
  /// est en attente dans le service.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 [LIFECYCLE] App resumed — checking pending notification');
      PushNotificationService().clearBadge();
      final pending = PushNotificationService().consumePendingMessage();
      if (pending != null) {
        debugPrint('📱 [LIFECYCLE] Replaying pending notification: ${pending.messageId}');
        _handleNotificationTap(pending.data);
      }
      // Rafraîchir le contenu du rappel quotidien avec les plannings à jour
      final user = userNotifier.value;
      if (user != null && user.personalAlertEnabled) {
        LocalReminderService().reschedule(user).catchError((e) {
          debugPrint('📱 [LIFECYCLE] Reminder reschedule on resume failed: $e');
        });
      }
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _connectivityService.stopMonitoring();
    _maintenanceService.stopListening();
    super.dispose();
  }

  void initThemeMode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool? themeModeStored = prefs.getBool(KConstants.themeModeKey);
    isDarkModeNotifier.value = themeModeStored ?? false;
  }

  void _initPresenceViewMode() {
    PreferencesService().loadPresenceViewMode();
  }

  /// Vérifie l'état d'authentification Firebase au démarrage
  void _checkAuthState() async {
    debugPrint('🟡 [AUTH_LISTENER] Setting up auth state check');

    // Tentative de restauration immédiate au cold start :
    // Firebase Auth persiste la session automatiquement, mais les notifiers
    // applicatifs (isUserAuthentifiedNotifier, userNotifier) sont réinitialisés
    // à chaque démarrage. On les restaure depuis le cache local si un utilisateur
    // Firebase est déjà authentifié.
    final firebaseUser = _authService.currentFirebaseUser;
    if (firebaseUser != null) {
      debugPrint('🟡 [AUTH_LISTENER] Firebase user found at startup, restoring session...');
      final restored = await EnterApp.restore();
      debugPrint('🟡 [AUTH_LISTENER] Session restored: $restored');
    } else {
      debugPrint('🟡 [AUTH_LISTENER] No Firebase user at startup');
    }
    // La vérification est terminée — masquer l'indicateur de chargement sur WelcomePage
    isRestoringSessionNotifier.value = false;

    // Écoute pour les changements futurs (login/logout en cours de session)
    // NE PAS appeler restore() ici : c'est déjà fait ci-dessus au cold start,
    // et EnterApp.build() gère la navigation après un login explicite.
    _authService.authStateChanges.listen((firebaseUser) async {
      debugPrint('🟡 [AUTH_LISTENER] ========== AUTH STATE CHANGED ==========');
      if (firebaseUser != null) {
        debugPrint('🟡 [AUTH_LISTENER] User authenticated: ${firebaseUser.email}');
        // Rien à faire ici : soit restore() a déjà été appelé au démarrage,
        // soit EnterApp.build() a été appelé après le login explicite.
        // Le listener sert uniquement de trace pour le debugging.
      } else {
        debugPrint('🟡 [AUTH_LISTENER] User NOT authenticated (null)');
        // NOTE: Ne pas nettoyer les notifiers ici — la déconnexion explicite
        // est gérée dans settings_page.dart pour éviter un rebuild intermédiaire.
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
                final isAllowed = _maintenanceService.isUserAllowed(user?.id);
                if (isMaintenance && !isAllowed) {
                  homePage = MaintenancePage(message: maintenanceMessage);
                } else if (!_isOnline) {
                  homePage = const OfflinePage();
                } else if (isUserAuthentified == true &&
                    user != null &&
                    subscriptionStatus == SubscriptionStatus.expired) {
                  homePage = const SubscriptionExpiredPage();
                } else if (isUserAuthentified == true && user != null) {
                  if (user.firstName.isEmpty || user.lastName.isEmpty) {
                    homePage = ProfileCompletionPage(user: user);
                  } else {
                    // La Key basée sur l'userId force une reconstruction complète
                    // de WidgetTree (et de ses pages) quand l'utilisateur change,
                    // notamment lors de la restauration de session au démarrage.
                    homePage = WidgetTree(key: ValueKey(user.id));
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
