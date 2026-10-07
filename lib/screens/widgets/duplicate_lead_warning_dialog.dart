import 'package:flutter/material.dart';

import '../../services/duplicate_lead_service.dart';
import '../../services/lead_service.dart';

/// What the user chose in [DuplicateLeadWarningDialog].
enum DuplicateDecision {
  /// Go back to the form.
  edit,

  /// Create the new lead anyway.
  saveAnyway,

  /// Joined the existing lead's team instead; nothing new should be saved.
  joined,
}

/// Shown before a lead is saved when [DuplicateLeadService] found something
/// that looks like the same party already in the CRM.
///
/// Deliberately advisory: the primary action is still "Save anyway", because
/// legitimate repeat enquiries from the same company are normal and a hard
/// block would push people to enter junk data to get around it.
class DuplicateLeadWarningDialog extends StatefulWidget {
  const DuplicateLeadWarningDialog({
    super.key,
    required this.result,
    this.leadService,
  });

  final DuplicateLeadResult result;

  /// Enables "Join" on other people's leads. Null hides it.
  final LeadService? leadService;

  static Future<DuplicateDecision> show(
    BuildContext context, {
    required DuplicateLeadResult result,
    LeadService? leadService,
  }) async {
    final decision = await showDialog<DuplicateDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          DuplicateLeadWarningDialog(result: result, leadService: leadService),
    );
    return decision ?? DuplicateDecision.edit;
  }

  @override
  State<DuplicateLeadWarningDialog> createState() =>
      _DuplicateLeadWarningDialogState();
}

class _DuplicateLeadWarningDialogState
    extends State<DuplicateLeadWarningDialog> {
  String? _joiningId;
  String? _error;

  DuplicateLeadResult get result => widget.result;

  /// Join only works through the server check's results: the fallback scan
  /// cannot tell whose lead it is.
  bool _canJoin(DuplicateLeadMatch m) =>
      widget.leadService != null &&
      result.checkedEveryone &&
      !m.isMine &&
      !m.isOnTeam &&
      m.leadId.isNotEmpty;

  Future<void> _join(DuplicateLeadMatch match) async {
    setState(() {
      _joiningId = match.leadId;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await widget.leadService!.joinLeadTeam(match.leadId);
      if (!mounted) return;
      Navigator.of(context).pop(DuplicateDecision.joined);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            status == 'joined'
                ? 'You joined ${match.displayTitle} with ${match.ownerName}. '
                    'It is now in your list.'
                : 'You are already working on ${match.displayTitle}. '
                    'It is in your list.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joiningId = null;
        _error = 'Could not join: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = result.matches;
    final mineCount = matches.where((m) => m.isMine).length;
    final othersCount = matches.length - mineCount;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(
        Icons.copy_all_rounded,
        color: Color(0xFFE8590C),
        size: 32,
      ),
      title: Text(
        matches.length == 1
            ? 'This lead may already exist'
            : 'Found ${matches.length} similar leads',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF1D2638),
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              othersCount > 0
                  ? 'Someone in the team is already working on this. Check with them before adding it again.'
                  : 'You already have this party in your own list.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF4B5563),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: matches.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final m = matches[index];
                  return _MatchTile(
                    match: m,
                    joining: _joiningId == m.leadId,
                    onJoin: _canJoin(m) && _joiningId == null
                        ? () => _join(m)
                        : null,
                  );
                },
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (!result.checkedEveryone) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Only the leads you can see were checked. There may be '
                      'more under other team members.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _joiningId != null
              ? null
              : () => Navigator.of(context).pop(DuplicateDecision.edit),
          child: const Text('Go back and edit'),
        ),
        FilledButton(
          onPressed: _joiningId != null
              ? null
              : () => Navigator.of(context).pop(DuplicateDecision.saveAnyway),
          child: const Text('Save anyway'),
        ),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, this.onJoin, this.joining = false});

  final DuplicateLeadMatch match;

  /// Non-null when the user can join this lead's team.
  final VoidCallback? onJoin;
  final bool joining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE0C2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  match.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1D2638),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBD9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  match.matchedOnLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFC2410C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (match.name.trim().isNotEmpty &&
                  match.company.trim().isNotEmpty)
                match.name.trim(),
              if (match.status.isNotEmpty) match.status,
              match.isMine
                  ? 'Already yours'
                  : (match.isOnTeam
                        ? 'With ${match.ownerName} — you are on the team'
                        : 'With ${match.ownerName}'),
            ].join(' • '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
            ),
          ),
          if (onJoin != null || joining) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onJoin,
                icon: joining
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add_rounded, size: 18),
                label: Text('Join ${match.ownerName} on this lead'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
