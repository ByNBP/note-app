import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_note_app/models/app_user.dart';
import 'package:mobile_note_app/models/note.dart';
import 'package:mobile_note_app/services/note_service.dart';
import 'package:mobile_note_app/services/notification_relay.dart';

const _author = AppUser(id: 'u-1', displayName: 'Deniz');
const _other = AppUser(id: 'u-2', displayName: 'Ayse');
const _sessionId = 's-1';

/// Relay'e gidecek cagrilari kaydeder; ag'a cikmaz.
class _RecordingRelay extends NotificationRelay {
  _RecordingRelay() : super(endpoint: 'https://relay.test');

  final List<(String sessionId, String noteId)> calls = [];

  @override
  Future<void> notifyNewNote({
    required String sessionId,
    required String noteId,
  }) async {
    calls.add((sessionId, noteId));
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late NoteService service;

  setUp(() async {
    db = FakeFirebaseFirestore();
    service = NoteService(firestore: db);
    await db.collection('sessions').doc(_sessionId).set({
      'title': 'Kamp listesi',
      'memberIds': [_author.id, _other.id],
    });
  });

  Future<List<Note>> readNotes() async {
    final snap = await db
        .collection('sessions')
        .doc(_sessionId)
        .collection('notes')
        .get();
    return snap.docs.map(Note.fromDoc).toList();
  }

  group('addNote', () {
    test('notu yazar ve yazari kaydeder', () async {
      await service.addNote(
        sessionId: _sessionId,
        text: '  cadir al  ',
        author: _author,
      );

      final notes = await readNotes();
      expect(notes, hasLength(1));
      expect(notes.single.text, 'cadir al', reason: 'bosluklari trimler');
      expect(notes.single.done, isFalse);
      expect(notes.single.authorId, _author.id);
      expect(notes.single.authorName, 'Deniz');
    });

    test('oturumun updatedAt alanini tazeler', () async {
      await service.addNote(
        sessionId: _sessionId,
        text: 'uyku tulumu',
        author: _author,
      );

      final session = await db.collection('sessions').doc(_sessionId).get();
      expect(session.data()!['updatedAt'], isNotNull);
    });

    test('yazildiktan sonra bildirim relay\'ini tetikler', () async {
      final relay = _RecordingRelay();
      final service = NoteService(firestore: db, relay: relay);

      await service.addNote(
        sessionId: _sessionId,
        text: 'ip al',
        author: _author,
      );

      final notes = await readNotes();
      expect(relay.calls, hasLength(1));
      expect(relay.calls.single.$1, _sessionId);
      expect(
        relay.calls.single.$2,
        notes.single.id,
        reason: 'relay yeni notun id\'sini almali',
      );
    });

    test('not reddedilirse relay tetiklenmez', () async {
      final relay = _RecordingRelay();
      final service = NoteService(firestore: db, relay: relay);

      await expectLater(
        () => service.addNote(
          sessionId: _sessionId,
          text: '   ',
          author: _author,
        ),
        throwsA(isA<NoteFailure>()),
      );

      expect(relay.calls, isEmpty);
    });

    test('bos not reddedilir', () {
      expect(
        () => service.addNote(
          sessionId: _sessionId,
          text: '   ',
          author: _author,
        ),
        throwsA(isA<NoteFailure>()),
      );
    });

    test('cok uzun not reddedilir', () {
      expect(
        () => service.addNote(
          sessionId: _sessionId,
          text: 'a' * (NoteService.maxNoteLength + 1),
          author: _author,
        ),
        throwsA(isA<NoteFailure>()),
      );
    });
  });

  group('setDone', () {
    test('baskasinin notunu isaretleyebilir ve kimin yaptigini yazar',
        () async {
      await service.addNote(
        sessionId: _sessionId,
        text: 'cadir al',
        author: _author,
      );
      final note = (await readNotes()).single;

      await service.setDone(
        sessionId: _sessionId,
        note: note,
        done: true,
        actor: _other,
      );

      final updated = (await readNotes()).single;
      expect(updated.done, isTrue);
      expect(updated.doneById, _other.id);
      expect(updated.doneByName, 'Ayse');
      expect(updated.authorId, _author.id, reason: 'yazar degismemeli');
    });

    test('isaret kaldirilinca tamamlayan bilgisi temizlenir', () async {
      await service.addNote(
        sessionId: _sessionId,
        text: 'cadir al',
        author: _author,
      );
      var note = (await readNotes()).single;
      await service.setDone(
        sessionId: _sessionId,
        note: note,
        done: true,
        actor: _other,
      );

      note = (await readNotes()).single;
      await service.setDone(
        sessionId: _sessionId,
        note: note,
        done: false,
        actor: _author,
      );

      final updated = (await readNotes()).single;
      expect(updated.done, isFalse);
      expect(updated.doneById, isNull);
      expect(updated.doneByName, isNull);
      expect(updated.doneAt, isNull);
    });
  });

  group('updateText', () {
    test('metni gunceller', () async {
      await service.addNote(
        sessionId: _sessionId,
        text: 'cadir',
        author: _author,
      );
      final note = (await readNotes()).single;

      await service.updateText(
        sessionId: _sessionId,
        note: note,
        text: 'cadir ve mat',
      );

      expect((await readNotes()).single.text, 'cadir ve mat');
    });

    test('bos metin reddedilir', () async {
      await service.addNote(
        sessionId: _sessionId,
        text: 'cadir',
        author: _author,
      );
      final note = (await readNotes()).single;

      expect(
        () => service.updateText(sessionId: _sessionId, note: note, text: ' '),
        throwsA(isA<NoteFailure>()),
      );
    });
  });

  group('clearCompleted', () {
    /// [texts] icindeki her notu ekler ve hepsini isaretler.
    Future<void> addDoneNotes(Map<String, AppUser> texts) async {
      for (final entry in texts.entries) {
        await service.addNote(
          sessionId: _sessionId,
          text: entry.key,
          author: entry.value,
        );
      }
      for (final note in await readNotes()) {
        await service.setDone(
          sessionId: _sessionId,
          note: note,
          done: true,
          actor: note.authorId == _author.id ? _author : _other,
        );
      }
    }

    test('yalnizca isaretli notlari siler', () async {
      for (final text in ['a', 'b', 'c']) {
        await service.addNote(
          sessionId: _sessionId,
          text: text,
          author: _author,
        );
      }
      for (final note in (await readNotes()).take(2)) {
        await service.setDone(
          sessionId: _sessionId,
          note: note,
          done: true,
          actor: _author,
        );
      }

      final result = await service.clearCompleted(
        sessionId: _sessionId,
        uid: _author.id,
        ownerId: _author.id,
      );

      expect(result.removed, 2);
      expect(result.skipped, 0);
      final rest = await readNotes();
      expect(rest, hasLength(1));
      expect(rest.single.done, isFalse);
    });

    test('oturum sahibi herkesin notunu temizleyebilir', () async {
      await addDoneNotes({'benim': _author, 'onun': _other});

      final result = await service.clearCompleted(
        sessionId: _sessionId,
        uid: _author.id,
        ownerId: _author.id,
      );

      expect(result.removed, 2);
      expect(result.skipped, 0);
      expect(await readNotes(), isEmpty);
    });

    test('sahip olmayan uye yalnizca kendi notlarini temizler', () async {
      await addDoneNotes({'benim': _other, 'sahibin': _author});

      final result = await service.clearCompleted(
        sessionId: _sessionId,
        uid: _other.id,
        ownerId: _author.id,
      );

      expect(result.removed, 1);
      expect(result.skipped, 1, reason: 'sahibin notuna dokunamaz');
      final rest = await readNotes();
      expect(rest.single.authorId, _author.id);
    });

    test('isaretli not yoksa sifir doner', () async {
      await service.addNote(
        sessionId: _sessionId,
        text: 'a',
        author: _author,
      );

      final result = await service.clearCompleted(
        sessionId: _sessionId,
        uid: _author.id,
        ownerId: _author.id,
      );

      expect(result.removed, 0);
      expect(result.skipped, 0);
    });
  });

  group('sortNewestFirst', () {
    Note noteAt(String id, DateTime? createdAt) => Note(
          id: id,
          text: id,
          done: false,
          authorId: _author.id,
          authorName: _author.displayName,
          createdAt: createdAt,
        );

    test('en yeni not basta gelir', () {
      final sorted = NoteService.sortNewestFirst([
        noteAt('eski', DateTime(2026, 3, 1)),
        noteAt('yeni', DateTime(2026, 3, 5)),
        noteAt('orta', DateTime(2026, 3, 3)),
      ]);

      expect(sorted.map((n) => n.id), ['yeni', 'orta', 'eski']);
    });

    test('sunucu damgasi henuz gelmemis not en uste alinir', () {
      final sorted = NoteService.sortNewestFirst([
        noteAt('eski', DateTime(2026, 3, 1)),
        noteAt('bekleyen', null),
        noteAt('yeni', DateTime(2026, 3, 5)),
      ]);

      expect(sorted.first.id, 'bekleyen');
      expect(sorted.map((n) => n.id), ['bekleyen', 'yeni', 'eski']);
    });
  });

  group('deleteNote', () {
    test('notu siler', () async {
      await service.addNote(
        sessionId: _sessionId,
        text: 'cadir',
        author: _author,
      );
      final note = (await readNotes()).single;

      await service.deleteNote(sessionId: _sessionId, note: note);

      expect(await readNotes(), isEmpty);
    });
  });
}
