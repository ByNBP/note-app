// ---------------------------------------------------------------------------
// Firebase yapilandirmasi -- elle bakimi yapiliyor.
//
// Android degerleri android/app/google-services.json dosyasindan alindi.
// Web degerleri Firebase Console > Project settings > Your apps > Web app
// bolumundeki `firebaseConfig` nesnesinden gelir.
//
// Web bolumunu degistirirsen ayni degerleri web/firebase-messaging-sw.js
// icine de yaz: service worker Dart kodunu okuyamaz.
//
// `flutterfire configure` calistirirsan bu dosyanin uzerine yazar ve
// webPushVapidKey sabiti kaybolur -- o zaman asagidaki degeri geri ekle.
// ---------------------------------------------------------------------------

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Henuz doldurulmamis alanlar bu onekle basliyor.
const String _placeholderPrefix = 'REPLACE_ME';

const String _projectId = 'note-app-a3675';
const String _messagingSenderId = '533163142600';
const String _storageBucket = 'note-app-a3675.firebasestorage.app';

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// Calisilan platform icin yapilandirma tamam mi?
  static bool get isConfigured =>
      !currentPlatform.apiKey.startsWith(_placeholderPrefix);

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          '${defaultTargetPlatform.name} icin Firebase yapilandirmasi yok. '
          'Once `flutterfire configure` calistir.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB2vAFf0duXEGXmkihcz9ptF97WxSQpVSM',
    appId: '1:533163142600:android:d8594552ce538b481ee4fd',
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
  );

  /// iOS degerleri henuz doldurulmadi.
  ///
  /// Firebase Console > Add app > iOS ile `com.example.ortaknotlar` bundle
  /// id'si icin bir uygulama olustur, sonra bir Mac'te
  /// `flutterfire configure --platforms=ios` calistir; komut hem asagidaki
  /// degerleri hem de `ios/Runner/GoogleService-Info.plist` dosyasini yazar.
  ///
  /// Doldurulana kadar uygulama iOS'ta cokmez, kurulum ekranini gosterir.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '${_placeholderPrefix}_IOS_API_KEY',
    appId: '${_placeholderPrefix}_IOS_APP_ID',
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
    iosBundleId: 'com.example.ortaknotlar',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCf9lIksECtMS_8aMdC9IKehKgox3V2zoI',
    appId: '1:533163142600:web:0f1c79ba74af7a921ee4fd',
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    authDomain: '$_projectId.firebaseapp.com',
    storageBucket: _storageBucket,
    measurementId: 'G-RRPWE5WPBQ',
  );

  /// Web push icin genel VAPID anahtari.
  /// Firebase Console > Project Settings > Cloud Messaging >
  /// "Web Push certificates".
  static const String webPushVapidKey =
      'BH9nkS2XryG16CV_pb8caTeCaw_2zJiie92mDYwn4uLMt4AgX0k54RPqJ_XQ0ray5F7'
      'xKX_h5euHXPFZgqQ81o0';

  static bool get isWebPushConfigured =>
      !webPushVapidKey.startsWith(_placeholderPrefix);
}
