import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/note.dart';
import 'notification_relay.dart';

/// Kullaniciya gosterilebilecek, Turkce mesajli not hatasi.
class NoteFailure implements Exception {
  const NoteFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Bir oturumun notlari uzerindeki islemler.
///
/// Her yazma, oturumun `updatedAt` alanini da tazeler; oturum listesi
/// bu alana gore siralandigi icin hareketli oturumlar ustte kalir.
class NoteService {
  NoteService({FirebaseFirestore? firestore, NotificationRelay? relay})
      : _db = firestore ?? FirebaseFirestore.instance,
        _relay = relay ?? NotificationRelay();

  final FirebaseFirestore _db;
  final NotificationRelay _relay;

  static const int maxNoteLength = 2000;

  DocumentReference<Map<String, dynamic>> _sessionRef(String sessionId) =>
      _db.collection('sessions').doc(sessionId);

  CollectionReference<Map<String, dynamic>> _notesRef(String sessionId) =>
      _sessionRef(sessionId).collection('notes');

  /// Oturumun notlarini canli izler (en yeni ustte).
  ///
  /// `createdAt` bir sunucu zaman damgasi oldugu icin, yeni eklenen notta
  /// sunucu onayi gelene kadar `null` okunur. Sorgunun sirasina birakirsak
  /// bekleyen not bir an listenin dibinde gorunup sonra basa zipliyor; bu
  /// yuzden damgasi olmayan notlari yerel olarak en uste aliyoruz.
  Stream<List<Note>> watchNotes(String sessionId) {
    return _notesRef(sessionId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => sortNewestFirst(snap.docs.map(Note.fromDoc)));
  }

  /// En yeni ustte; henuz sunucuya islenmemis notlar hepsinden once.
  @visibleForTesting
  static List<Note> sortNewestFirst(Iterable<Note> notes) {
    final sorted = notes.toList();
    sorted.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) return 0;
      if (a.createdAt == null) return -1;
      if (b.createdAt == null) return 1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return sorted;
  }

  Future<void> addNote({
    required String sessionId,
    required String text,
    required AppUser author,
  }) async {
    final clean = _requireText(text);
    final noteRef = _notesRef(sessionId).doc();
    final batch = _db.batch();
    batch.set(noteRef, {
      'text': clean,
      'done': false,
      'authorId': author.id,
      'authorName': author.displayName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'doneById': null,
      'doneByName': null,
      'doneAt': null,
    });
    batch.update(_sessionRef(sessionId), {
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    // Bildirimi beklemiyoruz: not zaten kaydedildi, gonderim basarisiz olsa
    // bile yazan kisinin akisi durmamali.
    unawaited(_relay.notifyNewNote(sessionId: sessionId, noteId: noteRef.id));
  }

  /// Notu isaretler / isareti kaldirir ve kimin yaptigini kaydeder.
  Future<void> setDone({
    required String sessionId,
    required Note note,
    required bool done,
    required AppUser actor,
  }) async {
    await _notesRef(sessionId).doc(note.id).update({
      'done': done,
      'doneById': done ? actor.id : null,
      'doneByName': done ? actor.displayName : null,
      'doneAt': done ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateText({
    required String sessionId,
    required Note note,
    required String text,
  }) async {
    final clean = _requireText(text);
    if (clean == note.text) return;
    await _notesRef(sessionId).doc(note.id).update({
      'text': clean,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNote({
    required String sessionId,
    required Note note,
  }) async {
    await _notesRef(sessionId).doc(note.id).delete();
  }

  /// Isaretlenmis notlari siler.
  ///
  /// Guvenlik kurallari bir notu yalnizca **yazarinin** veya **oturum
  /// sahibinin** silmesine izin verir. Toplu yazma atomik oldugu icin, yetki
  /// disindaki bir notu listeye koyarsak tum islem reddedilir; bu yuzden
  /// silinemeyecekleri bastan ayikliyor ve sayilarini geri bildiriyoruz.
  Future<({int removed, int skipped})> clearCompleted({
    required String sessionId,
    required String uid,
    required String ownerId,
  }) async {
    final done = await _notesRef(sessionId).where('done', isEqualTo: true).get();
    if (done.docs.isEmpty) return (removed: 0, skipped: 0);

    final deletable = uid == ownerId
        ? done.docs
        : done.docs.where((doc) => doc.data()['authorId'] == uid).toList();

    for (var i = 0; i < deletable.length; i += 400) {
      final batch = _db.batch();
      for (final doc in deletable.skip(i).take(400)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    return (
      removed: deletable.length,
      skipped: done.docs.length - deletable.length,
    );
  }

  String _requireText(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      throw const NoteFailure('Not bos olamaz.');
    }
    if (text.length > maxNoteLength) {
      throw NoteFailure('Not en fazla $maxNoteLength karakter olabilir.');
    }
    return text;
  }
}
