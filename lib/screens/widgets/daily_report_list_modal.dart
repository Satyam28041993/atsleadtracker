import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/lead_model.dart';
import '../../models/quotation_model.dart';
import '../../services/auth_service.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import 'lead_details_modal.dart';

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
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('leads')
          .where(FieldPath.documentId, whereIn: itemIds.take(30).toList())
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final leads = snapshot.data?.docs.map(Lead.fromFirestore).toList() ?? [];
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
              trailing: IconButton(
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
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('quotations')
          .where(FieldPath.documentId, whereIn: itemIds.take(30).toList())
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final quotes = snapshot.data?.docs.map(QuotationModel.fromFirestore).toList() ?? [];
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
              trailing: IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: () async {
                  Navigator.of(context).pop();
                  // For quotation, we need the actual Lead object to open LeadDetailsModal
                  final leadDoc = await FirebaseFirestore.instance.collection('leads').doc(quote.leadId).get();
                  if (leadDoc.exists && context.mounted) {
                    final lead = Lead.fromFirestore(leadDoc);
                    LeadDetailsModal.show(
                      context,
                      lead: lead,
                      authService: authService,
                      leadService: leadService,
                      productService: productService,
                    );
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}
