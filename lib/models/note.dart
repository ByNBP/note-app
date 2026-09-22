import 'package:cloud_firestore/cloud_firestore.dart';

/// `sessions/{sessionId}/notes/{noteId}` dokumani.
class Note {
  const Note({
    required this.id,
    required this.text,
    required this.done,
    required this.authorId,
    required this.authorName,
    this.createdAt,
    this.updatedAt,
    this.doneById,
    this.doneByName,
    this.doneAt,
  });

  final String id;
  final String text;
  final bool done;
  final String authorId;
  final String authorName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Notu kim isaretledi (isaretli degilse null).
  final String? doneById;
  final String? doneByName;
  final DateTime? doneAt;

  factory Note.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Note(
      id: doc.id,
      text: data['text'] as String? ?? '',
      done: data['done'] as bool? ?? false,
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'Bilinmeyen',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      doneById: data['doneById'] as String?,
      doneByName: data['doneByName'] as String?,
      doneAt: (data['doneAt'] as Timestamp?)?.toDate(),
    );
  }
}
