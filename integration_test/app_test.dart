// Gercek cihazda, gercek Firebase projesine karsi calisan uctan uca test.
//
//   flutter test integration_test/app_test.dart -d <cihaz-id>
//
// Firebase Console'da su ikisi acik olmali:
//   Authentication > Sign-in method > Anonim
//   Firestore Database (kurallar firestore.rules'tan yayinlanmis)
//
// Test kendi actigi oturumu ve notlarini sonunda siler.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_note_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Test sirasinda acilan oturumun id'si; sonunda temizlenir.
  String? createdSessionId;

  final sessionTitle = 'Entegrasyon testi ${DateTime.now().millisecondsSinceEpoch}';
  const noteText = 'cadir al';

  /// Canli akislar yuzunden `pumpAndSettle` oturmayabilir; verilen
  /// finder'lardan biri eslesene kadar gercek zamanda pump ediyoruz.
  ///
  /// Eslesen finder'in indeksini dondurur.
  Future<int> pumpUntilAny(
    WidgetTester tester,
    List<Finder> finders, {
    Duration timeout = const Duration(seconds: 40),
    required String what,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 120));
      for (var i = 0; i < finders.length; i++) {
        if (finders[i].evaluate().isNotEmpty) return i;
      }
    }
    fail('Zaman asimi: $what bulunamadi');
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 40),
    required String what,
  }) =>
      pumpUntilAny(tester, [finder], timeout: timeout, what: what);

  tearDownAll(() async {
    final id = createdSessionId;
    if (id == null) return;
    final db = FirebaseFirestore.instance;
    try {
      final notes = await db.collection('sessions').doc(id).collection('notes').get();
      for (final doc in notes.docs) {
        await doc.reference.delete();
      }
      final session = await db.collection('sessions').doc(id).get();
      final code = session.data()?['joinCode'] as String?;
      if (code != null) await db.collection('joinCodes').doc(code).delete();
      await db.collection('sessions').doc(id).delete();
      debugPrint('TEMIZLENDI: oturum $id');
    } catch (error) {
      debugPrint('TEMIZLIK BASARISIZ ($id): $error');
    }
  });

  testWidgets('misafir girisi → oturum ac → not ekle → isaretle', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 3));

    // --- 1. Giris ------------------------------------------------------
    // Onceki calistirmadan kalan oturum olabilir: hangi ekranin geldigini
    // bekleyerek ogreniyoruz (acilis animasyonu bitmeden karar vermiyoruz).
    final landed = await pumpUntilAny(
      tester,
      [find.text('Oturumlarim'), find.text('Misafir')],
      what: 'giris ekrani ya da oturum listesi',
    );

    if (landed == 1) {
      await tester.tap(find.text('Misafir'));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.enterText(find.byType(TextFormField).first, 'Test Kullanici');
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Misafir olarak devam et'));
      await tester.pump(const Duration(seconds: 2));

      await pumpUntil(
        tester,
        find.text('Oturumlarim'),
        what: 'oturum listesi (Anonim giris acik mi?)',
      );
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    expect(uid, isNotNull, reason: 'giris yapilamadi');
    debugPrint('GIRIS TAMAM: uid=$uid');

    // --- 2. Oturum ac --------------------------------------------------
    await tester.tap(find.text('Yeni oturum').first);
    await tester.pump(const Duration(milliseconds: 800));

    await pumpUntil(tester, find.text('Olustur'), what: 'yeni oturum diyalogu');
    await tester.enterText(find.byType(TextFormField).last, sessionTitle);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Olustur'));
    await tester.pump(const Duration(seconds: 2));

    await pumpUntil(
      tester,
      find.text('Ilk notu sen yaz'),
      what: 'yeni oturum ekrani (Firestore yazma izni var mi?)',
    );

    final sessions = await FirebaseFirestore.instance
        .collection('sessions')
        .where('memberIds', arrayContains: uid)
        .get();
    final created = sessions.docs
        .where((d) => d.data()['title'] == sessionTitle)
        .toList();
    expect(created, hasLength(1), reason: 'oturum Firestore\'a yazilmadi');
    createdSessionId = created.single.id;
    debugPrint('OTURUM ACILDI: $createdSessionId '
        'kod=${created.single.data()['joinCode']}');

    // --- 3. Not ekle ---------------------------------------------------
    await tester.enterText(find.byType(TextField).last, noteText);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(seconds: 2));

    await pumpUntil(tester, find.text(noteText), what: 'eklenen not');
    await pumpUntil(tester, find.text('0 / 1 tamamlandi'), what: 'ilerleme');
    debugPrint('NOT EKLENDI: "$noteText"');

    // --- 4. Checkbox ---------------------------------------------------
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump(const Duration(seconds: 2));
    await pumpUntil(tester, find.text('1 / 1 tamamlandi'), what: 'isaretleme');

    final notes = await FirebaseFirestore.instance
        .collection('sessions')
        .doc(createdSessionId)
        .collection('notes')
        .get();
    expect(notes.docs, hasLength(1));
    final note = notes.docs.single.data();
    expect(note['text'], noteText);
    expect(note['done'], isTrue);
    expect(note['doneById'], uid, reason: 'isaretleyen kaydedilmeli');
    expect(note['authorId'], uid);
    debugPrint('ISARETLENDI: done=${note['done']} doneBy=${note['doneByName']}');

    // --- 5. FCM token kaydi --------------------------------------------
    final profile =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final tokens = List<String>.from(profile.data()?['fcmTokens'] ?? const []);
    debugPrint('FCM TOKEN SAYISI: ${tokens.length}');
    expect(
      tokens,
      isNotEmpty,
      reason: 'push bildirimi icin cihaz token\'i kaydedilmeliydi',
    );
  });
}
