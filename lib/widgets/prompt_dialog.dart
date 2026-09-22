import 'package:flutter/material.dart';

/// Tek alanli metin soran ortak diyalog. Iptal edilirse `null` doner.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String? hint,
  String initialValue = '',
  bool capitalize = false,
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initialValue);
  final formKey = GlobalKey<FormState>();

  void submit(BuildContext dialogContext) {
    if (formKey.currentState!.validate()) {
      Navigator.of(dialogContext).pop(controller.text);
    }
  }

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          textCapitalization: capitalize
              ? TextCapitalization.characters
              : TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'Bos birakilamaz'
              : null,
          onFieldSubmitted:
              maxLines == 1 ? (_) => submit(dialogContext) : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Vazgec'),
        ),
        FilledButton(
          onPressed: () => submit(dialogContext),
          child: Text(confirmLabel),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Yikici islemler icin onay diyalogu. Onaylanirsa `true` doner.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Vazgec'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
