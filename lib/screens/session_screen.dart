import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/note.dart';
import '../models/note_session.dart';
import '../services/auth_service.dart';
import '../services/note_service.dart';
import '../services/session_service.dart';
import '../theme.dart';
import '../utils/formatting.dart';
import '../widgets/feedback.dart';
import '../widgets/member_avatars.dart';
import '../widgets/note_tile.dart';
import '../widgets/prompt_dialog.dart';

/// Bir oturumun not listesi: herkes not ekleyebilir, herkes isaretleyebilir.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _composerController = TextEditingController();
  final _composerFocus = FocusNode();
  bool _sending = false;
  bool _hideCompleted = false;

  @override
  void dispose() {
    _composerController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().profile;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final sessionService = context.read<SessionService>();

    return StreamBuilder<NoteSession?>(
      stream: sessionService.watchSession(widget.sessionId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MessageScaffold(
            icon: Icons.lock_outline,
            title: 'Oturuma erisilemedi',
            message: describeError(snapshot.error!),
          );
        }
        // Silinmis oturum icin akis `null` yayinlar; `hasData` o durumda da
        // false oldugu icin yukleme kontrolunu connectionState'e bagliyoruz.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = snapshot.data;
        if (session == null || !session.memberIds.contains(user.id)) {
          return const _MessageScaffold(
            icon: Icons.no_accounts_outlined,
            title: 'Bu oturum artik acik degil',
            message:
                'Oturum silinmis ya da uyelikten cikarilmis olabilirsin.',
          );
        }

        return _buildSession(context, session, user);
      },
    );
  }

  Widget _buildSession(
    BuildContext context,
    NoteSession session,
    AppUser user,
  ) {
    final notes = context.read<NoteService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Oturumlar',
          onPressed: () => context.go('/'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${session.memberCount} uye · kod ${formatJoinCode(session.joinCode)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Uyeler',
            icon: const Icon(Icons.people_outline),
            onPressed: () => _showMembers(context, session, user),
          ),
          _SessionMenu(
            session: session,
            user: user,
            hideCompleted: _hideCompleted,
            onToggleHideCompleted: () =>
                setState(() => _hideCompleted = !_hideCompleted),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ContentShell(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Note>>(
                stream: notes.watchNotes(session.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Notlar yuklenemedi',
                      message: describeError(snapshot.error!),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final all = snapshot.data!;
                  if (all.isEmpty) {
                    return EmptyState(
                      icon: Icons.edit_note_outlined,
                      title: 'Ilk notu sen yaz',
                      message:
                          'Asagidaki alana yazip gonderdiginde oturumdaki '
                          'herkes aninda gorur ve bildirim alir.',
                    );
                  }

                  final visible = _hideCompleted
                      ? all.where((n) => !n.done).toList()
                      : all;
                  final doneCount = all.where((n) => n.done).length;

                  return Column(
                    children: [
                      _ProgressHeader(
                        total: all.length,
                        done: doneCount,
                        hideCompleted: _hideCompleted,
                      ),
                      Expanded(
                        child: visible.isEmpty
                            ? const EmptyState(
                                icon: Icons.check_circle_outline,
                                title: 'Hepsi tamam',
                                message:
                                    'Tamamlanmamis not kalmadi. Gizlemeyi '
                                    'kapatarak eski notlari gorebilirsin.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 12),
                                itemCount: visible.length,
                                itemBuilder: (context, index) {
                                  final note = visible[index];
                                  return NoteTile(
                                    note: note,
                                    currentUserId: user.id,
                                    canDelete: note.authorId == user.id ||
                                        session.isOwnedBy(user.id),
                                    onToggle: (value) =>
                                        _toggle(session, note, value, user),
                                    onEdit: () => _edit(session, note),
                                    onDelete: () => _delete(session, note),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
            _Composer(
              controller: _composerController,
              focusNode: _composerFocus,
              sending: _sending,
              onSend: () => _send(session, user),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Islemler
  // ---------------------------------------------------------------------

  Future<void> _send(NoteSession session, AppUser user) async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final notes = context.read<NoteService>();
    try {
      await notes.addNote(
        sessionId: session.id,
        text: text,
        author: user,
      );
      _composerController.clear();
      _composerFocus.requestFocus();
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggle(
    NoteSession session,
    Note note,
    bool done,
    AppUser user,
  ) async {
    final notes = context.read<NoteService>();
    try {
      await notes.setDone(
        sessionId: session.id,
        note: note,
        done: done,
        actor: user,
      );
    } catch (error) {
      if (mounted) showAppError(context, error);
    }
  }

  Future<void> _edit(NoteSession session, Note note) async {
    final text = await promptText(
      context,
      title: 'Notu duzenle',
      label: 'Not',
      confirmLabel: 'Kaydet',
      initialValue: note.text,
      maxLines: 4,
    );
    if (text == null || !mounted) return;

    final notes = context.read<NoteService>();
    try {
      await notes.updateText(sessionId: session.id, note: note, text: text);
    } catch (error) {
      if (mounted) showAppError(context, error);
    }
  }

  Future<void> _delete(NoteSession session, Note note) async {
    final confirmed = await confirmAction(
      context,
      title: 'Not silinsin mi?',
      message: 'Bu islem geri alinamaz.',
      confirmLabel: 'Sil',
    );
    if (!confirmed || !mounted) return;

    final notes = context.read<NoteService>();
    try {
      await notes.deleteNote(sessionId: session.id, note: note);
      if (mounted) showAppSnack(context, 'Not silindi');
    } catch (error) {
      if (mounted) showAppError(context, error);
    }
  }

  void _showMembers(BuildContext context, NoteSession session, AppUser user) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Uyeler (${session.memberCount})',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final id in session.memberIds)
                    ListTile(
                      leading: MemberAvatar(
                        name: session.nameOf(id),
                        seed: id,
                        radius: 18,
                      ),
                      title: Text(session.nameOf(id)),
                      subtitle: session.isOwnedBy(id)
                          ? const Text('Oturum sahibi')
                          : null,
                      trailing: id == user.id
                          ? const Chip(
                              label: Text('Sen'),
                              visualDensity: VisualDensity.compact,
                            )
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Tamamlanma orani ve gizleme durumunu gosteren baslik.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.total,
    required this.done,
    required this.hideCompleted,
  });

  final int total;
  final int done;
  final bool hideCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = total == 0 ? 0.0 : done / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$done / $total tamamlandi',
                style: theme.textTheme.labelLarge,
              ),
              if (hideCompleted) ...[
                const SizedBox(width: 8),
                Icon(Icons.visibility_off_outlined,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'tamamlananlar gizli',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// Alt kisimdaki not yazma alani.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: NoteService.maxNoteLength,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Yeni not yaz…',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                width: 48,
                child: FilledButton(
                  onPressed: sending ? null : onSend,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  child: sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Oturum ust menusu.
class _SessionMenu extends StatelessWidget {
  const _SessionMenu({
    required this.session,
    required this.user,
    required this.hideCompleted,
    required this.onToggleHideCompleted,
  });

  final NoteSession session;
  final AppUser user;
  final bool hideCompleted;
  final VoidCallback onToggleHideCompleted;

  bool get _isOwner => session.isOwnedBy(user.id);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Oturum islemleri',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        switch (value) {
          case 'code':
            await _copyCode(context);
          case 'hide':
            onToggleHideCompleted();
          case 'clear':
            await _clearCompleted(context);
          case 'rename':
            await _rename(context);
          case 'leave':
            await _leave(context);
          case 'delete':
            await _delete(context);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'code',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.key_outlined),
            title: Text('Katilma kodunu kopyala'),
          ),
        ),
        PopupMenuItem(
          value: 'hide',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(hideCompleted
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            title: Text(hideCompleted
                ? 'Tamamlananlari goster'
                : 'Tamamlananlari gizle'),
          ),
        ),
        const PopupMenuItem(
          value: 'clear',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cleaning_services_outlined),
            title: Text('Tamamlananlari sil'),
          ),
        ),
        if (_isOwner)
          const PopupMenuItem(
            value: 'rename',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.drive_file_rename_outline),
              title: Text('Basligi degistir'),
            ),
          ),
        const PopupMenuDivider(),
        if (_isOwner)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline),
              title: Text('Oturumu sil'),
            ),
          )
        else
          const PopupMenuItem(
            value: 'leave',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.exit_to_app),
              title: Text('Oturumdan ayril'),
            ),
          ),
      ],
    );
  }

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: session.joinCode));
    if (context.mounted) {
      showAppSnack(
        context,
        'Kod kopyalandi: ${formatJoinCode(session.joinCode)}',
      );
    }
  }

  Future<void> _clearCompleted(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Tamamlananlar silinsin mi?',
      message: 'Isaretlenmis tum notlar kalici olarak silinecek.',
      confirmLabel: 'Sil',
    );
    if (!confirmed || !context.mounted) return;

    final notes = context.read<NoteService>();
    try {
      final result = await notes.clearCompleted(
        sessionId: session.id,
        uid: user.id,
        ownerId: session.ownerId,
      );
      if (!context.mounted) return;

      final message = switch (result) {
        (removed: 0, skipped: 0) => 'Silinecek not yoktu',
        (removed: final r, skipped: 0) => '$r not silindi',
        (removed: 0, skipped: final s) =>
          '$s not baskalarina ait oldugu icin silinemedi',
        (removed: final r, skipped: final s) =>
          '$r not silindi · $s not baskalarina ait',
      };
      showAppSnack(context, message);
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _rename(BuildContext context) async {
    final title = await promptText(
      context,
      title: 'Basligi degistir',
      label: 'Oturum basligi',
      confirmLabel: 'Kaydet',
      initialValue: session.title,
    );
    if (title == null || !context.mounted) return;

    final sessions = context.read<SessionService>();
    try {
      await sessions.renameSession(
        session: session,
        uid: user.id,
        title: title,
      );
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _leave(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Oturumdan ayril',
      message:
          'Bu oturumun notlarini artik goremeyeceksin. Kodu tekrar girerek '
          'geri katilabilirsin.',
      confirmLabel: 'Ayril',
    );
    if (!confirmed || !context.mounted) return;

    final sessions = context.read<SessionService>();
    try {
      await sessions.leaveSession(session: session, uid: user.id);
      if (context.mounted) context.go('/');
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Oturum silinsin mi?',
      message:
          '"${session.title}" oturumu ve icindeki tum notlar kalici olarak '
          'silinecek. Bu islem geri alinamaz.',
      confirmLabel: 'Sil',
    );
    if (!confirmed || !context.mounted) return;

    final sessions = context.read<SessionService>();
    try {
      await sessions.deleteSession(session: session, uid: user.id);
      if (context.mounted) context.go('/');
    } catch (error) {
      if (context.mounted) showAppError(context, error);
    }
  }
}

/// Erisim yoksa / oturum yoksa gosterilen basit ekran.
class _MessageScaffold extends StatelessWidget {
  const _MessageScaffold({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: EmptyState(
        icon: icon,
        title: title,
        message: message,
        action: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Oturumlarima don'),
        ),
      ),
    );
  }
}
