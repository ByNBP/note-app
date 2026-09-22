import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/note_session.dart';

/// Kullaniciya gosterilebilecek, Turkce mesajli oturum hatasi.
class SessionFailure implements Exception {
  const SessionFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Oturum (session) olusturma, katilma, ayrilma ve silme islemleri.
///
/// Katilma kodlari ayri bir `joinCodes` koleksiyonunda tutulur; boylece
/// oturumu henuz okuyamayan bir kullanici koddan `sessionId`ye ulasabilir.
class SessionService {
  SessionService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Karistirilmasi kolay karakterler (I, O, 0, 1) bilerek disarida birakildi.
  static const String _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int _codeLength = 6;
  static const int _codeAttempts = 5;

  final Random _random = Random.secure();

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('sessions');
  CollectionReference<Map<String, dynamic>> get _joinCodes =>
      _db.collection('joinCodes');

  // ---------------------------------------------------------------------
  // Okuma
  // ---------------------------------------------------------------------

  /// Kullanicinin uyesi oldugu oturumlar, son hareket tarihine gore.
  Stream<List<NoteSession>> watchMySessions(String uid) {
    return _sessions
        .where('memberIds', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(NoteSession.fromDoc).toList());
  }

  /// Tek bir oturumu canli izler. Oturum silindiyse veya kullanici
  /// cikarildiysa `null` yayinlar.
  Stream<NoteSession?> watchSession(String sessionId) {
    return _sessions
        .doc(sessionId)
        .snapshots()
        .map((doc) => doc.exists ? NoteSession.fromDoc(doc) : null);
  }

  // ---------------------------------------------------------------------
  // Yazma
  // ---------------------------------------------------------------------

  /// Yeni oturum acar ve benzersiz bir katilma kodu uretir.
  Future<NoteSession> createSession({
    required String title,
    required AppUser user,
  }) async {
    final cleanTitle = _requireTitle(title);
    final code = await _reserveJoinCode();
    final sessionRef = _sessions.doc();

    final batch = _db.batch();
    batch.set(sessionRef, {
      'title': cleanTitle,
      'joinCode': code,
      'ownerId': user.id,
      'memberIds': [user.id],
      'memberNames': {user.id: user.displayName},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_joinCodes.doc(code), {
      'sessionId': sessionRef.id,
      'ownerId': user.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    final doc = await sessionRef.get();
    return NoteSession.fromDoc(doc);
  }

  /// Katilma kodu ile oturuma dahil olur; zaten uyeyse sadece id doner.
  Future<String> joinByCode({
    required String code,
    required AppUser user,
  }) async {
    final clean = normalizeCode(code);
    if (clean.length != _codeLength) {
      throw SessionFailure('Kod $_codeLength karakter olmali.');
    }

    final codeDoc = await _joinCodes.doc(clean).get();
    if (!codeDoc.exists) {
      throw const SessionFailure('Bu koda ait bir oturum bulunamadi.');
    }

    final sessionId = codeDoc.data()!['sessionId'] as String?;
    if (sessionId == null) {
      throw const SessionFailure('Kod kaydi bozuk. Oturum sahibine danis.');
    }

    // Oturum dokumanini ONCE OKUMUYORUZ: guvenlik kurallari oturumu yalnizca
    // uyelerine okutur, katilmak isteyen kisi ise henuz uye degil. Bunun
    // yerine dogrudan yaziyoruz; kurallar sunucu tarafinda mevcut hali
    // gorebildigi icin dogrulamayi onlar yapiyor:
    //   - yeni uye  -> memberIds eskisi + [uid] olur, `isJoining` gecer
    //   - zaten uye -> arrayUnion bir sey degistirmez, `isMemberTouch` gecer
    try {
      await _sessions.doc(sessionId).update({
        'memberIds': FieldValue.arrayUnion([user.id]),
        'memberNames.${user.id}': user.displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        throw const SessionFailure('Oturum silinmis.');
      }
      rethrow;
    }

    return sessionId;
  }

  /// Uye oturumdan ayrilir. Sahip ayrilamaz; oturumu silmesi gerekir.
  Future<void> leaveSession({
    required NoteSession session,
    required String uid,
  }) async {
    if (session.isOwnedBy(uid)) {
      throw const SessionFailure(
        'Oturumun sahibisin. Ayrilmak yerine oturumu silebilirsin.',
      );
    }
    await _sessions.doc(session.id).update({
      'memberIds': FieldValue.arrayRemove([uid]),
      'memberNames.$uid': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Oturumu, notlarini ve katilma kodunu siler. Sadece sahip cagirabilir.
  Future<void> deleteSession({
    required NoteSession session,
    required String uid,
  }) async {
    if (!session.isOwnedBy(uid)) {
      throw const SessionFailure('Oturumu yalnizca sahibi silebilir.');
    }

    // Alt koleksiyon otomatik silinmez; notlari parcalar halinde temizliyoruz.
    final notes = _sessions.doc(session.id).collection('notes');
    while (true) {
      final chunk = await notes.limit(400).get();
      if (chunk.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in chunk.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (chunk.docs.length < 400) break;
    }

    final batch = _db.batch();
    if (session.joinCode.isNotEmpty) {
      batch.delete(_joinCodes.doc(session.joinCode));
    }
    batch.delete(_sessions.doc(session.id));
    await batch.commit();
  }

  /// Oturum basligini degistirir. Sadece sahip cagirabilir.
  Future<void> renameSession({
    required NoteSession session,
    required String uid,
    required String title,
  }) async {
    if (!session.isOwnedBy(uid)) {
      throw const SessionFailure('Basligi yalnizca oturum sahibi degistirebilir.');
    }
    await _sessions.doc(session.id).update({
      'title': _requireTitle(title),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Kullanici ismini degistirdiginde, uyesi oldugu oturumlardaki
  /// denormalize edilmis ismi de gunceller.
  Future<void> syncMemberName({
    required String uid,
    required String displayName,
  }) async {
    final mine = await _sessions.where('memberIds', arrayContains: uid).get();
    if (mine.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in mine.docs) {
      batch.update(doc.reference, {'memberNames.$uid': displayName});
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------
  // Yardimcilar
  // ---------------------------------------------------------------------

  /// Kullanicinin girdigi kodu normalize eder (bosluk/tire temizler).
  static String normalizeCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Bos bir kod bulana kadar dener; tum denemeler tutulursa hata verir.
  Future<String> _reserveJoinCode() async {
    for (var attempt = 0; attempt < _codeAttempts; attempt++) {
      final code = _randomCode();
      final existing = await _joinCodes.doc(code).get();
      if (!existing.exists) return code;
    }
    throw const SessionFailure(
      'Katilma kodu uretilemedi. Lutfen tekrar dene.',
    );
  }

  String _randomCode() => List.generate(
        _codeLength,
        (_) => _codeAlphabet[_random.nextInt(_codeAlphabet.length)],
      ).join();

  String _requireTitle(String value) {
    final title = value.trim();
    if (title.isEmpty) {
      throw const SessionFailure('Oturum basligi bos olamaz.');
    }
    if (title.length > 80) {
      throw const SessionFailure('Baslik en fazla 80 karakter olabilir.');
    }
    return title;
  }
}
