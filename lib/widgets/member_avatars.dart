import 'package:flutter/material.dart';

import '../models/note_session.dart';

/// Bir ismi her zaman ayni renge esleyen deterministik palet.
Color avatarColorFor(String seed, ColorScheme scheme) {
  const palette = <Color>[
    Color(0xFF3D5AFE),
    Color(0xFF00897B),
    Color(0xFFD81B60),
    Color(0xFF6D4C41),
    Color(0xFF5E35B1),
    Color(0xFF00838F),
    Color(0xFFEF6C00),
    Color(0xFF2E7D32),
  ];
  if (seed.isEmpty) return scheme.outline;
  final hash = seed.codeUnits.fold<int>(7, (acc, unit) => (acc * 31 + unit) & 0x7fffffff);
  return palette[hash % palette.length];
}

String initialsOf(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String head(String s, int n) =>
      (s.length <= n ? s : s.substring(0, n)).toUpperCase();
  if (parts.length == 1) return head(parts.first, 2);
  return '${head(parts.first, 1)}${head(parts.last, 1)}';
}

/// Tek bir uye rozeti.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.radius = 16,
  });

  final String name;
  final String seed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = avatarColorFor(seed, scheme);
    return Tooltip(
      message: name,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Text(
          initialsOf(name),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: radius * 0.72,
          ),
        ),
      ),
    );
  }
}

/// Oturum uyelerini ust uste binen rozetler halinde gosterir.
class MemberAvatarStack extends StatelessWidget {
  const MemberAvatarStack({
    super.key,
    required this.session,
    this.maxVisible = 4,
    this.radius = 14,
  });

  final NoteSession session;
  final int maxVisible;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ids = session.memberIds;
    final visible = ids.take(maxVisible).toList();
    final overflow = ids.length - visible.length;
    final step = radius * 1.45;

    return SizedBox(
      height: radius * 2,
      width: visible.isEmpty
          ? 0
          : step * (visible.length - 1) + radius * 2 + (overflow > 0 ? step : 0),
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: MemberAvatar(
                  name: session.nameOf(visible[i]),
                  seed: visible[i],
                  radius: radius,
                ),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: step * visible.length,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: CircleAvatar(
                  radius: radius,
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: Text(
                    '+$overflow',
                    style: TextStyle(
                      fontSize: radius * 0.7,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
