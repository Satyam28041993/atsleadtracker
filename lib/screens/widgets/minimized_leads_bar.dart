import 'package:flutter/material.dart';

import '../../services/lead_draft_store.dart';

const Color _kChipBg = Color(0xFF1D2638);
const Color _kChipBorder = Color(0xFF2F3B52);

/// Bottom-left strip of chips for leads that were minimised mid-edit.
///
/// Mounted straight into the root [Overlay] by [ensureMounted] so it survives
/// route changes and works from all dashboard shells without any of them
/// having to host it.
class MinimizedLeadsBar extends StatelessWidget {
  const MinimizedLeadsBar({super.key});

  static OverlayEntry? _entry;

  /// Inserts the bar once per app run. Safe to call on every panel open.
  static void ensureMounted(BuildContext context) {
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (_) => const MinimizedLeadsBar(),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MinimizedLead>>(
      valueListenable: LeadDraftStore.instance.drafts,
      builder: (context, drafts, _) {
        if (drafts.isEmpty) return const SizedBox.shrink();

        return Positioned(
          left: 16,
          bottom: 16,
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in drafts)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _DraftChip(entry: entry),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DraftChip extends StatelessWidget {
  const _DraftChip({required this.entry});

  final MinimizedLead entry;

  @override
  Widget build(BuildContext context) {
    final draft = entry.draft;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => entry.restore(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(
            color: _kChipBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kChipBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.edit_note_rounded,
                size: 20,
                color: Color(0xFF9DB2D8),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${draft.subtitle} · unsaved',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9DB2D8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Discard draft',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                color: const Color(0xFF9DB2D8),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => _confirmDiscard(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDiscard(BuildContext context) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard draft?'),
        content: Text(
          'Unsaved changes to ${entry.draft.label} will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true) {
      LeadDraftStore.instance.remove(entry.draft.leadId);
    }
  }
}
