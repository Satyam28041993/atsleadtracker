import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/lead_model.dart';
import '../../services/auth_service.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import 'lead_details_modal.dart';

/// Searchable bottom sheet listing leads for an analytics drill-down.
class AnalyticsLeadListModal extends StatefulWidget {
  const AnalyticsLeadListModal({
    super.key,
    required this.title,
    required this.leadIds,
    required this.authService,
    required this.leadService,
    this.productService,
    this.quotedLeadIds = const {},
    this.leadAmounts = const {},
  });

  final String title;
  final List<String> leadIds;
  final AuthService authService;
  final LeadService leadService;
  final ProductService? productService;

  /// Lead ids that already have a quotation (shows "Proposal sent").
  final Set<String> quotedLeadIds;

  /// Lead id → effective deal amount (quotation fallback included).
  final Map<String, double> leadAmounts;

  static void show(
    BuildContext context, {
    required String title,
    required List<String> leadIds,
    required AuthService authService,
    required LeadService leadService,
    ProductService? productService,
    Set<String>? quotedLeadIds,
    Map<String, double>? leadAmounts,
  }) {
    if (leadIds.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AnalyticsLeadListModal(
        title: title,
        leadIds: leadIds,
        authService: authService,
        leadService: leadService,
        productService: productService,
        quotedLeadIds: quotedLeadIds ?? const {},
        leadAmounts: leadAmounts ?? const {},
      ),
    );
  }

  @override
  State<AnalyticsLeadListModal> createState() => _AnalyticsLeadListModalState();
}

class _AnalyticsLeadListModalState extends State<AnalyticsLeadListModal> {
  final TextEditingController _searchController = TextEditingController();
  late final Future<List<Lead>> _leadsFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _leadsFuture = _loadLeads(widget.leadIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Lead>> _loadLeads(List<String> ids) async {
    final uniqueIds = ids.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) return const <Lead>[];

    final leads = <Lead>[];
    const chunkSize = 30;
    for (var i = 0; i < uniqueIds.length; i += chunkSize) {
      final end = (i + chunkSize < uniqueIds.length)
          ? i + chunkSize
          : uniqueIds.length;
      final chunk = uniqueIds.sublist(i, end);
      final snap = await FirebaseFirestore.instance
          .collection('leads')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      leads.addAll(snap.docs.map(Lead.fromFirestore));
    }

    // Prefer analytics amount order (biggest first); else lastModified.
    if (widget.leadAmounts.isNotEmpty) {
      leads.sort((a, b) {
        final amtCmp = (widget.leadAmounts[b.id] ?? 0)
            .compareTo(widget.leadAmounts[a.id] ?? 0);
        if (amtCmp != 0) return amtCmp;
        return b.lastModified.compareTo(a.lastModified);
      });
    } else {
      // Preserve requested id order when amounts are not supplied.
      final order = <String, int>{
        for (var i = 0; i < ids.length; i++) ids[i]: i,
      };
      leads.sort((a, b) {
        final ai = order[a.id] ?? 1 << 30;
        final bi = order[b.id] ?? 1 << 30;
        if (ai != bi) return ai.compareTo(bi);
        return b.lastModified.compareTo(a.lastModified);
      });
    }
    return leads;
  }

  bool _matches(Lead lead) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final quoted = widget.quotedLeadIds.contains(lead.id) ||
        (widget.leadAmounts[lead.id] ?? lead.totalAmount) > 0;
    return lead.name.toLowerCase().contains(q) ||
        lead.company.toLowerCase().contains(q) ||
        lead.phone.toLowerCase().contains(q) ||
        lead.status.toLowerCase().contains(q) ||
        lead.source.toLowerCase().contains(q) ||
        lead.bidNo.toLowerCase().contains(q) ||
        (quoted && 'proposal sent'.contains(q));
  }

  String _fmtMoney(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)} K';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(v);
  }

  Color _stageColor(String status) {
    switch (status) {
      case 'Follow-up':
        return const Color(0xFF8B5CF6);
      case 'Proposal':
        return const Color(0xFF6366F1);
      case 'Contacted':
        return const Color(0xFFF59E0B);
      case 'Technical Evaluation':
      case 'Qualified':
      case 'Reverse Auction(RA)':
        return const Color(0xFF0EA5E9);
      case 'Query Raised':
      case 'Query Responded':
        return const Color(0xFF0CA678);
      case 'Won':
        return const Color(0xFF10B981);
      case 'Lost':
      case 'Loss':
      case 'Disqualified':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) {
        return Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search name, company, phone, status...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Lead>>(
                  future: _leadsFuture,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load leads.\n${snap.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    final all = snap.data ?? const <Lead>[];
                    final filtered = all.where(_matches).toList();
                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          all.isEmpty ? 'No leads found.' : 'No matches.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Text(
                            'Showing ${filtered.length} of ${all.length} loaded'
                            ' (requested ${widget.leadIds.length})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            controller: controller,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final lead = filtered[index];
                              final title = lead.company.trim().isNotEmpty
                                  ? lead.company
                                  : (lead.name.trim().isNotEmpty
                                      ? lead.name
                                      : lead.id);
                              final sub = lead.company.trim().isNotEmpty &&
                                      lead.name.trim().isNotEmpty
                                  ? lead.name
                                  : lead.phone;
                              final amount = widget.leadAmounts[lead.id] ??
                                  lead.totalAmount;
                              final proposalSent =
                                  widget.quotedLeadIds.contains(lead.id) ||
                                      amount > 0;
                              // Pactech: 'Proposal' already says a quote went
                              // out; spell it out on Follow-up (and early
                              // stages / tenders where status alone is unclear).
                              final showProposalSent = proposalSent &&
                                  (lead.status == 'Follow-up' ||
                                      lead.status == 'Contacted' ||
                                      lead.status == 'New' ||
                                      lead.isTender);
                              final stageColor = _stageColor(lead.status);

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                isThreeLine: sub.trim().isNotEmpty,
                                title: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (sub.trim().isNotEmpty)
                                      Text(
                                        sub,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        _StageChip(
                                          label: lead.status.trim().isEmpty
                                              ? 'No stage'
                                              : lead.status,
                                          color: stageColor,
                                        ),
                                        if (lead.isTender)
                                          const _StageChip(
                                            label: 'Tender',
                                            color: Color(0xFF1864AB),
                                          ),
                                        if (showProposalSent)
                                          const _StageChip(
                                            label: 'Proposal sent',
                                            color: Color(0xFF0CA678),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (amount > 0)
                                      Text(
                                        _fmtMoney(amount),
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF245DAF),
                                        ),
                                      )
                                    else
                                      const Text(
                                        'No value',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFB45309),
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  LeadDetailsModal.show(
                                    context,
                                    lead: lead,
                                    authService: widget.authService,
                                    leadService: widget.leadService,
                                    productService: widget.productService,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
