import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/quotation_model.dart';
import '../../services/quotation_service.dart';

/// Short form of a quotation ref: `ATEPL/0609-R1/2026-2027` -> `0609-R1`.
String shortQuoteNumber(String refNo) {
  final parts = refNo.split('/');
  if (parts.length >= 2) return parts[1];
  return refNo;
}

/// Lets the user choose which quotation drives a lead's deal amount.
///
/// Returns the chosen quotation, or null when dismissed.
Future<QuotationModel?> showQuotationPicker(
  BuildContext context, {
  required List<QuotationModel> quotations,
  required String? selectedId,
  required QuotationLoadStatus status,
}) {
  return showDialog<QuotationModel>(
    context: context,
    builder: (ctx) => _QuotationPickerDialog(
      quotations: quotations,
      selectedId: selectedId,
      status: status,
    ),
  );
}

class _QuotationPickerDialog extends StatefulWidget {
  const _QuotationPickerDialog({
    required this.quotations,
    required this.selectedId,
    required this.status,
  });

  final List<QuotationModel> quotations;
  final String? selectedId;
  final QuotationLoadStatus status;

  @override
  State<_QuotationPickerDialog> createState() => _QuotationPickerDialogState();
}

class _QuotationPickerDialogState extends State<_QuotationPickerDialog> {
  static final NumberFormat _money = NumberFormat('#,##,##0', 'en_IN');
  static final DateFormat _stamp = DateFormat('dd MMM yyyy, hh:mm a');

  late String? _selected =
      widget.selectedId ??
      (widget.quotations.isNotEmpty ? widget.quotations.first.id : null);

  String _emptyMessage() {
    switch (widget.status) {
      case QuotationLoadStatus.denied:
        return 'These quotations were created by another user, so they can '
            'not be shown here.';
      case QuotationLoadStatus.failed:
        return 'Could not load quotations. Check your connection and try '
            'again.';
      case QuotationLoadStatus.ok:
        return 'No quotations have been created for this lead yet.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quotes = widget.quotations;

    return AlertDialog(
      title: const Text('Choose quotation'),
      content: SizedBox(
        width: 460,
        child: quotes.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _emptyMessage(),
                  style: theme.textTheme.bodyMedium,
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: quotes.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final q = quotes[index];
                    // Quotes are pre-sorted newest-first, so index 0 is the
                    // one the lead follows by default.
                    final isLatest = index == 0;
                    final products = q.quoteRequest.products
                        .map((p) => p.productName.trim())
                        .where((n) => n.isNotEmpty)
                        .join(', ');

                    return RadioListTile<String>(
                      value: q.id,
                      groupValue: _selected,
                      onChanged: (v) => setState(() => _selected = v),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              q.currentRefNo.isNotEmpty
                                  ? q.currentRefNo
                                  : q.quoteRequest.refNo,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _Chip(
                            label: 'Rev ${q.revision}',
                            color: theme.colorScheme.primary,
                          ),
                          if (isLatest) ...[
                            const SizedBox(width: 4),
                            const _Chip(
                              label: 'Latest',
                              color: Color(0xFF10B981),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        products.isEmpty
                            ? _stamp.format(q.createdAt)
                            : '${_stamp.format(q.createdAt)} · $products',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      secondary: Text(
                        '₹${_money.format(q.quoteRequest.totalAmount)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (quotes.isNotEmpty)
          FilledButton(
            onPressed: _selected == null
                ? null
                : () => Navigator.of(context).pop(
                    quotes.firstWhere((q) => q.id == _selected),
                  ),
            child: const Text('Use this amount'),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
