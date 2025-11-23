import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_storage/get_storage.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:nexshift_app/config/theme.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/presentation/widgets/value_listenable_builder_widget.dart';
import 'package:nexshift_app/core/utils/constants.dart';
import 'package:nexshift_app/core/services/firebase_auth_service.dart';
import 'package:nexshift_app/core/services/push_notification_service.dart';
import 'package:nexshift_app/core/services/debug_logger.dart';
import 'package:nexshift_app/core/services/connectivity_service.dart';
import 'package:nexshift_app/core/services/log_service.dart';
import 'package:nexshift_app/core/repositories/local_repositories.dart';
import 'package:nexshift_app/core/presentation/pages/offline_page.dart';
import 'package:nexshift_app/features/app_shell/presentation/widgets/widget_tree.dart';
import 'package:nexshift_app/features/auth/presentation/pages/welcome_page.dart';
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
      await LogService().log('Firebase already initialized', level: LogLevel.info);
    }
  } catch (e) {
    // Sur iOS, Firebase peut être initialisé par le plugin natif avant Dart
    // L'erreur duplicate-app est normale et peut être ignorée
    final errorStr = e.toString();
    if (errorStr.contains('duplicate-app')) {
      debugPrint('Firebase already initialized by iOS plugin - OK');
      await LogService().log('Firebase ready (native init)', level: LogLevel.info);
    } else {
      debugPrint('Error initializing Firebase: $e');
      await LogService().log('Firebase initialization error: $e', level: LogLevel.error);
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
    await LogService().log('Push notifications initialized', level: LogLevel.info);
  } catch (e) {
    debugPrint('Error initializing push notifications: $e');
    await LogService().log('Push notifications error: $e', level: LogLevel.error);
  }

  try {
    await GetStorage.init();
  } catch (e) {
    // En cas d'erreur (ex: path_provider non prêt sur simulateur)
    debugPrint('Error initializing GetStorage: $e');
    await LogService().log('GetStorage initialization error: $e', level: LogLevel.error);
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

      showReplacementRequestDialog(
        context,
        requestId: requestId,
        currentUserId: currentUserId,
      );
      break;

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
  final _localRepo = LocalRepository();
  final _pushNotificationService = PushNotificationService();
  final _connectivityService = ConnectivityService();

  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    initThemeMode();
    _checkAuthState();
    _startConnectivityMonitoring();
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
    super.dispose();
  }

  void initThemeMode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool? themeModeStored = prefs.getBool(KConstants.themeModeKey);
    isDarkModeNotifier.value = themeModeStored ?? false;
  }

  /// Vérifie l'état d'authentification Firebase au démarrage
  void _checkAuthState() async {
    // Écouter les changements d'état d'authentification
    _authService.authStateChanges.listen((firebaseUser) async {
      if (firebaseUser != null) {
        debugPrint('User authenticated: ${firebaseUser.email}');

        // Récupérer le profil utilisateur complet
        try {
          final user = await _localRepo.getCurrentUser();
          if (user != null) {
            userNotifier.value = user;
            isUserAuthentifiedNotifier.value = true;

            // Sauvegarder le token FCM pour l'utilisateur
            try {
              DebugLogger().log('📱 Attempting to save FCM token for user: ${user.id}');
              await _pushNotificationService.saveUserToken(user.id);
              debugPrint('FCM token saved for user: ${user.id}');
            } catch (e) {
              debugPrint('Error saving FCM token: $e');
              DebugLogger().logError('Failed to save FCM token: $e');
            }

            // Sauvegarder l'état d'authentification
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(KConstants.authentifiedKey, true);
          }
        } catch (e) {
          debugPrint('Error loading user profile: $e');
          isUserAuthentifiedNotifier.value = false;
        }
      } else {
        debugPrint('User not authenticated');

        // Supprimer le token FCM si l'utilisateur était connecté
        final previousUser = userNotifier.value;
        if (previousUser != null) {
          try {
            await _pushNotificationService.deleteUserToken(previousUser.id);
            debugPrint('FCM token deleted for user: ${previousUser.id}');
          } catch (e) {
            debugPrint('Error deleting FCM token: $e');
          }
        }

        isUserAuthentifiedNotifier.value = false;
        userNotifier.value = null;

        // Nettoyer l'état d'authentification
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(KConstants.authentifiedKey, false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder2<bool, bool>(
      first: isDarkModeNotifier,
      second: isUserAuthentifiedNotifier,
      builder: (context, isDarkMode, isUserAuthentified, child) {
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
          themeMode: isDarkMode == true ? ThemeMode.dark : ThemeMode.light,
          home: !_isOnline
              ? const OfflinePage()
              : isUserAuthentified == true
                  ? const WidgetTree()
                  : const WelcomePage(),
        );
      },
    );
  }
}
