import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/config/environment_config.dart';
import 'debug_logger.dart';

/// Handler pour les messages reçus en arrière-plan
/// DOIT être une fonction top-level (en dehors de toute classe)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // S'assurer que Firebase est initialisé dans cet isolat
  // Nécessaire car le background handler s'exécute dans un isolat séparé
  await _ensureFirebaseInitialized();

  debugPrint('📬 Background message received: ${message.messageId}');
  debugPrint('  Title: ${message.notification?.title}');
  debugPrint('  Body: ${message.notification?.body}');
  debugPrint('  Data: ${message.data}');
}

/// Initialise Firebase de manière sûre (évite l'erreur duplicate-app)
Future<void> _ensureFirebaseInitialized() async {
  // Vérifier si Firebase est déjà initialisé
  if (Firebase.apps.isNotEmpty) {
    debugPrint('Firebase already initialized, skipping...');
    return;
  }

  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Firebase déjà initialisé, c'est OK
    debugPrint('Firebase initialization skipped: $e');
  }
}

/// Service de gestion des notifications push
/// Utilise Firebase Cloud Messaging pour envoyer et recevoir des notifications
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Callback pour gérer les actions sur les notifications
  Function(Map<String, dynamic>)? onNotificationTap;

  bool _initialized = false;

  /// Initialise le service de notifications
  Future<void> initialize() async {
    if (_initialized) return;

    final logger = DebugLogger();

    try {
      logger.log('🔔 Initializing PushNotificationService...');

      // Demander la permission pour les notifications
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Notification permission granted');
        logger.logSuccess('Notification permission granted');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('⚠️ Notification permission provisional');
        logger.log('⚠️ Notification permission provisional');
      } else {
        debugPrint('❌ Notification permission denied');
        logger.logError('Notification permission denied');
        return;
      }

      // Initialiser les notifications locales
      await _initializeLocalNotifications();
      logger.logSuccess('Local notifications initialized');

      // Configuration des handlers de messages
      await _setupMessageHandlers();
      logger.logSuccess('Message handlers configured');

      // Récupérer et sauvegarder le token FCM
      await _saveDeviceToken();

      _initialized = true;
      debugPrint('✅ PushNotificationService initialized successfully');
      logger.logSuccess('PushNotificationService initialized');
    } catch (e) {
      debugPrint('❌ Error initializing PushNotificationService: $e');
      logger.logError('Error initializing PushNotificationService: $e');
    }
  }

  /// Initialise les notifications locales (pour Android)
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('🔔 Local notification tapped: ${response.payload}');
        if (response.payload != null && onNotificationTap != null) {
          // Parser le payload JSON
          try {
            final data = Map<String, dynamic>.from(
              Uri.splitQueryString(response.payload!),
            );
            onNotificationTap!(data);
          } catch (e) {
            debugPrint('Error parsing notification payload: $e');
          }
        }
      },
    );

    // Créer le canal de notification Android
    const androidChannel = AndroidNotificationChannel(
      'nexshift_replacement_channel',
      'Remplacements',
      description: 'Notifications de recherche de remplaçants',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    debugPrint('✅ Local notifications initialized');
  }

  /// Configure les handlers pour les messages FCM
  Future<void> _setupMessageHandlers() async {
    // Handler pour messages reçus en premier plan (app ouverte)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📨 Foreground message received: ${message.messageId}');
      _showLocalNotification(message);
    });

    // Handler pour messages reçus en arrière-plan (app fermée/background)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Handler pour quand l'utilisateur tape sur une notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔔 Notification opened app: ${message.messageId}');
      if (onNotificationTap != null) {
        onNotificationTap!(message.data);
      }
    });

    // Vérifier si l'app a été ouverte par une notification
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🔔 App opened from notification: ${initialMessage.messageId}');
      if (onNotificationTap != null) {
        onNotificationTap!(initialMessage.data);
      }
    }
  }

  /// Affiche une notification locale pour les messages reçus en premier plan
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    if (notification == null) return;

    // Construire le payload à partir des data
    final payload = Uri(queryParameters: data).query;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nexshift_replacement_channel',
          'Remplacements',
          channelDescription: 'Notifications de recherche de remplaçants',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  /// Récupère et sauvegarde le token FCM de l'appareil
  Future<void> _saveDeviceToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        debugPrint('📱 FCM Token: $token');
        // TODO: Sauvegarder le token dans Firestore pour l'utilisateur courant
        // Sera implémenté dans la prochaine étape
      }
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }

    // Écouter les changements de token
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      debugPrint('🔄 FCM Token refreshed: $newToken');
      // TODO: Mettre à jour le token dans Firestore
    });
  }

  /// Supprime le token FCM de l'appareil lors de la déconnexion
  /// Cela permet d'éviter de recevoir des notifications après déconnexion
  Future<void> clearDeviceToken(String userId, {String? stationId}) async {
    try {
      debugPrint('🗑️ Clearing FCM token for user: $userId');

      // Utiliser le chemin complet avec station si fourni
      final collectionPath = stationId != null
          ? EnvironmentConfig.getCollectionPath('users', stationId)
          : 'users';

      // Supprimer le token du document utilisateur dans Firestore
      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(userId)
          .update({'fcmToken': FieldValue.delete()});

      // Supprimer le token local de FCM
      await _firebaseMessaging.deleteToken();

      debugPrint('✅ FCM token cleared successfully in $collectionPath');
    } catch (e) {
      debugPrint('❌ Error clearing FCM token: $e');
      // Ne pas throw l'erreur pour ne pas bloquer la déconnexion
    }
  }

  /// Sauvegarde le token FCM pour un utilisateur
  Future<void> saveUserToken(String userId, {String? stationId}) async {
    final logger = DebugLogger();

    try {
      logger.logFCM('Getting FCM token...');
      final token = await _firebaseMessaging.getToken();

      if (token == null) {
        logger.logError('FCM token is null');
        return;
      }

      logger.logFCM('Token received: ${token.substring(0, 20)}...');
      logger.logFCM('Saving token for user: $userId, station: $stationId');

      // Utiliser le chemin complet avec station si fourni
      final collectionPath = stationId != null
          ? EnvironmentConfig.getCollectionPath('users', stationId)
          : 'users';

      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(userId)
          .update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ FCM token saved for user: $userId in $collectionPath');
      logger.logSuccess('FCM token saved for user: $userId');
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
      logger.logError('Error saving FCM token: $e');
    }
  }

  /// Supprime le token FCM lors de la déconnexion
  Future<void> deleteUserToken(String userId, {String? stationId}) async {
    try {
      // Utiliser le chemin complet avec station si fourni
      final collectionPath = stationId != null
          ? EnvironmentConfig.getCollectionPath('users', stationId)
          : 'users';

      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(userId)
          .update({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.delete(),
      });

      debugPrint('✅ FCM token deleted for user: $userId in $collectionPath');
    } catch (e) {
      debugPrint('❌ Error deleting FCM token: $e');
    }
  }

  /// Récupère le token FCM actuel
  Future<String?> getToken() async {
    return await _firebaseMessaging.getToken();
  }

  /// Affiche une notification locale pour les tests
  Future<void> showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    // Construire le payload à partir des data
    final payloadString = payload != null ? Uri(queryParameters: payload.map((k, v) => MapEntry(k, v.toString()))).query : '';

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nexshift_replacement_channel',
          'Remplacements',
          channelDescription: 'Notifications de recherche de remplaçants',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payloadString,
    );
  }

  /// Nettoie les ressources
  void dispose() {
    // Cleanup if needed
  }
}
