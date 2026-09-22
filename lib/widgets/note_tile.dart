import 'package:flutter/material.dart';

import '../models/note.dart';
import '../utils/formatting.dart';
import 'member_avatars.dart';

/// Tek bir notun checkbox'li satiri.
class NoteTile extends StatelessWidget {
  const NoteTile({
    super.key,
    required this.note,
    required this.currentUserId,
    required this.canDelete,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Note note;
  final String currentUserId;
  final bool canDelete;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  bool get _isMine => note.authorId == currentUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final subtitle = note.done && note.doneByName != null
        ? '${note.doneByName} tamamladi · ${formatRelative(note.doneAt)}'
        : '${_isMine ? 'Sen' : note.authorName} · ${formatRelative(note.createdAt)}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: note.done
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
          : scheme.surface,
      child: InkWell(
        onTap: () => onToggle(!note.done),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: note.done,
                onChanged: (value) => onToggle(value ?? false),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.text,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          decoration:
                              note.done ? TextDecoration.lineThrough : null,
                          color: note.done
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          MemberAvatar(
                            name: note.authorName,
                            seed: note.authorId,
                            radius: 9,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Not islemleri',
                icon: Icon(Icons.more_vert, color: scheme.outline, size: 20),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Duzenle'),
                    ),
                  ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline),
                        title: Text('Sil'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
