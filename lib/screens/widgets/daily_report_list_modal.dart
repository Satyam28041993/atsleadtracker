import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/lead_model.dart';
import '../../models/quotation_model.dart';
import '../../services/auth_service.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import 'lead_details_modal.dart';
import 'lead_quotation_button.dart';

class DailyReportListModal extends StatelessWidget {
  const DailyReportListModal({
    super.key,
    required this.title,
    required this.itemIds,
    required this.isQuotation,
    required this.authService,
    required this.leadService,
    this.productService,
  });

  final String title;
  final List<String> itemIds;
  final bool isQuotation;
  final AuthService authService;
  final LeadService leadService;
  final ProductService? productService;

  /// firestore.rules only allows a leads/quotations read when isAdmin() or
  /// assignedTo/employeeId == uid, and a LIST query has to prove that from
  /// the query itself. A `whereIn` on the document id does not satisfy that
  /// check — not even with the ownership equality added alongside it — so an
  /// employee reads their own slice with the plain equality query that is
  /// known to work, and picks the requested ids out of it locally.
  Future<bool> _isAdmin() async {
    final uid = authService.currentUser?.uid;
    if (uid == null || uid.isEmpty) return false;
    try {
      return await authService.getUserRole(uid) == 'admin';
    } catch (_) {
      return false;
    }
  }

  /// Documents for [itemIds] out of [collection], read in whichever shape the
  /// signed-in user is actually allowed to use.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchByIds({
    required String collection,
    required String ownerField,
  }) async {
    final ids = itemIds.take(30).toSet();
    if (ids.isEmpty) return const [];
    final isAdmin = await _isAdmin();
    final uid = authService.currentUser?.uid;
    final col = FirebaseFirestore.instance.collection(collection);

    if (!isAdmin && uid != null && uid.isNotEmpty) {
      final snap = await col.where(ownerField, isEqualTo: uid).get();
      return snap.docs.where((d) => ids.contains(d.id)).toList();
    }
    final snap =
        await col.where(FieldPath.documentId, whereIn: ids.toList()).get();
    return snap.docs;
  }

  static void show(
    BuildContext context, {
    required String title,
    required List<String> itemIds,
    required bool isQuotation,
    required AuthService authService,
    required LeadService leadService,
    ProductService? productService,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DailyReportListModal(
        title: title,
        itemIds: itemIds,
        isQuotation: isQuotation,
        authService: authService,
        leadService: leadService,
        productService: productService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
              const Divider(height: 1),
              Expanded(
                child: isQuotation
                    ? _buildQuotationList(context, controller)
                    : _buildLeadList(context, controller),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeadList(BuildContext context, ScrollController controller) {
    if (itemIds.isEmpty) {
      return const Center(child: Text('No leads found.'));
    }
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _fetchByIds(collection: 'leads', ownerField: 'assignedTo'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final leads = snapshot.data?.map(Lead.fromFirestore).toList() ?? [];
        if (leads.isEmpty) {
          return const Center(child: Text('No leads found.'));
        }
        return ListView.builder(
          controller: controller,
          itemCount: leads.length,
          itemBuilder: (context, index) {
            final lead = leads[index];
            return ListTile(
              title: Text(lead.company.isNotEmpty ? lead.company : lead.name),
              subtitle: Text('${lead.status} • ${lead.requirement}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LeadQuotationButton(leadId: lead.id),
                  IconButton(
                    tooltip: 'Lead View',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () {
                      Navigator.of(context).pop();
                      LeadDetailsModal.show(
                        context,
                        lead: lead,
                        authService: authService,
                        leadService: leadService,
                        productService: productService,
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuotationList(BuildContext context, ScrollController controller) {
    if (itemIds.isEmpty) {
      return const Center(child: Text('No quotations found.'));
    }
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _fetchByIds(collection: 'quotations', ownerField: 'employeeId'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final quotes =
            snapshot.data?.map(QuotationModel.fromFirestore).toList() ?? [];
        if (quotes.isEmpty) {
          return const Center(child: Text('No quotations found.'));
        }
        return ListView.builder(
          controller: controller,
          itemCount: quotes.length,
          itemBuilder: (context, index) {
            final quote = quotes[index];
            return ListTile(
              title: Text(quote.currentRefNo),
              subtitle: Text(quote.quoteRequest.companyName),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Quote View',
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    onPressed: () => viewQuotationPdf(context, quote),
                  ),
                  IconButton(
                    tooltip: 'Lead View',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => _openLeadForQuote(context, quote),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openLeadForQuote(
    BuildContext context,
    QuotationModel quote,
  ) async {
    Navigator.of(context).pop();
    final leadDoc = await FirebaseFirestore.instance
        .collection('leads')
        .doc(quote.leadId)
        .get();
    if (!leadDoc.exists || !context.mounted) return;
    LeadDetailsModal.show(
      context,
      lead: Lead.fromFirestore(leadDoc),
      authService: authService,
      leadService: leadService,
      productService: productService,
    );
  }
}
