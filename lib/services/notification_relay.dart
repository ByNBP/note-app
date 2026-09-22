import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Yeni not eklendiginde bildirim relay'ini tetikler.
///
/// Firebase Spark planinda Cloud Functions deploy edilemedigi icin FCM'e
/// gonderimi Cloudflare Worker yapiyor (bkz. `relay/`). Istemci yalnizca
/// "su notu yazdim" der; alicilari ve metni Worker Firestore'dan okur.
///
/// Not zaten Firestore'a yazilmis oluyor; bu cagri basarisiz olursa kullaniciya
/// hata gosterilmez, sadece bildirim gitmemis olur.
class NotificationRelay {
  NotificationRelay({
    FirebaseAuth? auth,
    http.Client? client,
    String? endpoint,
  })  : _authOverride = auth,
        _clientOverride = client,
        _endpoint = endpoint ?? relayEndpoint;

  final FirebaseAuth? _authOverride;
  final http.Client? _clientOverride;
  final String _endpoint;

  /// Worker adresi. `wrangler deploy` ciktisi buraya yazilir; derleme aninda
  /// `--dart-define=NOTIFY_RELAY_URL=...` ile de gecilebilir.
  static const String relayEndpoint = String.fromEnvironment(
    'NOTIFY_RELAY_URL',
    defaultValue: 'REPLACE_ME_RELAY_URL',
  );

  static const Duration _timeout = Duration(seconds: 10);

  /// Relay adresi ayarlanmis mi? Ayarlanmamissa uygulama bildirimsiz calisir.
  bool get isConfigured => !_endpoint.startsWith('REPLACE_ME');

  Future<void> notifyNewNote({
    required String sessionId,
    required String noteId,
  }) async {
    if (!isConfigured) return;

    final client = _clientOverride ?? http.Client();
    try {
      final token = await (_authOverride ?? FirebaseAuth.instance)
          .currentUser
          ?.getIdToken();
      if (token == null) return;

      final response = await client
          .post(
            Uri.parse('$_endpoint/notify'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({'sessionId': sessionId, 'noteId': noteId}),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
          'Bildirim relay hatasi ${response.statusCode}: ${response.body}',
        );
      }
    } catch (error) {
      debugPrint('Bildirim relay cagrilamadi: $error');
    } finally {
      if (_clientOverride == null) client.close();
    }
  }
}
