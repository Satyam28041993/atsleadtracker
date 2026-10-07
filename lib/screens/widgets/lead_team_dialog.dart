import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/lead_service.dart';

/// Result of [showLeadTeamDialog]: the team as it now stands, and whether the
/// current user left it (the caller should close the lead then — they can no
/// longer read it).
class LeadTeamResult {
  const LeadTeamResult(this.teamMembers, {this.left = false});
  final List<String> teamMembers;
  final bool left;
}

/// Shows who works on a lead and lets the owner / an admin add or remove
/// employees, or a member leave. Returns null when nothing changed.
Future<LeadTeamResult?> showLeadTeamDialog(
  BuildContext context, {
  required LeadService leadService,
  required AuthService authService,
  required String leadId,
  required String ownerUid,
  required List<String> teamMembers,
  required bool canManage,
}) {
  return showDialog<LeadTeamResult>(
    context: context,
    builder: (_) => _LeadTeamDialog(
      leadService: leadService,
      authService: authService,
      leadId: leadId,
      ownerUid: ownerUid,
      initialTeam: teamMembers,
      canManage: canManage,
    ),
  );
}

class _LeadTeamDialog extends StatefulWidget {
  const _LeadTeamDialog({
    required this.leadService,
    required this.authService,
    required this.leadId,
    required this.ownerUid,
    required this.initialTeam,
    required this.canManage,
  });

  final LeadService leadService;
  final AuthService authService;
  final String leadId;
  final String ownerUid;
  final List<String> initialTeam;
  final bool canManage;

  @override
  State<_LeadTeamDialog> createState() => _LeadTeamDialogState();
}

class _LeadTeamDialogState extends State<_LeadTeamDialog> {
  late List<String> _team = List<String>.from(widget.initialTeam);
  late final Stream<List<EmployeeAssignee>> _employees = widget.leadService
      .getAssignableEmployeesStream();
  Map<String, String> _labels = const {};
  String? _pickUid;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  String get _me => widget.authService.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  Future<void> _loadLabels() async {
    try {
      final labels = await widget.leadService.getUserDisplayLabels(
        {widget.ownerUid, ..._team}.where((u) => u.isNotEmpty),
      );
      if (mounted) setState(() => _labels = {..._labels, ...labels});
    } catch (_) {}
  }

  String _label(String uid) {
    if (uid.isEmpty) return 'Unassigned';
    final name = _labels[uid] ?? 'Employee';
    return uid == _me ? '$name (you)' : name;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _changed = true;
    } catch (e) {
      _error = 'Could not update the team: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(List<EmployeeAssignee> options) async {
    final member = options.where((o) => o.uid == _pickUid).firstOrNull;
    if (member == null) return;
    await _run(() async {
      await widget.leadService.addTeamMembers(widget.leadId, [member]);
      _labels = {..._labels, member.uid: member.label};
      _team = [..._team, member.uid];
      _pickUid = null;
    });
  }

  Future<void> _remove(String uid) async {
    final leaving = uid == _me;
    if (leaving) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave this lead?'),
          content: const Text(
            'It will disappear from your lists. The owner can add you again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _run(() async {
      await widget.leadService.removeTeamMember(
        widget.leadId,
        memberUid: uid,
        memberLabel: _labels[uid] ?? 'Employee',
      );
      _team = _team.where((u) => u != uid).toList();
    });
    if (leaving && _error == null && mounted) {
      Navigator.of(context).pop(LeadTeamResult(_team, left: true));
    }
  }

  void _close() {
    Navigator.of(context).pop(_changed ? LeadTeamResult(_team) : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _close();
      },
      child: AlertDialog(
        title: const Text('Team on this lead'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Everyone here sees this lead in their Kanban, Follow-ups '
                  "and Today's Work, and can add notes, change status and "
                  'make quotations. Changes show up for all of them live.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.star_rounded, size: 20),
                  ),
                  title: Text(_label(widget.ownerUid)),
                  subtitle: const Text('Owner'),
                ),
                for (final uid in _team)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_rounded, size: 20),
                    ),
                    title: Text(_label(uid)),
                    subtitle: const Text('Team member'),
                    trailing: uid == _me
                        ? TextButton(
                            onPressed: _busy ? null : () => _remove(uid),
                            child: const Text('Leave'),
                          )
                        : (widget.canManage
                              ? IconButton(
                                  tooltip: 'Remove from team',
                                  onPressed: _busy ? null : () => _remove(uid),
                                  icon: const Icon(Icons.close_rounded),
                                )
                              : null),
                  ),
                if (_team.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No one else is on this lead yet.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (widget.canManage) ...[
                  const Divider(height: 24),
                  StreamBuilder<List<EmployeeAssignee>>(
                    stream: _employees,
                    builder: (context, snap) {
                      final options = (snap.data ?? const <EmployeeAssignee>[])
                          .where(
                            (e) =>
                                e.uid != widget.ownerUid &&
                                !_team.contains(e.uid),
                          )
                          .toList();
                      if (snap.hasData && options.isEmpty) {
                        return Text(
                          'Every employee is already on this lead.',
                          style: theme.textTheme.bodySmall,
                        );
                      }
                      final valid = options.any((o) => o.uid == _pickUid);
                      return Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_team.length),
                              initialValue: valid ? _pickUid : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Add employee',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                for (final o in options)
                                  DropdownMenuItem(
                                    value: o.uid,
                                    child: Text(o.label),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() => _pickUid = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _busy || !valid
                                ? null
                                : () => _add(options),
                            child: const Text('Add'),
                          ),
                        ],
                      );
                    },
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          TextButton(
            onPressed: _busy ? null : _close,
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
