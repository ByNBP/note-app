import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile_note_app/models/app_user.dart';
import 'package:mobile_note_app/services/auth_service.dart';
import 'package:mobile_note_app/services/note_service.dart';
import 'package:mobile_note_app/utils/formatting.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('tr'));

  group('formatRelative', () {
    final now = DateTime(2026, 3, 15, 14, 30);

    test('gonderilmemis not icin bekleme metni', () {
      expect(formatRelative(null), 'gonderiliyor…');
    });

    test('bir dakikadan yeni', () {
      expect(
        formatRelative(now.subtract(const Duration(seconds: 20)), now: now),
        'az once',
      );
    });

    test('dakika', () {
      expect(
        formatRelative(now.subtract(const Duration(minutes: 12)), now: now),
        '12 dk once',
      );
    });

    test('ayni gun icinde saat', () {
      expect(
        formatRelative(now.subtract(const Duration(hours: 3)), now: now),
        '3 sa once',
      );
    });

    test('dun', () {
      expect(
        formatRelative(DateTime(2026, 3, 14, 9, 5), now: now),
        'dun 09:05',
      );
    });

    test('ayni yil icinde eski tarih', () {
      expect(
        formatRelative(DateTime(2026, 1, 8, 16, 0), now: now),
        '8 Ocak 16:00',
      );
    });

    test('gecmis yil', () {
      expect(
        formatRelative(DateTime(2025, 11, 2, 16, 0), now: now),
        '2 Kasım 2025',
      );
    });

    test('ileri tarihli damga cokmeye yol acmaz', () {
      expect(
        formatRelative(now.add(const Duration(minutes: 5)), now: now),
        'az once',
      );
    });
  });

  group('formatJoinCode', () {
    test('alti haneli kodu ikiye boler', () {
      expect(formatJoinCode('K4M9TQ'), 'K4M-9TQ');
    });

    test('beklenmedik uzunlukta kodu oldugu gibi birakir', () {
      expect(formatJoinCode('ABC'), 'ABC');
    });
  });

  group('describeError', () {
    test('bilinen hatalarin kendi mesajini kullanir', () {
      expect(describeError(const NoteFailure('Not bos olamaz.')),
          'Not bos olamaz.');
      expect(describeError(const AuthFailure('Sifre gir.')), 'Sifre gir.');
    });

    test('yetki hatasini cevirir', () {
      expect(
        describeError(Exception('permission-denied: insufficient permissions')),
        'Bu islem icin yetkin yok.',
      );
    });

    test('ham hatayi kullaniciya sizdirmaz', () {
      final message = describeError(StateError('null check operator on null'));
      expect(message, 'Beklenmeyen bir hata olustu. Tekrar dene.');
      expect(message, isNot(contains('null check')));
    });
  });

  group('AppUser.initials', () {
    test('iki kelimelik isimden bas harfleri alir', () {
      expect(const AppUser(id: 'a', displayName: 'Ayse Yilmaz').initials, 'AY');
    });

    test('tek kelimelik isimden ilk iki harfi alir', () {
      expect(const AppUser(id: 'a', displayName: 'deniz').initials, 'DE');
    });

    test('bos isim cokmeye yol acmaz', () {
      expect(const AppUser(id: 'a', displayName: '   ').initials, '?');
    });
  });
}
