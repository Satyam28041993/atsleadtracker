import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/lead_model.dart';
import '../../models/quotation_model.dart';
import '../../services/pdf_service.dart';
import '../../services/quotation_lookup.dart';
import '../../utils/quote_pdf_view.dart';

/// "Quotation view" icon for a lead row. Renders nothing until the lead is
/// known to have at least one quotation.
class LeadQuotationButton extends StatefulWidget {
  const LeadQuotationButton({
    super.key,
    required this.leadId,
    this.compact = false,
  });

  final String leadId;

  /// Smaller icon for dense rows (e.g. Kanban cards).
  final bool compact;

  @override
  State<LeadQuotationButton> createState() => _LeadQuotationButtonState();
}

class _LeadQuotationButtonState extends State<LeadQuotationButton> {
  late Future<List<QuotationModel>> _quotes;

  @override
  void initState() {
    super.initState();
    _quotes = QuotationLookup.instance.quotesFor(widget.leadId);
  }

  @override
  void didUpdateWidget(covariant LeadQuotationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leadId != widget.leadId) {
      _quotes = QuotationLookup.instance.quotesFor(widget.leadId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QuotationModel>>(
      future: _quotes,
      builder: (context, snap) {
        final quotes = snap.data ?? const <QuotationModel>[];
        if (quotes.isEmpty) return const SizedBox.shrink();
        return IconButton(
          tooltip: quotes.length == 1
              ? 'Quotation view'
              : 'Quotation view (${quotes.length})',
          visualDensity: widget.compact ? VisualDensity.compact : null,
          iconSize: widget.compact ? 20 : null,
          icon: const Icon(
            Icons.picture_as_pdf_outlined,
            color: Color(0xFFDC2626),
          ),
          onPressed: () => openLeadQuotations(context, quotes),
        );
      },
    );
  }
}

/// Opens the only quotation directly, or lets the user pick a revision.
Future<void> openLeadQuotations(
  BuildContext context,
  List<QuotationModel> quotes,
) async {
  if (quotes.isEmpty) return;
  if (quotes.length == 1) {
    await viewQuotationPdf(context, quotes.first);
    return;
  }
  final money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  final picked = await showDialog<QuotationModel>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Select quotation'),
      children: [
        for (final q in quotes)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(q),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.picture_as_pdf_outlined,
                color: Color(0xFFDC2626),
              ),
              title: Text(
                q.currentRefNo.isNotEmpty ? q.currentRefNo : q.baseRefNo,
              ),
              subtitle: Text(
                '${DateFormat('dd MMM yyyy').format(q.createdAt)}'
                ' · ${q.employeeName}',
              ),
              trailing: q.quoteRequest.totalAmount > 0
                  ? Text(money.format(q.quoteRequest.totalAmount))
                  : null,
            ),
          ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;
  await viewQuotationPdf(context, picked);
}

/// Regenerates the quotation PDF and shows it in the preview.
Future<void> viewQuotationPdf(
  BuildContext context,
  QuotationModel quote,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Opening quotation…'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    String? mobile;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(quote.employeeId)
          .get();
      mobile = userDoc.data()?['mobile']?.toString();
    } catch (_) {}

    final lead = Lead(
      id: quote.leadId,
      source: 'Unknown',
      createdAt: quote.createdAt,
      name: quote.quoteRequest.customerName,
      company: quote.quoteRequest.companyName,
      location: quote.quoteRequest.location,
      phone: quote.quoteRequest.phone,
      email: quote.quoteRequest.email,
      requirement: quote.quoteRequest.productName,
      status: 'Generated',
      assignedTo: quote.employeeId,
      remark: '',
      website: '',
    );

    final bytes = await PdfService().generateQuoteData(
      lead,
      quote.quoteRequest,
      creatorMobile: mobile,
      creatorName: quote.employeeName,
    );
    if (!context.mounted) return;
    await showQuotePdfPreview(context, bytes: bytes, title: quote.currentRefNo);
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Error viewing: $e'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
