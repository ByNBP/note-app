import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile_note_app/models/app_user.dart';
import 'package:mobile_note_app/screens/session_screen.dart';
import 'package:mobile_note_app/services/auth_service.dart';
import 'package:mobile_note_app/services/note_service.dart';
import 'package:mobile_note_app/services/notification_service.dart';
import 'package:mobile_note_app/services/session_service.dart';
import 'package:mobile_note_app/theme.dart';
import 'package:provider/provider.dart';

const _sessionId = 's-1';
const _me = (uid: 'u-1', name: 'Deniz');
const _other = (uid: 'u-2', name: 'Ayse');

void main() {
  setUpAll(() async => initializeDateFormatting('tr'));

  late FakeFirebaseFirestore db;
  late AuthService auth;

  /// Iki uyeli bir oturum, profil dokumani ve oturum acmis bir AuthService.
  ///
  /// Firestore yazmalari gercek zamanlayici kullandigi icin `testWidgets`'in
  /// sahte saati altinda degil, [WidgetTester.runAsync] icinde calismali.
  Future<void> seed(WidgetTester tester, {List<(String, String)> notes = const []}) async {
    await tester.runAsync(() async {
      db = FakeFirebaseFirestore();

      await db.collection('users').doc(_me.uid).set({
        'displayName': _me.name,
        'isGuest': false,
      });
      await db.collection('sessions').doc(_sessionId).set({
        'title': 'Kamp listesi',
        'joinCode': 'K4M9TQ',
        'ownerId': _me.uid,
        'memberIds': [_me.uid, _other.uid],
        'memberNames': {_me.uid: _me.name, _other.uid: _other.name},
      });

      final noteService = NoteService(firestore: db);
      for (final (text, authorId) in notes) {
        await noteService.addNote(
          sessionId: _sessionId,
          text: text,
          author: AppUser(
            id: authorId,
            displayName: authorId == _me.uid ? _me.name : _other.name,
          ),
        );
      }

      auth = AuthService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: _me.uid, displayName: _me.name),
        ),
        firestore: db,
      );
      // Profil dokumani dinleyicisinin ilk degeri yayinlamasini bekle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  }

  Widget wrap() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        Provider<SessionService>(create: (_) => SessionService(firestore: db)),
        Provider<NoteService>(create: (_) => NoteService(firestore: db)),
        ChangeNotifierProvider<NotificationService>(
          create: (_) => NotificationService(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SessionScreen(sessionId: _sessionId),
      ),
    );
  }

  /// Takilma durumunda dakikalarca beklemek yerine 10 saniyede hata versin.
  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );

  Future<Map<String, dynamic>> singleNote(WidgetTester tester) async {
    late Map<String, dynamic> data;
    await tester.runAsync(() async {
      final snap = await db
          .collection('sessions')
          .doc(_sessionId)
          .collection('notes')
          .get();
      data = snap.docs.single.data();
    });
    return data;
  }

  tearDown(() => auth.dispose());

  testWidgets('oturum basligini, uye sayisini ve kodu gosterir',
      (tester) async {
    await seed(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('Kamp listesi'), findsOneWidget);
    expect(find.textContaining('2 uye'), findsOneWidget);
    expect(find.textContaining('K4M-9TQ'), findsOneWidget);
  });

  testWidgets('not yokken yonlendirici bos durum gosterir', (tester) async {
    await seed(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('Ilk notu sen yaz'), findsOneWidget);
  });

  testWidgets('baska uyenin notlari da listelenir', (tester) async {
    await seed(tester, notes: [
      ('cadir al', _me.uid),
      ('uyku tulumu getir', _other.uid),
    ]);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('cadir al'), findsOneWidget);
    expect(find.text('uyku tulumu getir'), findsOneWidget);
    expect(find.text('0 / 2 tamamlandi'), findsOneWidget);
  });

  testWidgets('checkbox isaretlenince Firestore guncellenir', (tester) async {
    await seed(tester, notes: [('cadir al', _other.uid)]);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await tester.tap(find.byType(Checkbox).first);
    await settle(tester);

    final data = await singleNote(tester);
    expect(data['done'], isTrue);
    expect(data['doneById'], _me.uid, reason: 'isaretleyen ben olmaliyim');
    expect(data['authorId'], _other.uid, reason: 'yazar degismemeli');
    expect(find.text('1 / 1 tamamlandi'), findsOneWidget);
  });

  testWidgets('not yazip gonderince listeye eklenir', (tester) async {
    await seed(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'ip ve kazik');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await settle(tester);

    expect(find.text('ip ve kazik'), findsOneWidget);
    expect((await singleNote(tester))['authorName'], _me.name);
  });

  testWidgets('uyeler listesi acilir', (tester) async {
    await seed(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await tester.tap(find.byIcon(Icons.people_outline));
    await settle(tester);

    expect(find.text('Uyeler (2)'), findsOneWidget);
    expect(find.text('Oturum sahibi'), findsOneWidget);
    expect(find.text('Sen'), findsOneWidget);
    expect(find.text(_other.name), findsOneWidget);
  });

  testWidgets('silinmis oturumda sonsuz yukleme yerine mesaj gosterilir',
      (tester) async {
    await seed(tester);
    await tester.runAsync(() async {
      await db.collection('sessions').doc(_sessionId).delete();
    });

    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Bu oturum artik acik degil'), findsOneWidget);
  });

  testWidgets('uyelikten cikarilan kullaniciya erisim mesaji gosterilir',
      (tester) async {
    await seed(tester);
    await tester.runAsync(() async {
      await db.collection('sessions').doc(_sessionId).update({
        'memberIds': [_other.uid],
      });
    });

    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('Bu oturum artik acik degil'), findsOneWidget);
  });
}
