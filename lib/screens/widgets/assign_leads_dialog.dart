import 'package:flutter/material.dart';

import '../../models/lead_model.dart';
import '../../services/auth_service.dart';
import '../../services/lead_service.dart';

/// Admin dialog to assign one or many leads / tenders to an employee (or to
/// the admin themself). Writes through [LeadService.assignLeads] and shows a
/// snackbar with the result.
///
/// Returns the chosen assignee once the leads are saved, or `null` when
/// cancelled or failed.
Future<EmployeeAssignee?> showAssignLeadsDialog(
  BuildContext context, {
  required LeadService leadService,
  required AuthService authService,
  required List<Lead> leads,
  Map<String, String> labels = const {},
}) async {
  if (leads.isEmpty) return null;
  final messenger = ScaffoldMessenger.of(context);
  final result = await showDialog<_AssignResult>(
    context: context,
    builder: (context) => _AssignLeadsDialog(
      leadService: leadService,
      authService: authService,
      leads: leads,
      labels: labels,
    ),
  );
  if (result == null) return null;
  final noun = leads.first.isTender && leads.every((l) => l.isTender)
      ? 'tender'
      : 'lead';
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(
        result.moved == 0
            ? 'Already assigned to ${result.assignee.label}.'
            : 'Assigned ${result.moved} $noun${result.moved == 1 ? '' : 's'}'
                  ' to ${result.assignee.label}.',
      ),
    ),
  );
  return result.assignee;
}

class _AssignResult {
  const _AssignResult(this.assignee, this.moved);
  final EmployeeAssignee assignee;
  final int moved;
}

class _AssignLeadsDialog extends StatefulWidget {
  const _AssignLeadsDialog({
    required this.leadService,
    required this.authService,
    required this.leads,
    required this.labels,
  });

  final LeadService leadService;
  final AuthService authService;
  final List<Lead> leads;
  final Map<String, String> labels;

  @override
  State<_AssignLeadsDialog> createState() => _AssignLeadsDialogState();
}

class _AssignLeadsDialogState extends State<_AssignLeadsDialog> {
  late final Stream<List<EmployeeAssignee>> _employees = widget.leadService
      .getAssignableEmployeesStream();
  late final Future<String> _selfName = widget.authService
      .getCurrentUserDisplayName();

  String? _selectedUid;
  bool _saving = false;
  String? _error;

  String get _selfUid => widget.authService.currentUser?.uid ?? '';

  Future<void> _assign(List<EmployeeAssignee> options) async {
    final assignee = options.where((o) => o.uid == _selectedUid).firstOrNull;
    if (assignee == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final moved = await widget.leadService.assignLeads(
        widget.leads,
        assignee,
        labels: widget.labels,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_AssignResult(assignee, moved));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not assign: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.leads.length;
    final single = count == 1 ? widget.leads.first : null;
    final currentUid = single?.assignedTo.trim() ?? '';
    final currentLabel = currentUid.isEmpty
        ? 'Unassigned'
        : (widget.labels[currentUid] ?? '');

    return FutureBuilder<String>(
      future: _selfName,
      builder: (context, selfSnap) {
        return StreamBuilder<List<EmployeeAssignee>>(
          stream: _employees,
          builder: (context, snap) {
            final selfName = selfSnap.data?.trim() ?? '';
            final options = <EmployeeAssignee>[
              if (_selfUid.isNotEmpty)
                EmployeeAssignee(
                  uid: _selfUid,
                  label: selfName.isEmpty ? 'Me' : 'Me ($selfName)',
                ),
              ...?snap.data?.where((e) => e.uid != _selfUid),
            ];
            final loading =
                !snap.hasData &&
                snap.connectionState == ConnectionState.waiting;
            final selectedValid = options.any((o) => o.uid == _selectedUid);

            return AlertDialog(
              title: Text(
                single == null
                    ? 'Assign $count selected'
                    : (currentUid.isEmpty ? 'Assign' : 'Reassign'),
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (single != null) ...[
                      Text(
                        single.company.trim().isNotEmpty
                            ? single.company
                            : single.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (currentLabel.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Currently with: $currentLabel',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: selectedValid ? _selectedUid : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Assign to',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final o in options)
                            DropdownMenuItem(
                              value: o.uid,
                              child: Text(o.label),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _selectedUid = v),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Status, remarks, quotations and timeline stay with the '
                      'lead. The new owner sees its full history.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _saving || !selectedValid
                      ? null
                      : () => _assign(options),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(single == null ? 'Assign $count' : 'Assign'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
