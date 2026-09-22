import 'package:cloud_firestore/cloud_firestore.dart';

/// `sessions/{sessionId}` dokumani.
///
/// [memberIds] guvenlik kurallari ve sorgular icin duz bir liste,
/// [memberNames] ise ekranda isim gosterebilmek icin denormalize edilmis
/// `uid -> isim` haritasi.
class NoteSession {
  const NoteSession({
    required this.id,
    required this.title,
    required this.joinCode,
    required this.ownerId,
    required this.memberIds,
    required this.memberNames,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String joinCode;
  final String ownerId;
  final List<String> memberIds;
  final Map<String, String> memberNames;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory NoteSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return NoteSession(
      id: doc.id,
      title: data['title'] as String? ?? 'Isimsiz oturum',
      joinCode: data['joinCode'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      memberIds: List<String>.from(data['memberIds'] as List? ?? const []),
      memberNames: Map<String, String>.from(
        (data['memberNames'] as Map?) ?? const {},
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool isOwnedBy(String uid) => ownerId == uid;

  String nameOf(String uid) => memberNames[uid] ?? 'Ayrilmis uye';

  int get memberCount => memberIds.length;
}
