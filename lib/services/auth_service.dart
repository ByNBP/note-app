import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';

/// Kullaniciya gosterilebilecek, Turkce mesajli kimlik dogrulama hatasi.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

enum AuthStatus { unknown, signedOut, signedIn }

/// Firebase Auth + `users/{uid}` profil dokumanini birlikte yonetir.
///
/// Oturum durumu degistiginde profil dokumanini da dinlemeye baslar, boylece
/// isim degisiklikleri ve FCM token guncellemeleri aninda yansir.
class AuthService extends ChangeNotifier {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance {
    // authStateChanges() yayin akisi oldugu icin, abone olmadan once dusmus
    // olan ilk olayi kaciririz. Zaten oturum aciksa durumu hemen kur.
    //
    // currentUser null ise "oturum yok" demek degildir (web'de kalici oturum
    // asenkron cozulur); bu durumda ilk olayi bekleyip `unknown` kaliriz --
    // boylece acilista giris ekrani bir an gorunup kaybolmaz.
    final existing = _auth.currentUser;
    if (existing != null) _onAuthStateChanged(existing);

    _authSub = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _profile;

  AuthStatus get status => _status;
  AppUser? get profile => _profile;
  User? get firebaseUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;

  /// Oturum acik ve profil yuklenmis mi?
  bool get isReady => _status == AuthStatus.signedIn && _profile != null;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  // ---------------------------------------------------------------------
  // Oturum islemleri
  // ---------------------------------------------------------------------

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final name = _requireName(displayName);
    await _guard(() async {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await cred.user!.updateDisplayName(name);
      await _writeProfile(cred.user!, displayName: name, isGuest: false);
    });
  }

  Future<void> signIn({required String email, required String password}) async {
    await _guard(() async {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      // Profil dokumani eksikse (ornegin konsoldan acilmis hesap) tamamla.
      await _ensureProfile(cred.user!);
    });
  }

  /// E-posta istemeden, sadece isimle giris. Cihaza bagli anonim hesap acar.
  Future<void> signInAsGuest({required String displayName}) async {
    final name = _requireName(displayName);
    await _guard(() async {
      final cred = await _auth.signInAnonymously();
      await cred.user!.updateDisplayName(name);
      await _writeProfile(cred.user!, displayName: name, isGuest: true);
    });
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> updateDisplayName(String displayName) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final name = _requireName(displayName);
    await _guard(() async {
      await user.updateDisplayName(name);
      await _users.doc(user.uid).set(
        {'displayName': name, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    });
  }

  // ---------------------------------------------------------------------
  // FCM token yonetimi
  // ---------------------------------------------------------------------

  Future<void> registerFcmToken(String token) async {
    final id = uid;
    if (id == null) return;
    await _users.doc(id).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unregisterFcmToken(String token) async {
    final id = uid;
    if (id == null) return;
    await _users.doc(id).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------
  // Ic isleyis
  // ---------------------------------------------------------------------

  void _onAuthStateChanged(User? user) {
    _profileSub?.cancel();
    _profileSub = null;

    if (user == null) {
      _profile = null;
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    _status = AuthStatus.signedIn;
    _profileSub = _users.doc(user.uid).snapshots().listen(
      (doc) {
        _profile = doc.exists
            ? AppUser.fromDoc(doc)
            // Dokuman henuz yazilmadiysa Auth'taki isimle gecici profil kur.
            : AppUser(
                id: user.uid,
                displayName: user.displayName ?? 'Isimsiz uye',
                email: user.email,
                isGuest: user.isAnonymous,
              );
        notifyListeners();
      },
      onError: (Object error) {
        debugPrint('Profil dinlenemedi: $error');
      },
    );
    notifyListeners();
  }

  Future<void> _ensureProfile(User user) async {
    final doc = await _users.doc(user.uid).get();
    if (doc.exists) return;
    await _writeProfile(
      user,
      displayName: user.displayName ?? 'Isimsiz uye',
      isGuest: user.isAnonymous,
    );
  }

  Future<void> _writeProfile(
    User user, {
    required String displayName,
    required bool isGuest,
  }) {
    return _users.doc(user.uid).set({
      'displayName': displayName,
      'email': user.email,
      'isGuest': isGuest,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _requireName(String value) {
    final name = value.trim();
    if (name.isEmpty) {
      throw const AuthFailure('Lutfen bir isim gir.');
    }
    if (name.length > 40) {
      throw const AuthFailure('Isim en fazla 40 karakter olabilir.');
    }
    return name;
  }

  /// FirebaseAuthException'lari okunabilir [AuthFailure]'a cevirir.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e));
    }
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'E-posta adresi gecersiz.';
      case 'email-already-in-use':
        return 'Bu e-posta ile zaten bir hesap var. Giris yapmayi dene.';
      case 'weak-password':
        return 'Sifre en az 6 karakter olmali.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-posta veya sifre hatali.';
      case 'too-many-requests':
        return 'Cok fazla deneme yapildi. Biraz sonra tekrar dene.';
      case 'network-request-failed':
        return 'Internet baglantisi kurulamadi.';
      case 'operation-not-allowed':
        return 'Bu giris yontemi Firebase Console\'da acik degil.';
      default:
        return e.message ?? 'Giris yapilamadi (${e.code}).';
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
