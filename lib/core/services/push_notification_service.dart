import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexshift_app/core/data/datasources/sdis_context.dart';
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
  // Utiliser le setter onNotificationTapCallback pour bénéficier du replay
  // automatique du message initial si l'app a été ouverte depuis une notification.
  Function(Map<String, dynamic>)? onNotificationTap;

  // Message initial stocké si getInitialMessage() est appelé avant que
  // onNotificationTap soit assigné (cas app fermée ouverte par notification).
  RemoteMessage? _pendingInitialMessage;

  bool _initialized = false;

  /// Setter qui assigne le callback et rejoue immédiatement le message initial
  /// si l'app a été lancée depuis une notification (app était fermée).
  set onNotificationTapCallback(Function(Map<String, dynamic>) callback) {
    onNotificationTap = callback;
    if (_pendingInitialMessage != null) {
      final msg = _pendingInitialMessage!;
      _pendingInitialMessage = null;
      debugPrint('🔔 Replaying pending initial message: ${msg.messageId}');
      Future.microtask(() => callback(msg.data));
    }
  }

  /// Consomme le message en attente (si présent) et le retourne.
  /// Appelé depuis didChangeAppLifecycleState pour gérer le cas où
  /// onMessageOpenedApp n'a pas été déclenché (background → foreground).
  RemoteMessage? consumePendingMessage() {
    final msg = _pendingInitialMessage;
    _pendingInitialMessage = null;
    return msg;
  }

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

    // Handler pour quand l'utilisateur tape sur une notification (app en background)
    // Le message est stocké dans _pendingInitialMessage si le callback n'est pas
    // encore assigné (race condition possible lors du démarrage).
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔔 [FCM] onMessageOpenedApp: ${message.messageId}');
      debugPrint('🔔 [FCM] onMessageOpenedApp data: ${message.data}');
      if (onNotificationTap != null) {
        onNotificationTap!(message.data);
      } else {
        debugPrint('🔔 [FCM] onNotificationTap not set yet — storing as pending');
        _pendingInitialMessage ??= message;
      }
    });

    // Vérifier si l'app a été ouverte par une notification (app était fermée = cold start)
    // On stocke le message dans _pendingInitialMessage car onNotificationTap
    // n'est pas encore assigné à ce stade (il le sera dans main() juste après).
    // Le setter onNotificationTapCallback se chargera du replay.
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🔔 [FCM] getInitialMessage: ${initialMessage.messageId}');
      debugPrint('🔔 [FCM] getInitialMessage data: ${initialMessage.data}');
      _pendingInitialMessage = initialMessage;
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
  Future<void> clearDeviceToken(String userId, {String? authUid}) async {
    try {
      debugPrint('🗑️ Clearing FCM token for user: $userId');

      final sdisId = SDISContext().currentSDISId;
      if (authUid != null && authUid.isNotEmpty && sdisId != null && sdisId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('sdis')
            .doc(sdisId)
            .collection('users')
            .doc(authUid)
            .update({'fcmToken': FieldValue.delete()});
      }

      // Supprimer le token local de FCM
      await _firebaseMessaging.deleteToken();

      debugPrint('✅ FCM token cleared successfully for authUid: $authUid');
    } catch (e) {
      debugPrint('❌ Error clearing FCM token: $e');
      // Ne pas throw l'erreur pour ne pas bloquer la déconnexion
    }
  }

  /// Sauvegarde le token FCM pour un utilisateur au niveau SDIS
  /// Le token est stocké dans sdis/{sdisId}/users/{authUid} pour être accessible
  /// même avant que l'utilisateur ait rejoint une caserne.
  Future<void> saveUserToken(String userId, {String? authUid}) async {
    final logger = DebugLogger();

    try {
      logger.logFCM('Getting FCM token...');
      final token = await _firebaseMessaging.getToken();

      if (token == null) {
        logger.logError('FCM token is null');
        return;
      }

      logger.logFCM('Token received: ${token.substring(0, 20)}...');

      final sdisId = SDISContext().currentSDISId;

      if (authUid != null && authUid.isNotEmpty && sdisId != null && sdisId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('sdis')
            .doc(sdisId)
            .collection('users')
            .doc(authUid)
            .set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('✅ FCM token saved for authUid: $authUid in sdis/$sdisId/users');
      } else {
        logger.logError('Cannot save FCM token: authUid ($authUid) or SDIS context ($sdisId) unavailable');
      }

      logger.logSuccess('FCM token saved for user: $userId');
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
      logger.logError('Error saving FCM token: $e');
    }
  }

  /// Supprime le token FCM lors de la déconnexion
  Future<void> deleteUserToken(String userId, {String? authUid}) async {
    try {
      final sdisId = SDISContext().currentSDISId;
      if (authUid != null && authUid.isNotEmpty && sdisId != null && sdisId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('sdis')
            .doc(sdisId)
            .collection('users')
            .doc(authUid)
            .update({
          'fcmToken': FieldValue.delete(),
          'fcmTokenUpdatedAt': FieldValue.delete(),
        });
        debugPrint('✅ FCM token deleted for authUid: $authUid in sdis/$sdisId/users');
      }
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

  static const _badgeChannel = MethodChannel('nexshift/badge');

  /// Efface le badge de l'icône de l'app (iOS uniquement).
  /// À appeler dès que l'app passe au premier plan.
  Future<void> clearBadge() async {
    try {
      await _badgeChannel.invokeMethod('clearBadge');
      debugPrint('✅ [FCM] Badge cleared');
    } catch (e) {
      // Non-fatal : la fonctionnalité n'est disponible que sur iOS
      debugPrint('⚠️ [FCM] Failed to clear badge: $e');
    }
  }

  /// Nettoie les ressources
  void dispose() {
    // Cleanup if needed
  }
}
