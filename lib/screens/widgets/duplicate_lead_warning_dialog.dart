import 'package:flutter/material.dart';

import '../../services/duplicate_lead_service.dart';

/// Shown before a lead is saved when [DuplicateLeadService] found something
/// that looks like the same party already in the CRM.
///
/// Deliberately advisory: the primary action is still "Save anyway", because
/// legitimate repeat enquiries from the same company are normal and a hard
/// block would push people to enter junk data to get around it.
class DuplicateLeadWarningDialog extends StatelessWidget {
  const DuplicateLeadWarningDialog({super.key, required this.result});

  final DuplicateLeadResult result;

  /// Returns `true` when the user chose to save anyway.
  static Future<bool> show(
    BuildContext context, {
    required DuplicateLeadResult result,
  }) async {
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DuplicateLeadWarningDialog(result: result),
    );
    return proceed ?? false;
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
                itemBuilder: (context, index) =>
                    _MatchTile(match: matches[index]),
              ),
            ),
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
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Go back and edit'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save anyway'),
        ),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match});

  final DuplicateLeadMatch match;

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
                  : 'With ${match.ownerName}',
            ].join(' • '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}
