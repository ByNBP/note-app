import 'package:cloud_firestore/cloud_firestore.dart';

/// `users/{uid}` dokumani: profil bilgisi ve cihaz push token'lari.
class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    this.email,
    this.isGuest = false,
    this.fcmTokens = const [],
  });

  final String id;
  final String displayName;
  final String? email;
  final bool isGuest;
  final List<String> fcmTokens;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return AppUser(
      id: doc.id,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? data['displayName'] as String
          : 'Isimsiz uye',
      email: data['email'] as String?,
      isGuest: data['isGuest'] as bool? ?? false,
      fcmTokens: List<String>.from(data['fcmTokens'] as List? ?? const []),
    );
  }

  /// Profil icin baş harfler (avatar rozetinde kullaniliyor).
  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.firstChars(2);
    return '${parts.first.firstChars(1)}${parts.last.firstChars(1)}';
  }
}

extension on String {
  /// Ilk [n] karakteri buyuk harfe cevirerek dondurur; kisa metinlerde tasmaz.
  String firstChars(int n) =>
      (length <= n ? this : substring(0, n)).toUpperCase();
}
