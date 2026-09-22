import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_note_app/models/app_user.dart';
import 'package:mobile_note_app/models/note_session.dart';
import 'package:mobile_note_app/services/session_service.dart';

const _owner = AppUser(id: 'owner-1', displayName: 'Deniz');
const _guest = AppUser(id: 'guest-1', displayName: 'Ayse Yilmaz');

void main() {
  late FakeFirebaseFirestore db;
  late SessionService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = SessionService(firestore: db);
  });

  group('createSession', () {
    test('sahibi tek uye olarak ekler ve katilma kodu uretir', () async {
      final session = await service.createSession(
        title: '  Pazartesi toplantisi  ',
        user: _owner,
      );

      expect(session.title, 'Pazartesi toplantisi', reason: 'basligi trimler');
      expect(session.ownerId, _owner.id);
      expect(session.memberIds, [_owner.id]);
      expect(session.memberNames[_owner.id], 'Deniz');
      expect(session.joinCode, hasLength(6));
      expect(session.joinCode, matches(RegExp(r'^[A-HJ-NP-Z2-9]{6}$')),
          reason: 'karistirilabilir I/O/0/1 kullanilmamali');
    });

    test('kodu joinCodes koleksiyonuna da yazar', () async {
      final session =
          await service.createSession(title: 'Alisveris', user: _owner);

      final codeDoc = await db.collection('joinCodes').doc(session.joinCode).get();
      expect(codeDoc.exists, isTrue);
      expect(codeDoc.data()!['sessionId'], session.id);
    });

    test('bos baslik reddedilir', () {
      expect(
        () => service.createSession(title: '   ', user: _owner),
        throwsA(isA<SessionFailure>()),
      );
    });

    test('80 karakterden uzun baslik reddedilir', () {
      expect(
        () => service.createSession(title: 'a' * 81, user: _owner),
        throwsA(isA<SessionFailure>()),
      );
    });
  });

  group('joinByCode', () {
    test('kullaniciyi uye listesine ekler', () async {
      final session =
          await service.createSession(title: 'Kamp listesi', user: _owner);

      final joinedId =
          await service.joinByCode(code: session.joinCode, user: _guest);

      expect(joinedId, session.id);
      final updated = NoteSession.fromDoc(
        await db.collection('sessions').doc(session.id).get(),
      );
      expect(updated.memberIds, containsAll([_owner.id, _guest.id]));
      expect(updated.nameOf(_guest.id), 'Ayse Yilmaz');
    });

    test('bosluk ve tire iceren kodu kabul eder', () async {
      final session =
          await service.createSession(title: 'Kamp listesi', user: _owner);
      final code = session.joinCode;
      final messy = '${code.substring(0, 3)}- ${code.substring(3).toLowerCase()}';

      await service.joinByCode(code: messy, user: _guest);

      final updated = NoteSession.fromDoc(
        await db.collection('sessions').doc(session.id).get(),
      );
      expect(updated.memberIds, contains(_guest.id));
    });

    test('zaten uye olan kullanici icin uye listesi bozulmaz', () async {
      final session =
          await service.createSession(title: 'Kamp listesi', user: _owner);

      await service.joinByCode(code: session.joinCode, user: _guest);
      await service.joinByCode(code: session.joinCode, user: _guest);

      final updated = NoteSession.fromDoc(
        await db.collection('sessions').doc(session.id).get(),
      );
      expect(updated.memberIds.where((id) => id == _guest.id), hasLength(1));
    });

    test('bilinmeyen kod hata verir', () {
      expect(
        () => service.joinByCode(code: 'ZZZZZZ', user: _guest),
        throwsA(isA<SessionFailure>()),
      );
    });

    test('yanlis uzunluktaki kod hata verir', () {
      expect(
        () => service.joinByCode(code: 'AB1', user: _guest),
        throwsA(isA<SessionFailure>()),
      );
    });
  });

  group('leaveSession', () {
    test('uyeyi listeden ve isim haritasindan cikarir', () async {
      final created =
          await service.createSession(title: 'Kamp listesi', user: _owner);
      await service.joinByCode(code: created.joinCode, user: _guest);

      final withGuest = NoteSession.fromDoc(
        await db.collection('sessions').doc(created.id).get(),
      );
      await service.leaveSession(session: withGuest, uid: _guest.id);

      final after = NoteSession.fromDoc(
        await db.collection('sessions').doc(created.id).get(),
      );
      expect(after.memberIds, [_owner.id]);
      expect(after.memberNames.containsKey(_guest.id), isFalse);
    });

    test('sahip ayrilamaz', () async {
      final session =
          await service.createSession(title: 'Kamp listesi', user: _owner);

      expect(
        () => service.leaveSession(session: session, uid: _owner.id),
        throwsA(isA<SessionFailure>()),
      );
    });
  });

  group('deleteSession', () {
    test('oturumu, notlarini ve kodunu siler', () async {
      final session =
          await service.createSession(title: 'Kamp listesi', user: _owner);
      final notes = db.collection('sessions').doc(session.id).collection('notes');
      await notes.add({'text': 'cadir', 'done': false});
      await notes.add({'text': 'uyku tulumu', 'done': true});

      await service.deleteSession(session: session, uid: _owner.id);

      expect((await db.collection('sessions').doc(session.id).get()).exists,
          isFalse);
      expect((await db.collection('joinCodes').doc(session.joinCode).get()).exists,
          isFalse);
      expect((await notes.get()).docs, isEmpty);
    });

    test('sahip olmayan silemez', () async {
      final session =
          await service.createSession(title: 'Kamp listesi', user: _owner);

      expect(
        () => service.deleteSession(session: session, uid: _guest.id),
        throwsA(isA<SessionFailure>()),
      );
    });
  });

  group('watchMySessions', () {
    test('yalnizca uye olunan oturumlari yayinlar', () async {
      final mine = await service.createSession(title: 'Benim', user: _guest);
      await service.createSession(title: 'Baskasinin', user: _owner);

      final visible = await service.watchMySessions(_guest.id).first;

      expect(visible.map((s) => s.id), [mine.id]);
    });
  });

  group('syncMemberName', () {
    test('isim degisikligini tum oturumlara yansitir', () async {
      final a = await service.createSession(title: 'Bir', user: _guest);
      final b = await service.createSession(title: 'Iki', user: _guest);

      await service.syncMemberName(uid: _guest.id, displayName: 'Ayse Y.');

      for (final id in [a.id, b.id]) {
        final session = NoteSession.fromDoc(
          await db.collection('sessions').doc(id).get(),
        );
        expect(session.nameOf(_guest.id), 'Ayse Y.');
      }
    });
  });

  group('normalizeCode', () {
    test('kucuk harf, bosluk ve ayraclari temizler', () {
      expect(SessionService.normalizeCode(' k4m-9tq '), 'K4M9TQ');
    });
  });
}
