import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/session_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/setup_required_screen.dart';
import 'services/auth_service.dart';
import 'services/note_service.dart';
import 'services/notification_service.dart';
import 'services/session_service.dart';
import 'theme.dart';
import 'widgets/feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr');

  if (!DefaultFirebaseOptions.isConfigured) {
    runApp(const _SetupApp());
    return;
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    runApp(_SetupApp(error: error));
    return;
  }

  // Arka plan mesajlari yalnizca native platformlarda bu handler'a duser;
  // web'de bunu web/firebase-messaging-sw.js ustlenir.
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  runApp(const NoteApp());
}

/// Firebase yapilandirilmadiginda calisan kucuk uygulama.
class _SetupApp extends StatelessWidget {
  const _SetupApp({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ortak Notlar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: SetupRequiredScreen(error: error),
    );
  }
}

class NoteApp extends StatefulWidget {
  const NoteApp({super.key});

  @override
  State<NoteApp> createState() => _NoteAppState();
}

class _NoteAppState extends State<NoteApp> {
  final AuthService _auth = AuthService();
  final SessionService _sessions = SessionService();
  final NoteService _notes = NoteService();
  final NotificationService _notifications = NotificationService();

  late final GoRouter _router = _buildRouter();

  StreamSubscription<String>? _openSub;
  StreamSubscription<InAppNotification>? _inAppSub;
  Timer? _bannerTimer;

  InAppNotification? _banner;
  String? _attachedUid;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    unawaited(_initNotifications());
  }

  Future<void> _initNotifications() async {
    await _notifications.initialize();
    if (!mounted) return;

    _openSub = _notifications.openRequests.listen((sessionId) {
      _router.go('/session/$sessionId');
    });

    _inAppSub = _notifications.inAppMessages.listen((message) {
      setState(() => _banner = message);
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _banner = null);
      });
    });

    // initialize() izin diyalogunu gosterdigi icin banner durumu degismis
    // olabilir; giris yapilmissa token'i simdi kaydet.
    _onAuthChanged();
  }

  /// Giris yapildiginda FCM token'ini kaydeder, cikista serbest birakir.
  void _onAuthChanged() {
    final uid = _auth.uid;
    if (uid != null && uid != _attachedUid) {
      _attachedUid = uid;
      unawaited(_notifications.attachUser(_auth));
    } else if (uid == null && _attachedUid != null) {
      _attachedUid = null;
    }
  }

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: '/',
      refreshListenable: _auth,
      redirect: (context, state) {
        final atLogin = state.matchedLocation == '/login';
        switch (_auth.status) {
          case AuthStatus.unknown:
            return null;
          case AuthStatus.signedOut:
            return atLogin ? null : '/login';
          case AuthStatus.signedIn:
            return atLogin ? '/' : null;
        }
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) => _auth.status == AuthStatus.unknown
              ? const _SplashScreen()
              : const SessionsScreen(),
        ),
        GoRoute(
          path: '/session/:id',
          builder: (context, state) =>
              SessionScreen(sessionId: state.pathParameters['id']!),
        ),
      ],
      errorBuilder: (context, state) => const _SplashScreen(),
    );
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _openSub?.cancel();
    _inAppSub?.cancel();
    _auth.removeListener(_onAuthChanged);
    unawaited(_notifications.shutdown());
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: _auth),
        Provider<SessionService>.value(value: _sessions),
        Provider<NoteService>.value(value: _notes),
        ChangeNotifierProvider<NotificationService>.value(
          value: _notifications,
        ),
      ],
      child: MaterialApp.router(
        title: 'Ortak Notlar',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: _router,
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Stack(
          children: [
            ?child,
            if (_banner != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: InAppNotificationBanner(
                  title: _banner!.title,
                  body: _banner!.body,
                  onDismiss: () => setState(() => _banner = null),
                  onOpen: () {
                    final sessionId = _banner!.sessionId;
                    setState(() => _banner = null);
                    if (sessionId != null) _router.go('/session/$sessionId');
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
