import 'package:flutter/material.dart';

import '../utils/formatting.dart';

/// Kisa bilgi mesaji gosterir.
void showAppSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  SnackBarAction? action,
}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        backgroundColor: isError ? scheme.errorContainer : null,
        showCloseIcon: isError,
      ),
    );
}

/// Hata nesnesini okunakli mesaja cevirip gosterir.
void showAppError(BuildContext context, Object error) =>
    showAppSnack(context, describeError(error), isError: true);

/// Bos liste durumlari icin ortak yerlesim.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Uygulama on plandayken gelen bildirimi gosteren ust banner.
class InAppNotificationBanner extends StatelessWidget {
  const InAppNotificationBanner({
    super.key,
    required this.title,
    required this.body,
    required this.onDismiss,
    this.onOpen,
  });

  final String title;
  final String body;
  final VoidCallback onDismiss;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(16),
          elevation: 6,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined,
                      color: scheme.onInverseSurface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onInverseSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (body.isNotEmpty)
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onInverseSurface
                                  .withValues(alpha: 0.85),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: onDismiss,
                    icon: Icon(Icons.close, color: scheme.onInverseSurface),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
