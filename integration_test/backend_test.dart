// Gercek Firebase projesine karsi, arayuze hic dokunmadan calisan test.
//
//   flutter test integration_test/backend_test.dart -d <cihaz-id>
//
// Amaci yayinlanmis `firestore.rules` kurallarini dogrulamak: kim neyi
// okuyabiliyor, kim neyi yazabiliyor. Sahte Firestore ile yapilan birim
// testleri kurallari calistirmadigi icin bu testin yeri ayri.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_note_app/firebase_options.dart';
import 'package:mobile_note_app/models/app_user.dart';
import 'package:mobile_note_app/models/note.dart';
import 'package:mobile_note_app/services/auth_service.dart';
import 'package:mobile_note_app/services/note_service.dart';
import 'package:mobile_note_app/services/session_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AuthService auth;
  late SessionService sessions;
  late NoteService notes;
  late FirebaseFirestore db;

  setUpAll(() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    db = FirebaseFirestore.instance;
    auth = AuthService();
    sessions = SessionService();
    notes = NoteService();
  });

  /// Test boyunca acilan hesaplar; sonunda hepsi siliniyor.
  final createdAccounts = <({String email, String password})>[];

  Future<AppUser> awaitProfile(String name) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final profile = auth.profile;
      if (profile != null && profile.displayName == name) return profile;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    fail('Profil yuklenemedi: $name');
  }

  /// Yeni bir e-posta/sifre hesabi acar ve profil dokumani yazilana kadar
  /// bekler. (Projede anonim giris kapali oldugu icin misafir yolu degil
  /// bu yol kullaniliyor.)
  Future<({AppUser user, String email, String password})> createAccount(
    String name,
  ) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final email = 'it-${stamp}_${name.hashCode.abs()}@ortaknotlar.test';
    const password = 'Test123456';

    await auth.signUp(email: email, password: password, displayName: name);
    createdAccounts.add((email: email, password: password));
    final user = await awaitProfile(name);
    return (user: user, email: email, password: password);
  }

  /// Daha once acilmis bir hesaba geri doner.
  Future<AppUser> signInBack(String email, String password, String name) async {
    await auth.signIn(email: email, password: password);
    return awaitProfile(name);
  }

  /// Acilan tum test hesaplarini siler.
  Future<void> deleteAccounts() async {
    for (final account in createdAccounts) {
      try {
        await auth.signIn(email: account.email, password: account.password);
        final uid = FirebaseAuth.instance.currentUser!.uid;
        // Once profil dokumani, sonra hesap: hesap silinince dokumani
        // silecek yetkili kimse kalmiyor.
        await db.collection('users').doc(uid).delete();
        await FirebaseAuth.instance.currentUser?.delete();
      } catch (error) {
        debugPrint('Hesap silinemedi (${account.email}): $error');
      }
    }
    createdAccounts.clear();
  }

  tearDownAll(() async {
    await deleteAccounts();
    auth.dispose();
  });

  test('kayit olan kullanici profil dokumani yazabiliyor', () async {
    final account = await createAccount('Test A');

    final doc = await db.collection('users').doc(account.user.id).get();
    expect(doc.exists, isTrue, reason: 'users/{uid} yazilamadi');
    expect(doc.data()!['displayName'], 'Test A');
    expect(doc.data()!['isGuest'], isFalse);
    debugPrint('✔ kayit + profil: uid=${account.user.id}');
  });

  test('oturum acma, not ekleme ve isaretleme uctan uca calisiyor', () async {
    final user = (await createAccount('Test A')).user;

    // --- oturum ac ---
    final session = await sessions.createSession(
      title: 'Backend testi ${DateTime.now().millisecondsSinceEpoch}',
      user: user,
    );
    expect(session.memberIds, [user.id]);
    expect(session.joinCode, hasLength(6));
    debugPrint('✔ oturum acildi: ${session.id} kod=${session.joinCode}');

    // joinCodes kaydi da yazilabildi mi?
    final codeDoc = await db.collection('joinCodes').doc(session.joinCode).get();
    expect(codeDoc.exists, isTrue, reason: 'joinCodes yazilamadi');

    // --- not ekle ---
    await notes.addNote(
      sessionId: session.id,
      text: 'cadir al',
      author: user,
    );
    var list = await notes.watchNotes(session.id).first;
    expect(list, hasLength(1));
    expect(list.single.text, 'cadir al');
    expect(list.single.done, isFalse);
    debugPrint('✔ not eklendi');

    // --- isaretle ---
    await notes.setDone(
      sessionId: session.id,
      note: list.single,
      done: true,
      actor: user,
    );
    list = await notes.watchNotes(session.id).first;
    expect(list.single.done, isTrue);
    expect(list.single.doneById, user.id);
    expect(list.single.doneByName, 'Test A');
    debugPrint('✔ isaretlendi');

    // --- oturum listesinde gorunuyor mu? (composite index testi) ---
    final mine = await sessions.watchMySessions(user.id).first;
    expect(
      mine.map((s) => s.id),
      contains(session.id),
      reason: 'memberIds+updatedAt indeksi eksik olabilir',
    );
    debugPrint('✔ oturum listesi sorgusu calisti');

    // --- temizlik ---
    await sessions.deleteSession(session: session, uid: user.id);
    expect((await db.collection('sessions').doc(session.id).get()).exists, isFalse);
    expect((await db.collection('joinCodes').doc(session.joinCode).get()).exists,
        isFalse);
    debugPrint('✔ oturum silindi');
  });

  test('ikinci kullanici kodla katilip ortak listeyi kullanabiliyor', () async {
    // --- A: oturumu acar ve bir not birakir ---
    final accountA = await createAccount('Test A');
    final userA = accountA.user;
    final session = await sessions.createSession(
      title: 'Ortak test ${DateTime.now().millisecondsSinceEpoch}',
      user: userA,
    );
    await notes.addNote(
      sessionId: session.id,
      text: 'A nin notu',
      author: userA,
    );
    debugPrint('A: oturum=${session.id} kod=${session.joinCode}');

    // --- B: baska bir kullanici olarak koda katilir ---
    await auth.signOut();
    final userB = (await createAccount('Test B')).user;
    expect(userB.id, isNot(userA.id));

    final joinedId =
        await sessions.joinByCode(code: session.joinCode, user: userB);
    expect(joinedId, session.id);
    debugPrint('✔ B kodla katildi');

    final afterJoin = await sessions.watchSession(session.id).first;
    expect(afterJoin, isNotNull, reason: 'B oturumu okuyamiyor');
    expect(afterJoin!.memberIds, containsAll([userA.id, userB.id]));
    expect(afterJoin.nameOf(userB.id), 'Test B');

    // --- B, A'nin notunu gorebiliyor mu? ---
    var list = await notes.watchNotes(session.id).first;
    expect(list.map((n) => n.text), contains('A nin notu'));
    debugPrint('✔ B, A nin notunu goruyor');

    // --- B kendi notunu ekler ---
    await notes.addNote(
      sessionId: session.id,
      text: 'B nin notu',
      author: userB,
    );
    list = await notes.watchNotes(session.id).first;
    expect(list, hasLength(2));
    debugPrint('✔ B not ekledi');

    // --- B, A'nin notunu isaretler (asil istenen davranis) ---
    final notesOfA = list.where((Note n) => n.authorId == userA.id).toList();
    expect(notesOfA, hasLength(1));
    await notes.setDone(
      sessionId: session.id,
      note: notesOfA.single,
      done: true,
      actor: userB,
    );
    list = await notes.watchNotes(session.id).first;
    final toggled = list.firstWhere((n) => n.authorId == userA.id);
    expect(toggled.done, isTrue);
    expect(toggled.doneById, userB.id);
    expect(toggled.authorId, userA.id, reason: 'yazar degismemeli');
    debugPrint('✔ B, A nin notunu isaretledi');

    // --- B, A'nin notunu silemez (kural kontrolu) ---
    await expectLater(
      notes.deleteNote(sessionId: session.id, note: toggled),
      throwsA(isA<FirebaseException>()),
      reason: 'B baskasinin notunu silememeli',
    );
    debugPrint('✔ B, A nin notunu silemedi (beklenen)');

    // --- B, oturum basligini degistiremez (kural kontrolu) ---
    await expectLater(
      db.collection('sessions').doc(session.id).update({'title': 'ele gecti'}),
      throwsA(isA<FirebaseException>()),
      reason: 'sahibi olmayan basligi degistirememeli',
    );
    debugPrint('✔ B basligi degistiremedi (beklenen)');

    // --- B ayrilir ---
    await sessions.leaveSession(session: afterJoin, uid: userB.id);
    debugPrint('✔ B ayrildi');

    // Ayrilan uye oturumu artik okuyamamali (kural kontrolu).
    await expectLater(
      db.collection('sessions').doc(session.id).get(),
      throwsA(isA<FirebaseException>()),
      reason: 'ayrilan uye oturumu okuyabiliyor',
    );
    debugPrint('✔ ayrilan B oturumu okuyamiyor (beklenen)');

    // --- A'ya geri don: ayrilma gercekten islenmis mi? ---
    await auth.signOut();
    await signInBack(accountA.email, accountA.password, 'Test A');

    final toDelete = await sessions.watchSession(session.id).first;
    expect(toDelete, isNotNull);
    expect(
      toDelete!.memberIds,
      isNot(contains(userB.id)),
      reason: 'B uye listesinden cikmamis',
    );
    expect(toDelete.memberIds, contains(userA.id));

    // B'nin ekledigi not oturumda kalmali (uye ayrilsa da notlar kalir).
    final remaining = await notes.watchNotes(session.id).first;
    expect(remaining.map((n) => n.text), containsAll(['A nin notu', 'B nin notu']));
    debugPrint('✔ A geri dondu, B listeden cikmis, notlar duruyor');

    // --- temizlik ---
    await sessions.deleteSession(session: toDelete, uid: userA.id);
    expect((await db.collection('sessions').doc(session.id).get()).exists,
        isFalse);
    expect(
      (await db.collection('joinCodes').doc(session.joinCode).get()).exists,
      isFalse,
    );
    debugPrint('✔ oturum ve kod temizlendi');
  });
}
