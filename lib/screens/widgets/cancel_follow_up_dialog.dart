import 'package:flutter/material.dart';

/// Asks why a follow-up is being cancelled.
///
/// Returns the reason (possibly empty if the user skipped it), or null when
/// the dialog is dismissed — callers must treat null as "do nothing".
Future<String?> showCancelFollowUpDialog(
  BuildContext context, {
  required String leadName,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _CancelFollowUpDialog(leadName: leadName),
  );
}

class _CancelFollowUpDialog extends StatefulWidget {
  const _CancelFollowUpDialog({required this.leadName});

  final String leadName;

  @override
  State<_CancelFollowUpDialog> createState() => _CancelFollowUpDialogState();
}

class _CancelFollowUpDialogState extends State<_CancelFollowUpDialog> {
  static const List<String> _quickReasons = <String>[
    'Client declined',
    'No longer interested',
    'Budget not available',
    'Bought from someone else',
    'Wrong / unreachable contact',
  ];

  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pick(String reason) {
    setState(() {
      _controller.text = reason;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.leadName.trim();

    return AlertDialog(
      title: const Text('Cancel follow-up'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty
                  ? 'This lead will stop appearing in the follow-up list. You '
                        'can schedule a new follow-up at any time.'
                  : '$name will stop appearing in the follow-up list. You can '
                        'schedule a new follow-up at any time.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reason in _quickReasons)
                  ActionChip(
                    label: Text(reason),
                    onPressed: () => _pick(reason),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Why are we stopping follow-ups?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep follow-up'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Cancel follow-up'),
        ),
      ],
    );
  }
}
