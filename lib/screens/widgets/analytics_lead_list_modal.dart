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
  });

  final String title;
  final List<String> leadIds;
  final AuthService authService;
  final LeadService leadService;
  final ProductService? productService;

  static void show(
    BuildContext context, {
    required String title,
    required List<String> leadIds,
    required AuthService authService,
    required LeadService leadService,
    ProductService? productService,
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

    leads.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return leads;
  }

  bool _matches(Lead lead) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return lead.name.toLowerCase().contains(q) ||
        lead.company.toLowerCase().contains(q) ||
        lead.phone.toLowerCase().contains(q) ||
        lead.status.toLowerCase().contains(q) ||
        lead.source.toLowerCase().contains(q) ||
        lead.bidNo.toLowerCase().contains(q);
  }

  String _fmtMoney(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)} K';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1D2638),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Search name, company, phone, status…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF7F8FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<Lead>>(
                  future: _leadsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Could not load leads.\n${snapshot.error}'),
                      );
                    }
                    final all = snapshot.data ?? const <Lead>[];
                    final filtered = all.where(_matches).toList(growable: false);
                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          all.isEmpty
                              ? 'No leads found.'
                              : 'No leads match your search.',
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
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final lead = filtered[index];
                        final title = lead.company.trim().isNotEmpty
                            ? lead.company
                            : (lead.name.trim().isNotEmpty
                                ? lead.name
                                : lead.id);
                        return ListTile(
                          title: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${lead.status} • ${lead.source.isEmpty ? 'No source' : lead.source}'
                            '${lead.name.trim().isNotEmpty && lead.company.trim().isNotEmpty ? ' • ${lead.name}' : ''}',
                          ),
                          trailing: Text(
                            _fmtMoney(lead.totalAmount),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF245DAF),
                            ),
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
