import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/feedback.dart';

/// `flutterfire configure` henuz calistirilmadiginda gosterilir.
///
/// Uygulamanin cokmek yerine ne yapilmasi gerektigini anlatmasi icin var.
class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key, this.error});

  /// Firebase baslatilamadiysa asil hata.
  final Object? error;

  static const List<({String title, String command, String detail})> _steps = [
    (
      title: '1. Firebase projesi ac',
      command: 'https://console.firebase.google.com',
      detail:
          'Yeni bir proje olustur. Authentication > Sign-in method altinda '
          '"E-posta/Sifre" ve "Anonim" yontemlerini etkinlestir. '
          'Firestore Database olustur.',
    ),
    (
      title: '2. FlutterFire CLI kur',
      command: 'dart pub global activate flutterfire_cli',
      detail: 'Bir kez kurulmasi yeterli.',
    ),
    (
      title: '3. Projeyi bagla',
      command: 'flutterfire configure --platforms=android,web',
      detail:
          'Bu komut lib/firebase_options.dart dosyasini gercek anahtarlarla '
          'yeniden yazar ve android/app/google-services.json dosyasini ekler.',
    ),
    (
      title: '4. Web push anahtarini gir',
      command: 'lib/firebase_options.dart > webPushVapidKey',
      detail:
          'Firebase Console > Project Settings > Cloud Messaging > '
          'Web Push certificates bolumundeki anahtar ciftini olusturup '
          'degeri buraya yapistir. Ayni degeri web/firebase-messaging-sw.js '
          'icindeki yapilandirmaya da yaz.',
    ),
    (
      title: '5. Kurallari ve fonksiyonu yayinla',
      command: 'firebase deploy --only firestore,functions',
      detail:
          'Guvenlik kurallarini ve yeni not bildirimini gonderen Cloud '
          'Function\'i yukler.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Kurulum gerekli')),
      body: ContentShell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        error == null
                            ? 'Firebase yapilandirmasi bulunamadi. Asagidaki '
                                'adimlari tamamladiktan sonra uygulamayi '
                                'yeniden baslat.'
                            : 'Firebase baslatilamadi:\n$error',
                        style: TextStyle(
                            color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (final step in _steps) _StepCard(step: step),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step});

  final ({String title, String command, String detail}) step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(step.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: step.command));
                if (context.mounted) {
                  showAppSnack(context, 'Kopyalandi');
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        step.command,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Icon(Icons.copy_rounded,
                        size: 16, color: theme.colorScheme.outline),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              step.detail,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
