import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../models/quotation_model.dart';
import '../models/lead_model.dart';
import '../services/quotation_service.dart';
import '../services/lead_service.dart';
import '../services/product_service.dart';
import '../services/pdf_service.dart';
import '../utils/quote_pdf_view.dart';
import 'widgets/quote_builder_dialog.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:printing/printing.dart';

class QuotationManagementScreen extends StatefulWidget {
  const QuotationManagementScreen({
    super.key,
    required this.isAdmin,
    required this.productService,
    required this.leadService,
  });

  final bool isAdmin;
  final ProductService productService;
  final LeadService leadService;

  @override
  State<QuotationManagementScreen> createState() => _QuotationManagementScreenState();
}

class _QuotationManagementScreenState extends State<QuotationManagementScreen> {
  final QuotationService _quotationService = QuotationService();
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  String _searchQuery = '';
  DateTime? _filterDate;

  Future<String?> _getEmployeeMobile(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['mobile']?.toString();
      }
    } catch (_) {}
    return null;
  }

  /// Extracts the short quotation number from a ref like `ATEPL/1069/2026-2027`
  /// -> `1069` (keeps revision suffixes like `1069-R1`).
  String _shortQuoteNumber(String ref) {
    final trimmed = ref.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split('/');
    final candidate = parts.length >= 2 ? parts[1].trim() : trimmed;
    return candidate.replaceAll(RegExp(r'[^\w\-]+'), '_');
  }

  Future<void> _downloadQuotation(QuotationModel q) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        const SnackBar(content: Text('Generating PDF...')),
      );
      
      // If lead is deleted or not found, we create a dummy one just for the PDF generator 
      // since the PDF generator mainly uses the QuoteRequest data anyway.
      final lead = Lead(
        id: q.leadId,
        source: 'Unknown',
        createdAt: q.createdAt,
        name: q.quoteRequest.customerName,
        company: q.quoteRequest.companyName,
        location: q.quoteRequest.location,
        phone: q.quoteRequest.phone,
        email: q.quoteRequest.email,
        requirement: q.quoteRequest.productName,
        status: 'Generated',
        assignedTo: q.employeeId,
        remark: '',
        website: '',
      );

      final mobile = await _getEmployeeMobile(q.employeeId);
      final bytes = await PdfService().generateQuoteData(
        lead,
        q.quoteRequest,
        creatorMobile: mobile,
        creatorName: q.employeeName,
      );
      
      final nameSource = q.quoteRequest.companyName.isNotEmpty
          ? q.quoteRequest.companyName
          : q.quoteRequest.customerName;
      final safeName = nameSource.isEmpty
          ? 'quotation'
          : nameSource.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final number = _shortQuoteNumber(q.currentRefNo);
      final filename = number.isEmpty
          ? '${safeName}_quotation.pdf'
          : '${safeName}_$number.pdf';

      if (kIsWeb) {
        await Printing.sharePdf(bytes: bytes, filename: filename);
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Downloaded $filename')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to download: $e')),
        );
      }
    }
  }

  Future<void> _editQuotation(QuotationModel q) async {
    final lead = Lead(
      id: q.leadId,
      source: 'Unknown',
      createdAt: q.createdAt,
      name: q.quoteRequest.customerName,
      company: q.quoteRequest.companyName,
      location: q.quoteRequest.location,
      phone: q.quoteRequest.phone,
      email: q.quoteRequest.email,
      requirement: q.quoteRequest.productName,
      status: 'Generated',
      assignedTo: q.employeeId,
      remark: '',
      website: '',
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QuoteBuilderDialog(
        lead: lead,
        productService: widget.productService,
        existingQuotation: q,
      ),
    );
  }

  Future<void> _viewQuotation(QuotationModel q) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final lead = Lead(
        id: q.leadId,
        source: 'Unknown',
        createdAt: q.createdAt,
        name: q.quoteRequest.customerName,
        company: q.quoteRequest.companyName,
        location: q.quoteRequest.location,
        phone: q.quoteRequest.phone,
        email: q.quoteRequest.email,
        requirement: q.quoteRequest.productName,
        status: 'Generated',
        assignedTo: q.employeeId,
        remark: '',
        website: '',
      );

      final mobile = await _getEmployeeMobile(q.employeeId);
      final bytes = await PdfService().generateQuoteData(
        lead,
        q.quoteRequest,
        creatorMobile: mobile,
        creatorName: q.employeeName,
      );
      
      if (!mounted) return;
      await showQuotePdfPreview(
        context,
        bytes: bytes,
        title: q.currentRefNo,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error viewing: $e')));
    }
  }

  Future<void> _deleteQuotation(QuotationModel q) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Quotation?'),
        content: Text('Are you sure you want to delete ${q.currentRefNo}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _quotationService.deleteQuotation(q.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quotation deleted.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by Ref No, Company, or Customer...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: Text(_filterDate == null
                    ? 'Filter Date'
                    : DateFormat('dd.MM.yyyy').format(_filterDate!)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _filterDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _filterDate = picked);
                  }
                },
              ),
              if (_filterDate != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _filterDate = null),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<QuotationModel>>(
            stream: _quotationService.getQuotationsStream(
              employeeId: widget.isAdmin ? null : _currentUid,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                debugPrint('Quotations Stream Error: ${snapshot.error}');
                return Center(
                  child: Text(
                    'Could not load quotations: ${snapshot.error}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var items = snapshot.data ?? const <QuotationModel>[];
              
              if (_searchQuery.isNotEmpty) {
                final q = _searchQuery.toLowerCase();
                items = items.where((item) {
                  return item.currentRefNo.toLowerCase().contains(q) ||
                         item.quoteRequest.companyName.toLowerCase().contains(q) ||
                         item.quoteRequest.customerName.toLowerCase().contains(q);
                }).toList();
              }
              if (_filterDate != null) {
                items = items.where((item) {
                  return item.createdAt.year == _filterDate!.year &&
                         item.createdAt.month == _filterDate!.month &&
                         item.createdAt.day == _filterDate!.day;
                }).toList();
              }

              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.request_quote_outlined,
                        size: 56,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No quotations yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(20).copyWith(top: 0),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final q = items[index];
                  final dateStr =
                      DateFormat('MMM d, yyyy, hh:mm a').format(q.createdAt);
                  
                  String createdBy = q.employeeName;
                  if (createdBy == 'atsadmin@gmail.com') {
                    createdBy = 'Admin';
                  } else if (createdBy.contains('@')) {
                    createdBy = createdBy.split('@')[0];
                    if (createdBy.isNotEmpty) {
                      createdBy = createdBy[0].toUpperCase() + createdBy.substring(1);
                    }
                  }
                  
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(Icons.picture_as_pdf_rounded, color: theme.colorScheme.onPrimaryContainer),
                      ),
                      title: Text(
                        '${q.quoteRequest.companyName.isEmpty ? q.quoteRequest.customerName : q.quoteRequest.companyName} (${q.currentRefNo})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Product: ${q.quoteRequest.productName} • Created: $dateStr',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.isAdmin)
                            Text(
                              'Created by: $createdBy',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 0,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'INR ${q.quoteRequest.totalAmount.toStringAsFixed(0)}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                icon: const Icon(Icons.remove_red_eye_outlined, size: 22),
                                tooltip: 'View PDF',
                                onPressed: () => _viewQuotation(q),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                icon: const Icon(Icons.edit_document, size: 22),
                                tooltip: 'Edit Quotation',
                                onPressed: () => _editQuotation(q),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                icon: const Icon(Icons.download_rounded, size: 22),
                                tooltip: 'Download PDF',
                                onPressed: () => _downloadQuotation(q),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                                tooltip: 'Delete',
                                onPressed: () => _deleteQuotation(q),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
