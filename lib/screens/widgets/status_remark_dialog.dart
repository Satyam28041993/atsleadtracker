import 'package:flutter/material.dart';

import '../../models/lead_model.dart';

/// Asks for the remark a status needs before a lead/tender can move into it.
///
/// Returns the trimmed text, or `null` when cancelled or left empty (a
/// snackbar explains why nothing changed).
Future<String?> showStatusRemarkDialog(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
  required String requiredMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) =>
        _StatusRemarkDialog(title: title, hint: hint, initial: initial),
  );
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(requiredMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return null;
  }
  return trimmed;
}

Future<String?> promptLossReason(BuildContext context, {String initial = ''}) {
  return showStatusRemarkDialog(
    context,
    title: 'Reason for Loss',
    hint: 'Please specify the reason...',
    initial: initial,
    requiredMessage:
        'A reason is required before marking this lead as Lost/Loss.',
  );
}

Future<String?> promptCommercialStatus(
  BuildContext context, {
  String initial = '',
}) {
  return showStatusRemarkDialog(
    context,
    title: Lead.commercialStatusStage,
    hint: 'What is the commercial status? e.g. L1, price bid opened...',
    initial: initial,
    requiredMessage:
        'A remark is required before moving to '
        '${Lead.commercialStatusStage}.',
  );
}

/// For quick status changes outside the lead sheet (Kanban drag, Today's
/// Work): collects the remark [target] needs and returns [lead] carrying it,
/// ready to pass as `sourceLead` to `LeadService.updateLeadStatus`.
/// Returns `null` when the user cancels.
Future<Lead?> leadWithStatusRemark(
  BuildContext context,
  Lead lead,
  String target,
) async {
  if (target == 'Loss' || target == 'Lost') {
    final reason = await promptLossReason(context, initial: lead.lossReason);
    return reason == null ? null : lead.copyWith(lossReason: reason);
  }
  if (target == Lead.commercialStatusStage) {
    final remark = await promptCommercialStatus(
      context,
      initial: lead.commercialStatus,
    );
    return remark == null ? null : lead.copyWith(commercialStatus: remark);
  }
  return lead;
}

/// Owns its controller so it is disposed only after the close animation.
class _StatusRemarkDialog extends StatefulWidget {
  const _StatusRemarkDialog({
    required this.title,
    required this.hint,
    required this.initial,
  });

  final String title;
  final String hint;
  final String initial;

  @override
  State<_StatusRemarkDialog> createState() => _StatusRemarkDialogState();
}

class _StatusRemarkDialogState extends State<_StatusRemarkDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: widget.hint,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
