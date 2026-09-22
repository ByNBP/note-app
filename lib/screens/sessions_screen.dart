import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/note_session.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../theme.dart';
import '../utils/formatting.dart';
import '../widgets/feedback.dart';
import '../widgets/member_avatars.dart';
import '../widgets/prompt_dialog.dart';

/// Kullanicinin uyesi oldugu oturumlarin listesi.
class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.profile;
    final sessions = context.read<SessionService>();

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Oturumlarim'),
        actions: [
          IconButton(
            tooltip: 'Kod ile katil',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => showJoinSessionDialog(context, user),
          ),
          _ProfileMenu(user: user),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSession(context, user),
        icon: const Icon(Icons.add),
        label: const Text('Yeni oturum'),
      ),
      body: ContentShell(
        child: Column(
          children: [
            const _NotificationPermissionBanner(),
            Expanded(
              child: StreamBuilder<List<NoteSession>>(
                stream: sessions.watchMySessions(user.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Oturumlar yuklenemedi',
                      message: describeError(snapshot.error!),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final items = snapshot.data!;
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.note_alt_outlined,
                      title: 'Henuz bir oturumun yok',
                      message:
                          'Yeni bir oturum ac ve kodu arkadaslarinla paylas, '
                          'ya da sana verilen kodla mevcut bir oturuma katil.',
                      action: Wrap(
                        spacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _createSession(context, user),
                            icon: const Icon(Icons.add),
                            label: const Text('Yeni oturum'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                showJoinSessionDialog(context, user),
                            icon: const Icon(Icons.group_add_outlined),
                            label: const Text('Kod ile katil'),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _SessionCard(
                      session: items[index],
                      currentUserId: user.id,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createSession(BuildContext context, AppUser user) async {
    final title = await promptText(
      context,
      title: 'Yeni oturum',
      label: 'Oturum basligi',
      hint: 'Orn. Pazartesi toplantisi',
      confirmLabel: 'Olustur',
    );
    if (title == null || !context.mounted) return;

    final sessions = context.read<SessionService>();
    try {
      final session = await sessions.createSession(title: title, user: user);
      if (!context.mounted) return;
      context.go('/session/${session.id}');
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }
}

/// Kod girerek oturuma katilma diyalogu. Bildirimden gelen derin
/// baglantilarda da kullanilabilsin diye disariya acik.
Future<void> showJoinSessionDialog(BuildContext context, AppUser user) async {
  final code = await promptText(
    context,
    title: 'Oturuma katil',
    label: 'Katilma kodu',
    hint: 'Orn. K4M-9TQ',
    confirmLabel: 'Katil',
    capitalize: true,
  );
  if (code == null || !context.mounted) return;

  final sessions = context.read<SessionService>();
  try {
    final sessionId = await sessions.joinByCode(code: code, user: user);
    if (!context.mounted) return;
    context.go('/session/$sessionId');
  } catch (error) {
    if (context.mounted) showAppError(context, error);
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.currentUserId});

  final NoteSession session;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = session.isOwnedBy(currentUserId);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.go('/session/${session.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (isOwner)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Tooltip(
                        message: 'Bu oturumun sahibisin',
                        child: Icon(Icons.star_rounded,
                            size: 18, color: theme.colorScheme.tertiary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  MemberAvatarStack(session: session),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${session.memberCount} uye · '
                      '${formatRelative(session.updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  _JoinCodeChip(code: session.joinCode),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Katilma kodunu gosteren, tiklaninca panoya kopyalayan cip.
class _JoinCodeChip extends StatelessWidget {
  const _JoinCodeChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Kodu kopyala',
      child: ActionChip(
        avatar: const Icon(Icons.key_outlined, size: 16),
        label: Text(
          formatJoinCode(code),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) {
            showAppSnack(context, 'Kod kopyalandi: ${formatJoinCode(code)}');
          }
        },
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: user.displayName,
      icon: MemberAvatar(name: user.displayName, seed: user.id, radius: 16),
      onSelected: (value) async {
        switch (value) {
          case 'rename':
            await _rename(context);
          case 'signout':
            await _signOut(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(user.displayName),
            subtitle: Text(user.isGuest ? 'Misafir hesap' : user.email ?? ''),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'rename',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.badge_outlined),
            title: Text('Ismi degistir'),
          ),
        ),
        const PopupMenuItem(
          value: 'signout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Cikis yap'),
          ),
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context) async {
    final name = await promptText(
      context,
      title: 'Ismi degistir',
      label: 'Gorunen isim',
      confirmLabel: 'Kaydet',
      initialValue: user.displayName,
    );
    if (name == null || !context.mounted) return;

    final auth = context.read<AuthService>();
    final sessions = context.read<SessionService>();
    try {
      await auth.updateDisplayName(name);
      // Oturumlardaki denormalize isimleri de tazele.
      await sessions.syncMemberName(uid: user.id, displayName: name.trim());
      if (context.mounted) showAppSnack(context, 'Isim guncellendi');
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final auth = context.read<AuthService>();
    final notifications = context.read<NotificationService>();
    try {
      // Once bu cihazin token'ini kaldir, sonra oturumu kapat.
      await notifications.detachUser();
      await auth.signOut();
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }
}

/// Bildirim izni verilmediyse ustte uyari gosterir.
class _NotificationPermissionBanner extends StatelessWidget {
  const _NotificationPermissionBanner();

  @override
  Widget build(BuildContext context) {
    // watch: izin diyalogu cevaplandiginda bant kendiliginden kaybolsun.
    if (!context.watch<NotificationService>().isBlocked) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined,
              color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Bildirim izni kapali. Yeni notlardan haberdar olmak icin '
              'cihaz ayarlarindan izni ac.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
