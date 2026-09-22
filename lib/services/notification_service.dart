import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'auth_service.dart';

/// Uygulama acikken gelen bildirimi ekranda banner olarak gostermek icin
/// kullanilan sade model.
class InAppNotification {
  const InAppNotification({
    required this.title,
    required this.body,
    this.sessionId,
  });

  final String title;
  final String body;
  final String? sessionId;
}

/// Uygulama arka plandayken gelen mesajlar bu isolate'te islenir.
///
/// Cloud Function `notification` alani da gonderdigi icin Android bildirimi
/// kendisi gosterir; burada yalnizca gunluk tutuyoruz.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  debugPrint('Arka planda bildirim alindi: ${message.messageId}');
}

/// FCM kurulumu, izinler, token kaydi ve bildirime tiklaninca yonlendirme.
///
/// Bildirim izni kullaniciya sorulduktan sonra degistigi icin dinleyicileri
/// uyarir; ekranlar izin uyarisini buna gore gosterir.
class NotificationService extends ChangeNotifier {
  NotificationService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  final StreamController<String> _openRequests =
      StreamController<String>.broadcast();
  final StreamController<InAppNotification> _inApp =
      StreamController<InAppNotification>.broadcast();

  StreamSubscription<String>? _tokenRefreshSub;
  final List<StreamSubscription<dynamic>> _messageSubs = [];

  String? _currentToken;
  AuthService? _auth;
  bool _initialized = false;

  /// Bildirime tiklandiginda acilmasi istenen oturum id'leri.
  Stream<String> get openRequests => _openRequests.stream;

  /// Uygulama on plandayken gosterilecek bildirimler.
  Stream<InAppNotification> get inAppMessages => _inApp.stream;

  AuthorizationStatus _permission = AuthorizationStatus.notDetermined;

  /// Kullanicinin bildirim izni verip vermedigi.
  AuthorizationStatus get permission => _permission;

  /// Kullanici izni acikca reddetti mi? (Uyari bandi bunu kullanir.)
  bool get isBlocked => _permission == AuthorizationStatus.denied;

  /// Android bildirim kanali; Cloud Function ayni id'yi gonderiyor.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'new_notes',
    'Yeni notlar',
    description: 'Oturumlarina yeni bir not eklendiginde haber verir.',
    importance: Importance.high,
  );

  // ---------------------------------------------------------------------
  // Kurulum
  // ---------------------------------------------------------------------

  /// Uygulama acilisinda bir kez cagrilir.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!kIsWeb) {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final sessionId = response.payload;
          if (sessionId != null && sessionId.isNotEmpty) {
            _openRequests.add(sessionId);
          }
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _permission = settings.authorizationStatus;
    notifyListeners();

    // iOS/web'de on plandayken sistem bildirimi de gorunsun.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _messageSubs.add(FirebaseMessaging.onMessage.listen(_onForegroundMessage));
    _messageSubs.add(
      FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTapped),
    );

    // Uygulama bildirime tiklanarak sifirdan acildiysa.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onNotificationTapped(initial);
  }

  // ---------------------------------------------------------------------
  // Token yonetimi
  // ---------------------------------------------------------------------

  /// Giris yapilinca cagrilir: cihaz token'ini kullanicinin profiline yazar.
  Future<void> attachUser(AuthService auth) async {
    _auth = auth;

    if (kIsWeb && !DefaultFirebaseOptions.isWebPushConfigured) {
      debugPrint(
        'Web push VAPID anahtari ayarlanmamis; web bildirimleri kapali.',
      );
      return;
    }

    try {
      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? DefaultFirebaseOptions.webPushVapidKey : null,
      );
      if (token == null) return;
      _currentToken = token;
      await auth.registerFcmToken(token);

      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((fresh) async {
        final previous = _currentToken;
        _currentToken = fresh;
        if (previous != null && previous != fresh) {
          await auth.unregisterFcmToken(previous);
        }
        await auth.registerFcmToken(fresh);
      });
    } catch (error) {
      // Izin verilmemis veya tarayici desteklemiyor olabilir; uygulama
      // bildirimsiz calismaya devam etmeli.
      debugPrint('FCM token alinamadi: $error');
    }
  }

  /// Cikis yapmadan once cagrilir: bu cihaza artik bildirim gitmesin.
  Future<void> detachUser() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    final token = _currentToken;
    final auth = _auth;
    if (token != null && auth != null) {
      try {
        await auth.unregisterFcmToken(token);
      } catch (error) {
        debugPrint('Token silinemedi: $error');
      }
    }
    _currentToken = null;
    _auth = null;
  }

  // ---------------------------------------------------------------------
  // Mesaj isleme
  // ---------------------------------------------------------------------

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['sessionTitle'] ?? 'Yeni not';
    final body = notification?.body ?? '';
    final sessionId = message.data['sessionId'] as String?;

    // Uygulama icinde her zaman bir banner gosteriyoruz.
    _inApp.add(
      InAppNotification(title: title, body: body, sessionId: sessionId),
    );

    if (kIsWeb) return; // web'de sistem bildirimi service worker'a birakiliyor

    await _local.show(
      id: message.messageId.hashCode,
      title: title,
      body: body,
      payload: sessionId,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          groupKey: sessionId,
        ),
      ),
    );
  }

  void _onNotificationTapped(RemoteMessage message) {
    final sessionId = message.data['sessionId'] as String?;
    if (sessionId != null && sessionId.isNotEmpty) {
      _openRequests.add(sessionId);
    }
  }

  /// Aboneliklerini ve akislarini kapatir.
  ///
  /// [ChangeNotifier.dispose] senkron oldugu icin ayri bir ad kullaniyoruz.
  Future<void> shutdown() async {
    await _tokenRefreshSub?.cancel();
    for (final sub in _messageSubs) {
      await sub.cancel();
    }
    await _openRequests.close();
    await _inApp.close();
    dispose();
  }
}
