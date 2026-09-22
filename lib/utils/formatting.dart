import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/note_service.dart';
import '../services/session_service.dart';

/// Tarihi "az once / 5 dk once / dun 14:30 / 3 Mart 14:30" seklinde yazar.
String formatRelative(DateTime? time, {DateTime? now}) {
  if (time == null) return 'gonderiliyor…';

  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);

  if (diff.isNegative || diff.inSeconds < 45) return 'az once';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk once';
  if (diff.inHours < 24 && _isSameDay(time, reference)) {
    return '${diff.inHours} sa once';
  }

  final yesterday = reference.subtract(const Duration(days: 1));
  if (_isSameDay(time, yesterday)) {
    return 'dun ${DateFormat.Hm('tr').format(time)}';
  }
  if (time.year == reference.year) {
    return DateFormat('d MMMM HH:mm', 'tr').format(time);
  }
  return DateFormat('d MMMM y', 'tr').format(time);
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Katilma kodunu okunakli hale getirir: ABC123 -> ABC-123
String formatJoinCode(String code) {
  if (code.length != 6) return code;
  return '${code.substring(0, 3)}-${code.substring(3)}';
}

/// Servislerden gelen hatalari kullaniciya gosterilecek metne cevirir.
///
/// Bilinen hata tipleri kendi Turkce mesajlarini tasir; digerleri icin
/// genel bir mesaj dondururuz (ham Firebase hatasi kullaniciya gosterilmez).
String describeError(Object error) {
  if (error is AuthFailure) return error.message;
  if (error is SessionFailure) return error.message;
  if (error is NoteFailure) return error.message;

  final text = error.toString();
  if (text.contains('permission-denied')) {
    return 'Bu islem icin yetkin yok.';
  }
  if (text.contains('unavailable') || text.contains('network')) {
    return 'Baglanti kurulamadi. Internetini kontrol et.';
  }
  return 'Beklenmeyen bir hata olustu. Tekrar dene.';
}
