import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cancel_follow_up_dialog.dart';
import 'quotation_picker_dialog.dart';
import '../../models/lead_draft.dart';
import '../../models/lead_event_model.dart';
import '../../models/lead_model.dart';
import '../../models/lead_product_line.dart';
import '../../services/auth_service.dart';
import '../../services/lead_attachment_service.dart';
import '../../services/lead_draft_store.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import '../../services/reminder_service.dart';
import '../../services/source_service.dart';
import '../../models/quotation_model.dart';
import '../../services/quotation_service.dart';
import '../../services/whatsapp_service.dart';
import 'lead_date_field.dart';
import 'lead_product_lines_editor.dart';
import 'minimized_leads_bar.dart';
import 'quote_builder_dialog.dart';

enum _CloseAction { cancel, minimize, discard, save }

const double _kCompactBreakpoint = 720;
const double _kTwoColumnBreakpoint = 900;

const Color _kBgSurface = Color(0xFFF5F7FB);
const Color _kCardBorder = Color(0xFFE6EAF2);
const Color _kInputFill = Color(0xFFF7F8FC);
const Color _kTextPrimary = Color(0xFF1D2638);
const Color _kTextSecondary = Color(0xFF69758D);
const Color _kTextMuted = Color(0xFF8E99AE);
const Color _kLabelColor = Color(0xFF44516B);

/// Opens a responsive lead detail panel.
///
/// - On desktop / tablet: slides in from the right, up to 960 px wide.
/// - On phones (< 720 px): takes the full screen.
class LeadDetailsModal {
  LeadDetailsModal._();

  static Future<void> show(
    BuildContext context, {
    required Lead lead,
    required LeadService leadService,
    required AuthService authService,
    ProductService? productService,
    LeadDraft? draft,
  }) {
    final screenW = MediaQuery.sizeOf(context).width;
    final screenH = MediaQuery.sizeOf(context).height;
    final isCompact = screenW < _kCompactBreakpoint;
    final panelWidth = isCompact
        ? screenW
        : math.min(960.0, screenW * (screenW >= 1200 ? 0.78 : 0.9));

    MinimizedLeadsBar.ensureMounted(context);
    // Reopening a minimised lead takes its chip away; minimising again puts a
    // fresh one back.
    LeadDraftStore.instance.remove(lead.id);

    return showDialog<void>(
      context: context,
      // Side/backdrop tap must not close the lead and discard unsaved edits.
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          alignment: isCompact ? Alignment.center : Alignment.centerRight,
          child: SizedBox(
            width: panelWidth,
            height: screenH,
            child: Material(
              elevation: isCompact ? 0 : 16,
              color: _kBgSurface,
              child: _LeadDetailsPanel(
                lead: lead,
                leadService: leadService,
                authService: authService,
                productService: productService,
                initialDraft: draft,
                onClose: () => Navigator.of(dialogContext).pop(),
                onMinimize: (captured) {
                  LeadDraftStore.instance.add(
                    MinimizedLead(
                      draft: captured,
                      restore: (restoreContext) => show(
                        restoreContext,
                        lead: captured.original,
                        leadService: leadService,
                        authService: authService,
                        productService: productService,
                        draft: captured,
                      ),
                    ),
                  );
                  Navigator.of(dialogContext).pop();
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LeadDetailsPanel extends StatefulWidget {
  const _LeadDetailsPanel({
    required this.lead,
    required this.leadService,
    required this.authService,
    required this.onClose,
    required this.onMinimize,
    this.productService,
    this.initialDraft,
  });

  final Lead lead;
  final LeadService leadService;
  final AuthService authService;
  final ProductService? productService;
  final VoidCallback onClose;
  final void Function(LeadDraft draft) onMinimize;

  /// Edits captured when this lead was previously minimised.
  final LeadDraft? initialDraft;

  @override
  State<_LeadDetailsPanel> createState() => _LeadDetailsPanelState();
}

class _LeadDetailsPanelState extends State<_LeadDetailsPanel>
    with SingleTickerProviderStateMixin {
  late String _status;
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _companyController;
  late final TextEditingController _remarkController;
  late final TextEditingController _locationController;
  late final TextEditingController _websiteController;
  late final List<LeadProductLineFields> _productLines;
  late final TextEditingController _totalAmountController;
  late final TextEditingController _timelineNoteController;

  // Tender fields
  late final TextEditingController _bidNoController;
  late final TextEditingController _qtyController;
  late final TextEditingController _technicalController;
  late final TextEditingController _commercialController;
  late final TextEditingController _lossReasonController;
  late final TextEditingController _designationController;

  // Enquiry detail + order/billing fields.
  late final TextEditingController _projectNameController;
  late final TextEditingController _quantityRequiredController;
  late final TextEditingController _deliveryAreaController;
  late final TextEditingController _deliveryPocController;
  late final TextEditingController _specificationController;
  late final TextEditingController _poNumberController;
  late final TextEditingController _invoiceNumberController;
  String? _poAttachmentUrl;
  String? _poAttachmentName;
  String? _invoiceAttachmentUrl;
  String? _invoiceAttachmentName;
  String? _uploadingAttachmentKind;
  final LeadAttachmentService _attachmentService = LeadAttachmentService();

  DateTime? _dueDate;
  late DateTime _leadDate;

  String? _selectedSource;
  late final TabController _tabController;
  DateTime? _installationDate;
  DateTime? _nextFollowUpDate;
  bool _saving = false;
  bool _schedulingFollowUp = false;
  bool _statusUpdating = false;
  bool _deleting = false;
  bool _postingNote = false;
  bool _amountFromQuote = false;
  bool _loadingQuoteAmount = false;
  final WhatsAppService _whatsAppService = WhatsAppService();
  final QuotationService _quotationService = QuotationService();

  /// Quotation currently backing the deal amount.
  String _quotationId = '';
  String _quotationRefNo = '';

  /// Amount we auto-filled from a quotation AND already wrote to Firestore.
  /// Held out of the dirty check so a self-persisted refresh never raises the
  /// "unsaved changes" prompt for a value the modal itself just saved.
  double? _persistedQuoteAmount;

  late final Stream<List<LeadEvent>> _eventsStream = FirebaseFirestore.instance
      .collection('leads')
      .doc(widget.lead.id)
      .collection('events')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(LeadEvent.fromFirestore).toList(growable: false),
      )
      .asBroadcastStream();

  late final Stream<List<String>> _cachedSourcesStream = SourceService.instance
      .watchSources()
      .asBroadcastStream();

  bool _isEditingRemark = false;
  bool _isAddingRemark = false;
  late String _savedRemarkText;

  /// Snapshot of the form right after open / restore / successful save.
  late String _pristineSignature;

  @override
  void initState() {
    super.initState();
    _status = widget.lead.status;
    final initialName = (widget.lead.isTender && widget.lead.name == 'Tender Contact')
        ? ''
        : widget.lead.name;
    final initialPhone = (widget.lead.isTender && widget.lead.phone == 'N/A')
        ? ''
        : widget.lead.phone;
    _nameController = TextEditingController(text: initialName);
    _emailController = TextEditingController(text: widget.lead.email);
    _phoneController = TextEditingController(text: initialPhone);
    _companyController = TextEditingController(text: widget.lead.company);
    _remarkController = TextEditingController(text: widget.lead.remark);
    _locationController = TextEditingController(text: widget.lead.location);
    _websiteController = TextEditingController(text: widget.lead.website);
    final activeProducts = widget.lead.activeProductLines;
    _productLines = activeProducts.isNotEmpty
        ? activeProducts.map((l) => LeadProductLineFields(initial: l)).toList()
        : [
            LeadProductLineFields(
              initial: LeadProductLine(
                requirement: widget.lead.requirement,
                modelNo: widget.lead.modelNo,
              ),
            ),
          ];
    _selectedSource = widget.lead.source.trim().isNotEmpty
        ? widget.lead.source.trim()
        : null;
    _totalAmountController = TextEditingController(
      text: widget.lead.totalAmount > 0
          ? widget.lead.totalAmount.toString()
          : '',
    );
    _bidNoController = TextEditingController(text: widget.lead.bidNo);
    _qtyController = TextEditingController(
      text: widget.lead.quantity.toString(),
    );
    _technicalController = TextEditingController(
      text: widget.lead.technicalStatus,
    );
    _commercialController = TextEditingController(
      text: widget.lead.commercialStatus,
    );
    _lossReasonController = TextEditingController(text: widget.lead.lossReason);
    _designationController = TextEditingController(text: widget.lead.designation);
    _projectNameController = TextEditingController(text: widget.lead.projectName);
    _quantityRequiredController =
        TextEditingController(text: widget.lead.quantityRequired);
    _deliveryAreaController =
        TextEditingController(text: widget.lead.deliveryArea);
    _deliveryPocController = TextEditingController(text: widget.lead.deliveryPoc);
    _specificationController =
        TextEditingController(text: widget.lead.specification);
    _poNumberController = TextEditingController(text: widget.lead.poNumber);
    _invoiceNumberController =
        TextEditingController(text: widget.lead.invoiceNumber);
    _poAttachmentUrl = widget.lead.poAttachmentUrl;
    _poAttachmentName = widget.lead.poAttachmentName;
    _invoiceAttachmentUrl = widget.lead.invoiceAttachmentUrl;
    _invoiceAttachmentName = widget.lead.invoiceAttachmentName;
    _dueDate = widget.lead.dueDate;
    _leadDate = widget.lead.leadDate;
    _timelineNoteController = TextEditingController();
    _installationDate = widget.lead.installationDate;
    _nextFollowUpDate = widget.lead.nextFollowUpDate;
    _quotationId = widget.lead.quotationId;
    _quotationRefNo = widget.lead.quotationRefNo;
    _amountFromQuote = widget.lead.quotationId.isNotEmpty;
    _tabController = TabController(length: 2, vsync: this);

    _savedRemarkText = widget.lead.remark.trim();
    _isEditingRemark = _savedRemarkText.isEmpty;

    final draft = widget.initialDraft;
    if (draft != null) _applyDraft(draft);

    _pristineSignature = _formSignature();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLoadAmountFromQuotation();
    });
  }

  void _applyDraft(LeadDraft draft) {
    final d = draft.edited;
    _status = d.status;
    // Restore the quotation link too, so a minimise/restore round trip does
    // not drop it on the next Save.
    _quotationId = d.quotationId;
    _quotationRefNo = d.quotationRefNo;
    _nameController.text = d.name;
    _emailController.text = d.email;
    _phoneController.text = d.phone;
    _companyController.text = d.company;
    _remarkController.text = d.remark;
    _locationController.text = d.location;
    _websiteController.text = d.website;
    _totalAmountController.text =
        d.totalAmount > 0 ? d.totalAmount.toStringAsFixed(0) : '';
    _bidNoController.text = d.bidNo;
    _qtyController.text = d.quantity.toString();
    _technicalController.text = d.technicalStatus;
    _commercialController.text = d.commercialStatus;
    _lossReasonController.text = d.lossReason;
    _designationController.text = d.designation;
    _projectNameController.text = d.projectName;
    _quantityRequiredController.text = d.quantityRequired;
    _deliveryAreaController.text = d.deliveryArea;
    _deliveryPocController.text = d.deliveryPoc;
    _specificationController.text = d.specification;
    _poNumberController.text = d.poNumber;
    _invoiceNumberController.text = d.invoiceNumber;
    _timelineNoteController.text = draft.timelineNote;

    _selectedSource = d.source.trim().isNotEmpty ? d.source.trim() : null;
    _leadDate = d.leadDate;
    _dueDate = d.dueDate;
    _installationDate = d.installationDate;
    _nextFollowUpDate = d.nextFollowUpDate;

    _poAttachmentUrl = d.poAttachmentUrl;
    _poAttachmentName = d.poAttachmentName;
    _invoiceAttachmentUrl = d.invoiceAttachmentUrl;
    _invoiceAttachmentName = d.invoiceAttachmentName;

    final lines = d.activeProductLines;
    if (lines.isNotEmpty) {
      for (final line in _productLines) {
        line.dispose();
      }
      _productLines
        ..clear()
        ..addAll(lines.map((l) => LeadProductLineFields(initial: l)));
    }

    _savedRemarkText = d.remark.trim();
    _isEditingRemark = _savedRemarkText.isEmpty;
  }

  LeadDraft _captureDraft() {
    return LeadDraft(
      original: widget.initialDraft?.original ?? widget.lead,
      edited: _leadFromForm(),
      timelineNote: _timelineNoteController.text,
    );
  }

  String _formSignature() {
    final lead = _leadFromForm();
    return [
      lead.status,
      lead.name,
      lead.email,
      lead.phone,
      lead.company,
      lead.remark,
      lead.location,
      lead.website,
      lead.source,
      (_persistedQuoteAmount != null &&
              lead.totalAmount == _persistedQuoteAmount)
          ? '<quote>'
          : lead.totalAmount.toString(),
      lead.bidNo,
      lead.quantity.toString(),
      lead.technicalStatus,
      lead.commercialStatus,
      lead.lossReason,
      lead.designation,
      lead.projectName,
      lead.quantityRequired,
      lead.deliveryArea,
      lead.deliveryPoc,
      lead.specification,
      lead.poNumber,
      lead.invoiceNumber,
      lead.leadDate.toIso8601String(),
      lead.dueDate?.toIso8601String() ?? '',
      lead.installationDate?.toIso8601String() ?? '',
      lead.nextFollowUpDate?.toIso8601String() ?? '',
      lead.poAttachmentUrl ?? '',
      lead.invoiceAttachmentUrl ?? '',
      for (final line in lead.activeProductLines)
        '${line.requirement}~${line.modelNo}',
      _timelineNoteController.text,
    ].join('\u0001');
  }

  bool get _hasUnsavedChanges => _formSignature() != _pristineSignature;

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!_hasUnsavedChanges) {
      widget.onClose();
      return;
    }

    final action = await showDialog<_CloseAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'This lead has changes that have not been saved. '
          'Minimise it to come back later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_CloseAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_CloseAction.minimize),
            child: const Text('Minimise'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_CloseAction.discard),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_CloseAction.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == _CloseAction.cancel) return;

    switch (action) {
      case _CloseAction.discard:
        widget.onClose();
      case _CloseAction.minimize:
        _minimize();
      case _CloseAction.save:
        await _saveDetails();
        if (mounted) widget.onClose();
      case _CloseAction.cancel:
        break;
    }
  }

  void _minimize() => widget.onMinimize(_captureDraft());

  String get _currentUid => widget.authService.currentUser?.uid ?? '';

  /// Applies a quotation's total to the lead and persists the link.
  Future<void> _applyQuotation(QuotationModel q) async {
    final amt = q.quoteRequest.totalAmount;
    final ref = q.currentRefNo.isNotEmpty
        ? q.currentRefNo
        : q.quoteRequest.refNo;
    setState(() {
      _totalAmountController.text = amt.toStringAsFixed(
        amt == amt.roundToDouble() ? 0 : 2,
      );
      _amountFromQuote = true;
      _quotationId = q.id;
      _quotationRefNo = ref;
    });
    try {
      // Persist so Won revenue / analytics work without an extra Save tap.
      await widget.leadService.updateLeadQuotationLink(
        widget.lead.id,
        amount: amt,
        quotationId: q.id,
        quotationRefNo: ref,
      );
      _persistedQuoteAmount = amt;
    } catch (_) {
      // Not saved, so it really is an unsaved change.
      _persistedQuoteAmount = null;
    }
  }

  /// Pulls the latest quotation onto the lead.
  ///
  /// "Latest" means the newest revision, not the largest amount — a revision
  /// that lowers the price has to win. A manual pick from the picker holds
  /// only until a newer revision exists; then the newer one takes over.
  Future<void> _maybeLoadAmountFromQuotation({bool force = false}) async {
    final current = double.tryParse(
          _totalAmountController.text.replaceAll(',', '').trim(),
        ) ??
        0;
    if (!force && current > 0 && !_amountFromQuote) return;

    setState(() => _loadingQuoteAmount = true);
    try {
      final latest = await _quotationService.getLatestQuotationForLead(
        widget.lead.id,
        currentUid: _currentUid,
      );
      if (!mounted || latest == null) return;
      if (latest.id == _quotationId && !force) return;
      if (force || current <= 0 || _amountFromQuote) {
        await _applyQuotation(latest);
      }
    } finally {
      if (mounted) setState(() => _loadingQuoteAmount = false);
    }
  }

  Future<void> _openQuotationPicker() async {
    setState(() => _loadingQuoteAmount = true);
    late final QuotationsForLead result;
    try {
      result = await _quotationService.getQuotationsForLead(
        widget.lead.id,
        currentUid: _currentUid,
      );
    } finally {
      if (mounted) setState(() => _loadingQuoteAmount = false);
    }
    if (!mounted) return;

    final picked = await showQuotationPicker(
      context,
      quotations: result.quotations,
      selectedId: _quotationId.isEmpty ? null : _quotationId,
      status: result.status,
    );
    if (picked == null || !mounted) return;
    await _applyQuotation(picked);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _companyController.dispose();
    _remarkController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    for (final line in _productLines) {
      line.dispose();
    }
    _totalAmountController.dispose();
    _timelineNoteController.dispose();
    _bidNoController.dispose();
    _qtyController.dispose();
    _technicalController.dispose();
    _commercialController.dispose();
    _lossReasonController.dispose();
    _designationController.dispose();
    _projectNameController.dispose();
    _quantityRequiredController.dispose();
    _deliveryAreaController.dispose();
    _deliveryPocController.dispose();
    _specificationController.dispose();
    _poNumberController.dispose();
    _invoiceNumberController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  String _formatDateTime(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '${_formatDate(value)} · $h:$m';
  }

  String _relativeTime(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} mo ago';
    return '${(diff.inDays / 365).floor()} y ago';
  }

  String _initials(String name) {
    if (name.trim().isEmpty && widget.lead.isTender) {
      return 'TD';
    }
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  Color _statusColor(String status) {
    if (widget.lead.isTender) {
      switch (Lead.migrateLegacyTenderStatus(status)) {
        case 'New':
          return const Color(0xFF3B82F6);
        case 'Query Raised':
          return const Color(0xFF8B5CF6);
        case 'Query Responded':
          return const Color(0xFF06B6D4);
        case 'Technical Evaluation':
          return const Color(0xFFF59E0B);
        case 'Qualified':
          return const Color(0xFF6366F1);
        case 'Disqualified':
          return const Color(0xFF94A3B8);
        case 'Reverse Auction(RA)':
          return const Color(0xFF0EA5E9);
        case 'Won':
          return const Color(0xFF10B981);
        case 'Loss':
          return const Color(0xFFEF4444);
        default:
          return _kTextSecondary;
      }
    }
    switch (status) {
      case 'New':
        return const Color(0xFF3B82F6);
      case 'Contacted':
        return const Color(0xFFF59E0B);
      case 'Proposal':
        return const Color(0xFF6366F1);
      case 'Follow-up':
        return const Color(0xFF8B5CF6);
      case 'Won':
        return const Color(0xFF10B981);
      case 'Lost':
        return const Color(0xFFEF4444);
      default:
        return _kTextSecondary;
    }
  }

  String _followUpStatusLabel() {
    final d = _nextFollowUpDate;
    if (d == null) return 'No follow-up scheduled';
    return DateFormat('dd MMM yyyy, hh:mm a').format(d);
  }

  Future<void> _onCancelFollowUpPressed() async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showCancelFollowUpDialog(
      context,
      leadName: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : _companyController.text.trim(),
    );
    if (reason == null || !mounted) return;

    setState(() => _schedulingFollowUp = true);
    try {
      await widget.leadService.cancelFollowUp(widget.lead.id, reason: reason);
      if (!mounted) return;
      setState(() {
        _nextFollowUpDate = null;
        _schedulingFollowUp = false;
        // Already persisted, so it must not count as an unsaved edit.
        _pristineSignature = _formSignature();
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Follow-up cancelled.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _schedulingFollowUp = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not cancel the follow-up: $e')),
      );
    }
  }

  Future<void> _onSetFollowUpPressed() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDate = DateTime(now.year + 5, now.month, now.day);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: lastDate,
      helpText: 'Follow-up date',
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
      helpText: 'Follow-up time',
    );
    if (pickedTime == null || !mounted) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() => _schedulingFollowUp = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final alarmScheduled = await widget.leadService.scheduleFollowUp(
        widget.lead.id,
        combined,
      );
      if (mounted) {
        setState(() => _nextFollowUpDate = combined);
        if (!ReminderService.instance.isAndroid) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Follow-up saved. Phone reminders work only on the Android app.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (!alarmScheduled) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Follow-up saved, but phone reminder could not be set. '
                'Allow Notifications and Alarms & reminders in phone settings, then set follow-up again.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 6),
            ),
          );
        } else if (!ReminderService.instance.exactAlarmsAllowed) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Follow-up saved. Allow "Alarms & reminders" in app settings for exact-time alerts.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Follow-up scheduled with phone reminder.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not schedule follow-up.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _schedulingFollowUp = false);
    }
  }

  String _installationDateLabel() {
    final date = _installationDate;
    if (date == null) return 'Select Installation Date';
    return _formatDate(date);
  }

  String _digitsOnlyPhone(String raw) {
    return raw.replaceAll(RegExp(r'\D'), '');
  }

  IconData _iconForEventAction(String? action) {
    switch (action) {
      case 'Created':
        return Icons.flag_outlined;
      case 'Status Change':
        return Icons.sync_alt_rounded;
      case 'Note':
        return Icons.sticky_note_2_outlined;
      case 'Follow-up Scheduled':
        return Icons.event_available_rounded;
      case 'Follow-up Cancelled':
        return Icons.event_busy_outlined;
      case 'Smart Follow-up Scheduled':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.circle_outlined;
    }
  }

  Color _colorForEventAction(String? action) {
    switch (action) {
      case 'Created':
        return const Color(0xFF3B82F6);
      case 'Status Change':
        return const Color(0xFF6366F1);
      case 'Note':
        return const Color(0xFFF59E0B);
      case 'Follow-up Scheduled':
        return const Color(0xFF10B981);
      case 'Follow-up Cancelled':
        return const Color(0xFFEF4444);
      case 'Smart Follow-up Scheduled':
        return const Color(0xFF8B5CF6);
      default:
        return _kTextSecondary;
    }
  }

  Future<void> _launchWhatsApp() async {
    final messenger = ScaffoldMessenger.of(context);
    final leadForMessage = _leadFromForm();
    final digits = _digitsOnlyPhone(leadForMessage.phone);
    if (digits.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Add a valid phone number first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Uri uri;
    try {
      uri = await _whatsAppService.buildTemplateUri(leadForMessage);
    } catch (_) {
      uri = _whatsAppService.buildUriFromMessage(
        leadForMessage,
        'Hi ${leadForMessage.name.trim().isEmpty ? 'there' : leadForMessage.name.trim()},',
      );
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _launchCall() async {
    final messenger = ScaffoldMessenger.of(context);
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No phone number to call.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final uri = Uri.parse('tel:$raw');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not start the call.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _launchEmail() async {
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Add a valid email address first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final lead = _leadFromForm();
    if (kIsWeb) {
      _showWebEmailOptions(context, lead);
      return;
    }
    final ok = await launchUrl(
      Uri(scheme: 'mailto', path: lead.email.trim()),
      mode: LaunchMode.platformDefault,
    );
    if (!ok && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open email app.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showWebEmailOptions(BuildContext context, Lead lead) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final encodedTo = Uri.encodeComponent(lead.email.trim());
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        Future<void> openUrl(Uri uri) async {
          Navigator.of(sheetContext).pop();
          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!ok && context.mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Could not open link.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }

        Future<void> openMailto() async {
          Navigator.of(sheetContext).pop();
          final ok = await launchUrl(
            Uri(scheme: 'mailto', path: lead.email.trim()),
            mode: LaunchMode.platformDefault,
          );
          if (!ok && context.mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Could not open default mail app.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }

        Future<void> copyEmail() async {
          await Clipboard.setData(ClipboardData(text: lead.email.trim()));
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          if (context.mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Email copied to clipboard'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(sheetContext).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(
                  'Choose Email Provider',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.mail_rounded, color: colorScheme.primary),
                title: const Text('Gmail'),
                onTap: () => openUrl(
                  Uri.parse(
                    'https://mail.google.com/mail/?view=cm&fs=1&to=$encodedTo',
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.mail_outline_rounded,
                  color: colorScheme.primary,
                ),
                title: const Text('Outlook (Web)'),
                onTap: () => openUrl(
                  Uri.parse(
                    'https://outlook.live.com/mail/0/deeplink/compose?to=$encodedTo',
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.open_in_new_rounded,
                  color: colorScheme.primary,
                ),
                title: const Text('System Default App'),
                subtitle: Text(
                  lead.email.trim(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: openMailto,
              ),
              ListTile(
                leading: Icon(Icons.copy_rounded, color: colorScheme.primary),
                title: const Text('Copy Address'),
                onTap: copyEmail,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _postTimelineNote() async {
    final text = _timelineNoteController.text.trim();
    if (text.isEmpty) return;

    setState(() => _postingNote = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final userName = await widget.authService.getCurrentUserDisplayName();
      await widget.leadService.addNoteToLead(widget.lead.id, text, userName);
      if (mounted) {
        _timelineNoteController.clear();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Note posted to timeline.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not post note.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _postingNote = false);
    }
  }

  Future<void> _pickInstallationDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _installationDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Installation Date',
    );
    if (picked != null && mounted) {
      setState(() => _installationDate = picked);
    }
  }

  Future<String?> _promptForLossReason() async {
    final localController = TextEditingController(
      text: _lossReasonController.text,
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reason for Loss'),
        content: TextField(
          controller: localController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Please specify the reason...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(localController.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _onStatusChanged(String? value) async {
    if (value == null || value == _status) return;
    if (value == 'Won' && _installationDate == null) {
      await _pickInstallationDate();
      if (_installationDate == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Installation date is required before marking this lead as Won.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    if (value == 'Loss' || value == 'Lost') {
      final reason = await _promptForLossReason();
      if (reason == null || reason.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'A reason is required before marking this lead as Lost/Loss.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      _lossReasonController.text = reason.trim();
    }

    setState(() => _statusUpdating = true);
    try {
      final leadSnapshot = _leadFromForm(statusOverride: value);
      await widget.leadService.updateLeadStatus(
        widget.lead.id,
        value,
        sourceLead: leadSnapshot,
        installationDate: value == 'Won' ? _installationDate : null,
      );
      if (mounted) setState(() => _status = value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update status.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _statusUpdating = false);
    }
  }

  Lead _leadFromForm({String? statusOverride}) {
    return Lead(
      id: widget.lead.id,
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      company: _companyController.text.trim(),
      status: statusOverride ?? _status,
      assignedTo: widget.lead.assignedTo,
      createdAt: widget.lead.createdAt,
      leadDate: _leadDate,
      remark: _remarkController.text.trim(),
      location: _locationController.text.trim(),
      website: _websiteController.text.trim(),
      productLines: _productLines.map((e) => e.toLine()).toList(),
      source: _selectedSource ?? '',
      targetGas: widget.lead.targetGas,
      measuringRange: widget.lead.measuringRange,
      industrySector: widget.lead.industrySector,
      installationDate: _installationDate,
      nextFollowUpDate: _nextFollowUpDate,
      isAmcLead: widget.lead.isAmcLead,
      // updateLead rewrites the whole document, so these must ride along or
      // the next Save would blank the lead's quotation link.
      quotationId: _quotationId,
      quotationRefNo: _quotationRefNo,
      creatorName: widget.lead.creatorName,
      totalAmount:
          double.tryParse(
            _totalAmountController.text.replaceAll(',', '').trim(),
          ) ??
          0,
      isTender: widget.lead.isTender,
      bidNo: _bidNoController.text.trim(),
      quantity: int.tryParse(_qtyController.text) ?? 1,
      dueDate: _dueDate,
      technicalStatus: _technicalController.text.trim(),
      commercialStatus: _commercialController.text.trim(),
      lossReason: _lossReasonController.text.trim(),
      designation: _designationController.text.trim(),
      projectName: _projectNameController.text.trim(),
      quantityRequired: _quantityRequiredController.text.trim(),
      deliveryArea: _deliveryAreaController.text.trim(),
      deliveryPoc: _deliveryPocController.text.trim(),
      specification: _specificationController.text.trim(),
      poNumber: _poNumberController.text.trim(),
      poAttachmentUrl: _poAttachmentUrl,
      poAttachmentName: _poAttachmentName,
      invoiceNumber: _invoiceNumberController.text.trim(),
      invoiceAttachmentUrl: _invoiceAttachmentUrl,
      invoiceAttachmentName: _invoiceAttachmentName,
      lastModified: widget.lead.lastModified,
    );
  }

  void _openQuoteBuilder() {
    showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Quotation Format Select Karein'),
        content: const Text('Quotation kis format me generate karni hai?'),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop('ATEPL'),
            child: const Text('ATEPL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('ATS'),
            child: const Text('ATS'),
          ),
        ],
      ),
    ).then((choice) async {
      if (choice == null) return;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => QuoteBuilderDialog(
          lead: _leadFromForm(),
          productService: widget.productService,
          initialCompanyType: choice,
        ),
      );
      if (!mounted) return;
      // After quotation save, pull latest quote total into amount field.
      await _maybeLoadAmountFromQuotation(force: true);
    });
  }

  Future<void> _saveDetails() async {
    if (_isAddingRemark) {
      if (_remarkController.text.trim().isNotEmpty) {
        final nowStr = DateFormat(
          'dd MMM yyyy, hh:mm a',
        ).format(DateTime.now());
        final newNote = '[$nowStr] ${_remarkController.text.trim()}';
        final prefix = _savedRemarkText.trim().isNotEmpty
            ? '${_savedRemarkText.trim()}\n\n---\n'
            : '';
        _remarkController.text = prefix + newNote;
      } else {
        _remarkController.text = _savedRemarkText;
      }
    } else if (_isEditingRemark &&
        _remarkController.text.trim() != _savedRemarkText) {
      if (_remarkController.text.trim().isNotEmpty) {
        final nowStr = DateFormat(
          'dd MMM yyyy, hh:mm a',
        ).format(DateTime.now());
        if (!_remarkController.text.contains('(Edited: $nowStr)')) {
          _remarkController.text =
              _remarkController.text.trim() + '\n(Edited: $nowStr)';
        }
      }
    }
    _savedRemarkText = _remarkController.text.trim();

    final poPresent = (_poAttachmentUrl ?? '').trim().isNotEmpty;
    final alreadyClosed =
        _status == 'Won' ||
        _status == 'Lost' ||
        _status == 'Loss' ||
        _status == 'Disqualified';
    final autoWinFromPo = poPresent && !alreadyClosed;
    if (autoWinFromPo) {
      _installationDate ??= DateTime.now();
      if (mounted) setState(() => _status = 'Won');
    }

    setState(() {
      _saving = true;
      if (_savedRemarkText.isNotEmpty) {
        _isEditingRemark = false;
        _isAddingRemark = false;
      }
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final lead = _leadFromForm();
      await widget.leadService.updateLead(lead);
      if (autoWinFromPo) {
        // Status event + AMC follow-up (same path as manual Won).
        await widget.leadService.updateLeadStatus(
          lead.id,
          'Won',
          sourceLead: lead,
          installationDate: _installationDate,
        );
      }
      _pristineSignature = _formSignature();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              autoWinFromPo
                  ? 'PO saved — lead marked Won and moved to Won revenue.'
                  : 'Changes saved.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save changes.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onDeletePressed() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete lead?'),
        content: const Text(
          'This lead will be removed permanently. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.leadService.deleteLead(widget.lead.id);
      if (mounted) widget.onClose();
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not delete lead.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTwoColumn = constraints.maxWidth >= _kTwoColumnBreakpoint;
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                _buildQuickActions(),
                if (!isTwoColumn) _buildTabBar(),
                Expanded(
                  child: isTwoColumn ? _buildTwoColumnBody() : _buildTabBody(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Header -------------------------------------------------------------

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final statusColor = _statusColor(_status);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _kCardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      statusColor.withValues(alpha: 0.85),
                      statusColor.withValues(alpha: 0.55),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(widget.lead.name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.lead.name.isEmpty
                          ? (widget.lead.isTender ? 'Tender' : 'Unnamed lead')
                          : widget.lead.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _kTextPrimary,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    ListenableBuilder(
                      listenable: _companyController,
                      builder: (context, _) {
                        final text = _companyController.text.trim();
                        return Text(
                          text.isEmpty ? 'No company' : text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _kTextSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete lead',
                onPressed: _deleting ? null : _onDeletePressed,
                icon: _deleting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.error,
                        ),
                      )
                    : Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
              ),
              IconButton(
                tooltip: 'Minimise — keeps your changes',
                onPressed: _saving ? null : _minimize,
                icon: const Icon(Icons.remove_rounded, color: _kLabelColor),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: _saving ? null : _requestClose,
                icon: const Icon(Icons.close_rounded, color: _kLabelColor),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatusPill(
                  status: _status,
                  statusColor: statusColor,
                  updating: _statusUpdating,
                  onChanged: _statusUpdating ? null : _onStatusChanged,
                  isTender: widget.lead.isTender,
                ),
              ),
              if (_status == 'Won') ...[
                const SizedBox(width: 10),
                _InstallationChip(
                  label: _installationDateLabel(),
                  onTap: _pickInstallationDate,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // --- Quick actions ------------------------------------------------------

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _kCardBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ActionChip(
              icon: Icons.chat_rounded,
              iconColor: const Color(0xFF25D366),
              label: 'WhatsApp',
              onTap: _launchWhatsApp,
            ),
            const SizedBox(width: 10),
            _ActionChip(
              icon: Icons.call_rounded,
              iconColor: const Color(0xFF3B82F6),
              label: 'Call',
              onTap: _launchCall,
            ),
            const SizedBox(width: 10),
            _ActionChip(
              icon: Icons.mail_outline_rounded,
              iconColor: const Color(0xFF6366F1),
              label: 'Email',
              onTap: _launchEmail,
            ),
            const SizedBox(width: 10),
            _ActionChip(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Generate Quote',
              primary: true,
              onTap: _openQuoteBuilder,
            ),
          ],
        ),
      ),
    );
  }

  // --- Layout bodies ------------------------------------------------------

  Widget _buildTabBar() {
    final theme = Theme.of(context);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TabBar(
        controller: _tabController,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: _kTextSecondary,
        indicatorColor: theme.colorScheme.primary,
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        tabs: const [
          Tab(icon: Icon(Icons.edit_note_rounded, size: 20), text: 'Details'),
          Tab(icon: Icon(Icons.history_rounded, size: 20), text: 'Timeline'),
        ],
      ),
    );
  }

  Widget _buildTabBody() {
    return TabBarView(
      controller: _tabController,
      children: [_buildDetailsColumn(), _buildTimelineColumn()],
    );
  }

  Widget _buildTwoColumnBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildDetailsColumn(withOuterPadding: false),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildTimelineColumn(withOuterPadding: false),
            ),
          ),
        ],
      ),
    );
  }

  // --- Details column -----------------------------------------------------

  Widget _buildDetailsColumn({bool withOuterPadding = true}) {
    return Container(
      color: _kBgSurface,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                withOuterPadding ? 16 : 14,
                withOuterPadding ? 16 : 14,
                withOuterPadding ? 16 : 14,
                16,
              ),
              children: [
                _buildFollowUpCard(),
                const SizedBox(height: 14),
                LeadDateField(
                  value: _leadDate,
                  enabled: !_saving,
                  onChanged: (d) => setState(() => _leadDate = d),
                ),
                const SizedBox(height: 14),
                if (widget.lead.isTender) ...[
                  _SectionCard(
                    title: 'Tender Details',
                    icon: Icons.description_outlined,
                    child: Column(
                      children: [
                        _buildTextField(
                          controller: _bidNoController,
                          label: 'BID NO',
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _companyController,
                          label: 'CUSTOMER NAME',
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _nameController,
                          label: 'CONTACT PERSON NAME',
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _phoneController,
                          label: 'CONTACT PERSON NUMBER',
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _designationController,
                          label: 'CONTACT PERSON DESIGNATION',
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 12),
                        LeadProductLinesEditor(
                          productService:
                              widget.productService ?? ProductService(),
                          lines: _productLines,
                          onChanged: () => setState(() {}),
                          productNameLabel: 'PRODUCT NAME',
                          requireFirstLine: false,
                          enabled: !_saving,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _qtyController,
                          label: 'QTY',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _saving
                              ? null
                              : () async {
                                  final dt = await showDatePicker(
                                    context: context,
                                    initialDate: _dueDate ?? DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (dt != null) {
                                    setState(() => _dueDate = dt);
                                  }
                                },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'DUE DATE',
                              labelStyle: const TextStyle(
                                color: _kLabelColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              filled: true,
                              fillColor: _kInputFill,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: _kCardBorder,
                                ),
                              ),
                            ),
                            child: Text(
                              _dueDate != null
                                  ? DateFormat('dd.MM.yyyy').format(_dueDate!)
                                  : 'Select Date',
                              style: const TextStyle(
                                color: _kTextPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _technicalController,
                          label: 'TECHNICAL',
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _commercialController,
                          label: 'COMMERCIAL',
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  _SectionCard(
                    title: 'Contact',
                    icon: Icons.person_outline_rounded,
                    child: Column(
                      children: [
                        _buildTextField(
                          controller: _nameController,
                          label: 'Customer Name',
                          textCapitalization: TextCapitalization.words,
                          prefixIcon: Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveFieldGrid(
                          children: [
                            _buildTextField(
                              controller: _phoneController,
                              label: 'Contact No.',
                              keyboardType: TextInputType.phone,
                              prefixIcon: Icons.phone_outlined,
                            ),
                            _buildTextField(
                              controller: _emailController,
                              label: 'Email ID',
                              keyboardType: TextInputType.emailAddress,
                              prefixIcon: Icons.mail_outline_rounded,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Company',
                    icon: Icons.business_outlined,
                    child: Column(
                      children: [
                        _buildTextField(
                          controller: _companyController,
                          label: 'Company Name',
                          textCapitalization: TextCapitalization.words,
                          prefixIcon: Icons.apartment_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _websiteController,
                          label: 'Website',
                          keyboardType: TextInputType.url,
                          prefixIcon: Icons.language_rounded,
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveFieldGrid(
                          children: [
                            _buildTextField(
                              controller: _locationController,
                              label: 'Location',
                              textCapitalization: TextCapitalization.words,
                              prefixIcon: Icons.location_on_outlined,
                            ),
                            StreamBuilder<List<String>>(
                              stream: _cachedSourcesStream,
                              builder: (context, snapshot) {
                                final sources =
                                    snapshot.data ??
                                    kDefaultLeadSources;
                                final List<String> effectiveSources = List.from(
                                  sources,
                                );
                                if (_selectedSource != null &&
                                    !effectiveSources.contains(
                                      _selectedSource,
                                    )) {
                                  effectiveSources.add(_selectedSource!);
                                }
                                if (_selectedSource == null &&
                                    effectiveSources.isNotEmpty) {
                                  _selectedSource = effectiveSources.first;
                                }
                                return DropdownButtonFormField<String>(
                                  value: _selectedSource,
                                  isExpanded: true,
                                  style: const TextStyle(
                                    color: _kTextPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Source',
                                    labelStyle: const TextStyle(
                                      color: _kLabelColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    filled: true,
                                    fillColor: _kInputFill,
                                    prefixIcon: const Icon(
                                      Icons.source_outlined,
                                      size: 18,
                                      color: _kTextSecondary,
                                    ),
                                    prefixIconConstraints: const BoxConstraints(
                                      minWidth: 38,
                                      minHeight: 38,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: _kCardBorder,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: _kCardBorder,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  items: effectiveSources
                                      .map(
                                        (s) => DropdownMenuItem<String>(
                                          value: s,
                                          child: Text(s),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) =>
                                      setState(() => _selectedSource = value),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Requirement & Specification',
                    icon: Icons.shopping_bag_outlined,
                    child: LeadProductLinesEditor(
                      productService: widget.productService ?? ProductService(),
                      lines: _productLines,
                      onChanged: () => setState(() {}),
                      productNameLabel: 'Requirement',
                      requireFirstLine: false,
                      enabled: !_saving,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _buildEnquiryDetailsCard(),
                if (_status == 'Loss' || _status == 'Lost') ...[
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Reason for Loss',
                    icon: Icons.cancel_outlined,
                    child: _buildTextField(
                      controller: _lossReasonController,
                      label: 'Please specify the reason...',
                      maxLines: 3,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Deal Amount',
                  icon: Icons.currency_rupee,
                  action: _loadingQuoteAmount
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : InkWell(
                          onTap: _openQuotationPicker,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.receipt_long,
                                  size: 14,
                                  color: _quotationRefNo.isNotEmpty
                                      ? Colors.green.shade700
                                      : _kTextSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _quotationRefNo.isNotEmpty
                                      ? shortQuoteNumber(_quotationRefNo)
                                      : 'Choose quotation',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _quotationRefNo.isNotEmpty
                                        ? Colors.green.shade700
                                        : _kTextSecondary,
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  size: 16,
                                  color: _quotationRefNo.isNotEmpty
                                      ? Colors.green.shade700
                                      : _kTextSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTextField(
                        controller: _totalAmountController,
                        label: 'Amount (₹)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) {
                          // The user is taking ownership of the number, so it
                          // is no longer a quotation-backed value.
                          _persistedQuoteAmount = null;
                          if (_amountFromQuote) {
                            setState(() => _amountFromQuote = false);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _amountFromQuote
                            ? 'Auto-filled from latest quotation. Edit to override.'
                            : 'Quotation banane pe auto fill hoga, ya manually daalein.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _kTextSecondary,
                        ),
                      ),
                      if (!_amountFromQuote) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _loadingQuoteAmount
                                ? null
                                : () => _maybeLoadAmountFromQuotation(
                                      force: true,
                                    ),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Fetch from quotation'),
                            style: TextButton.styleFrom(
                              foregroundColor: _kTextSecondary,
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _buildOrderBillingCard(),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Remark',
                  icon: Icons.notes_outlined,
                  action: (!_isEditingRemark && !_isAddingRemark)
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.add_outlined,
                                size: 18,
                                color: _kTextSecondary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isAddingRemark = true;
                                  _remarkController.clear();
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashRadius: 20,
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: _kTextSecondary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isEditingRemark = true;
                                  _remarkController.text = _savedRemarkText;
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashRadius: 20,
                            ),
                          ],
                        )
                      : null,
                  child: _isEditingRemark
                      ? _buildTextField(
                          controller: _remarkController,
                          label: 'Edit remark',
                          maxLines: 5,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_savedRemarkText.isNotEmpty)
                              ..._savedRemarkText
                                  .split('\n\n---\n')
                                  .map((n) => _buildPremiumNoteCard(n)),
                            if (_isAddingRemark) ...[
                              if (_savedRemarkText.isNotEmpty)
                                const SizedBox(height: 12),
                              _buildTextField(
                                controller: _remarkController,
                                label: 'New note...',
                                maxLines: 3,
                              ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          _buildSaveBar(),
        ],
      ),
    );
  }

  /// Free-text enquiry context: what the customer actually asked for, where it
  /// has to go, and who to reach there. All optional — older leads simply show
  /// empty fields.
  Widget _buildEnquiryDetailsCard() {
    return _SectionCard(
      title: 'Enquiry Details',
      icon: Icons.assignment_outlined,
      child: Column(
        children: [
          _ResponsiveFieldGrid(
            children: [
              _buildTextField(
                controller: _projectNameController,
                label: 'Project Name',
                textCapitalization: TextCapitalization.words,
                prefixIcon: Icons.workspaces_outline,
              ),
              _buildTextField(
                controller: _quantityRequiredController,
                label: 'Quantity Required',
                hint: 'e.g. 2 nos, 500 mtr/day',
                prefixIcon: Icons.numbers_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ResponsiveFieldGrid(
            children: [
              _buildTextField(
                controller: _deliveryAreaController,
                label: 'Delivery Area',
                textCapitalization: TextCapitalization.words,
                prefixIcon: Icons.local_shipping_outlined,
              ),
              _buildTextField(
                controller: _deliveryPocController,
                label: 'Delivery Contact Person',
                textCapitalization: TextCapitalization.words,
                prefixIcon: Icons.contact_phone_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _specificationController,
            label: 'Specification / Scope',
            hint: 'Technical details the customer specified…',
            maxLines: 4,
          ),
        ],
      ),
    );
  }

  /// PO and invoice numbers plus their scanned copies, so the paperwork for a
  /// won deal lives on the lead instead of in somebody's inbox.
  Widget _buildOrderBillingCard() {
    return _SectionCard(
      title: 'Order & Billing',
      icon: Icons.receipt_long_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: _poNumberController,
            label: 'Customer PO Number',
            prefixIcon: Icons.confirmation_number_outlined,
          ),
          const SizedBox(height: 10),
          _AttachmentRow(
            label: 'PO copy',
            fileName: _poAttachmentName,
            url: _poAttachmentUrl,
            isBusy: _uploadingAttachmentKind == 'po',
            isDisabled: _saving || _uploadingAttachmentKind != null,
            onAttach: () => _pickAttachment('po'),
            onRemove: () => _removeAttachment('po'),
            onOpen: () => _openAttachment(_poAttachmentUrl),
          ),
          const Divider(height: 26, color: _kCardBorder),
          _buildTextField(
            controller: _invoiceNumberController,
            label: 'Invoice Number',
            prefixIcon: Icons.description_outlined,
          ),
          const SizedBox(height: 10),
          _AttachmentRow(
            label: 'Invoice copy',
            fileName: _invoiceAttachmentName,
            url: _invoiceAttachmentUrl,
            isBusy: _uploadingAttachmentKind == 'invoice',
            isDisabled: _saving || _uploadingAttachmentKind != null,
            onAttach: () => _pickAttachment('invoice'),
            onRemove: () => _removeAttachment('invoice'),
            onOpen: () => _openAttachment(_invoiceAttachmentUrl),
          ),
          const SizedBox(height: 10),
          const Text(
            'Attachments upload immediately. Press Save to store numbers. '
            'Saving with a PO copy marks the lead Won automatically.',
            style: TextStyle(fontSize: 12, color: _kTextSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAttachment(String kind) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploadingAttachmentKind = kind);
    try {
      final attachment = await _attachmentService.pickAndUpload(
        leadId: widget.lead.id,
        kind: kind,
      );
      if (attachment == null || !mounted) return;

      setState(() {
        if (kind == 'po') {
          _poAttachmentUrl = attachment.url;
          _poAttachmentName = attachment.fileName;
        } else {
          _invoiceAttachmentUrl = attachment.url;
          _invoiceAttachmentName = attachment.fileName;
        }
      });

      // Persist just the pointer straight away, so an upload is never lost if
      // the sheet is closed without pressing Save.
      await widget.leadService.updateLeadFields(widget.lead.id, <String, dynamic>{
        if (kind == 'po') ...{
          'poAttachmentUrl': attachment.url,
          'poAttachmentName': attachment.fileName,
        } else ...{
          'invoiceAttachmentUrl': attachment.url,
          'invoiceAttachmentName': attachment.fileName,
        },
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text('${kind == 'po' ? 'PO' : 'Invoice'} copy attached.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on LeadAttachmentException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not attach that file.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAttachmentKind = null);
    }
  }

  /// Detaches the file from the lead. The uploaded object itself stays in
  /// Storage, so nothing is permanently destroyed by a mis-click.
  Future<void> _removeAttachment(String kind) async {
    final isPo = kind == 'po';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${isPo ? 'PO' : 'invoice'} copy?'),
        content: const Text(
          'The file will be detached from this lead. It stays in company '
          'storage and can be re-attached if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      if (isPo) {
        _poAttachmentUrl = null;
        _poAttachmentName = null;
      } else {
        _invoiceAttachmentUrl = null;
        _invoiceAttachmentName = null;
      }
    });

    try {
      await widget.leadService.updateLeadFields(widget.lead.id, <String, dynamic>{
        if (isPo) ...{
          'poAttachmentUrl': null,
          'poAttachmentName': null,
        } else ...{
          'invoiceAttachmentUrl': null,
          'invoiceAttachmentName': null,
        },
      });
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not remove the attachment.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openAttachment(String? url) async {
    if (url == null || url.trim().isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not open the file.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open the file.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildFollowUpCard() {
    final theme = Theme.of(context);
    final hasDate = _nextFollowUpDate != null;
    final accent = const Color(0xFF8B5CF6);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.08),
            accent.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.notifications_active_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next follow-up',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _kLabelColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasDate
                          ? _followUpStatusLabel()
                          : 'No follow-up scheduled',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: hasDate ? _kTextPrimary : _kTextMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: FilledButton.icon(
              onPressed: _schedulingFollowUp ? null : _onSetFollowUpPressed,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _schedulingFollowUp
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.edit_calendar_outlined, size: 18),
              label: Text(
                _schedulingFollowUp
                    ? 'Scheduling…'
                    : hasDate
                    ? 'Reschedule follow-up'
                    : 'Set follow-up',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (hasDate) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: TextButton.icon(
                onPressed: _schedulingFollowUp
                    ? null
                    : _onCancelFollowUpPressed,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.event_busy_outlined, size: 18),
                label: const Text(
                  'Cancel follow-up',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kCardBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: _saving ? null : _saveDetails,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 20),
          label: Text(
            _saving ? 'Saving changes…' : 'Save changes',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ),
    );
  }

  // --- Timeline column ----------------------------------------------------

  Widget _buildTimelineColumn({bool withOuterPadding = true}) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              withOuterPadding ? 16 : 18,
              withOuterPadding ? 16 : 18,
              withOuterPadding ? 16 : 18,
              12,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kCardBorder)),
            ),
            child: StreamBuilder<List<LeadEvent>>(
              stream: _eventsStream,
              builder: (context, snap) {
                final count = snap.data?.length ?? 0;
                return Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Timeline',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _kTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (count > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _kInputFill,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _kCardBorder),
                        ),
                        child: Text(
                          '$count ${count == 1 ? 'event' : 'events'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _kTextSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<LeadEvent>>(
              stream: _eventsStream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Could not load timeline.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data ?? const <LeadEvent>[];
                if (items.isEmpty) {
                  return _TimelineEmptyState();
                }
                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    withOuterPadding ? 14 : 16,
                    16,
                    withOuterPadding ? 16 : 16,
                    16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final event = items[index];
                    return _TimelineTile(
                      icon: _iconForEventAction(event.action),
                      iconColor: _colorForEventAction(event.action),
                      title: event.action.isEmpty ? 'Event' : event.action,
                      description: event.description,
                      userName: event.userName.isEmpty
                          ? 'Unknown'
                          : event.userName,
                      relativeTime: _relativeTime(event.timestamp),
                      exactTime: _formatDateTime(event.timestamp),
                      isFirst: index == 0,
                      isLast: index == items.length - 1,
                    );
                  },
                );
              },
            ),
          ),
          _buildNoteComposer(),
        ],
      ),
    );
  }

  Widget _buildNoteComposer() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kCardBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: TextField(
                controller: _timelineNoteController,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _kTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Add a note…',
                  hintStyle: const TextStyle(color: _kTextMuted),
                  filled: true,
                  fillColor: _kInputFill,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: _kCardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: _kCardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),
                onSubmitted: (_) => _postTimelineNote(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: theme.colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _postingNote ? null : _postTimelineNote,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: _postingNote
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Shared text field --------------------------------------------------

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(
        color: _kTextPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          color: _kLabelColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(color: _kTextMuted, fontSize: 13),
        filled: true,
        fillColor: _kInputFill,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 18, color: _kTextSecondary),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 38,
        ),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: prefixIcon == null ? 14 : 6,
          vertical: maxLines > 1 ? 14 : 12,
        ),
        alignLabelWithHint: maxLines > 1,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kCardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kCardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumNoteCard(String rawNote) {
    String dateStr = '';
    String text = rawNote;
    String editedStr = '';

    // Extract Date
    if (text.startsWith('[')) {
      int closeIdx = text.indexOf('] ');
      if (closeIdx != -1) {
        dateStr = text.substring(1, closeIdx);
        text = text.substring(closeIdx + 2);
      }
    }

    // Extract Edited
    int editedIdx = text.lastIndexOf('\n(Edited: ');
    if (editedIdx != -1 && text.endsWith(')')) {
      editedStr = text.substring(editedIdx + 10, text.length - 1);
      text = text.substring(0, editedIdx);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dateStr.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.access_time_filled_rounded,
                  size: 14,
                  color: Colors.blue.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 1,
              width: double.infinity,
              color: Colors.blue.shade50,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            text.trim(),
            style: const TextStyle(
              fontSize: 14.5,
              color: Color(0xFF2D3748),
              height: 1.5,
            ),
          ),
          if (editedStr.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.edit_note_rounded,
                  size: 14,
                  color: Colors.black45,
                ),
                const SizedBox(width: 4),
                Text(
                  'Edited: $editedStr',
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ==== Helper widgets ======================================================

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    required this.statusColor,
    required this.updating,
    required this.onChanged,
    required this.isTender,
  });

  final String status;
  final Color statusColor;
  final bool updating;
  final ValueChanged<String?>? onChanged;
  final bool isTender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusList = isTender ? Lead.tenderStatuses : Lead.statuses;
    final effectiveStatus = statusList.contains(status)
        ? status
        : statusList.first;

    return Container(
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: effectiveStatus,
                isDense: true,
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                icon: Icon(
                  Icons.expand_more_rounded,
                  color: statusColor,
                  size: 20,
                ),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
                items: statusList
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
          if (updating) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: statusColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InstallationChip extends StatelessWidget {
  const _InstallationChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kInputFill,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kCardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_rounded, size: 16, color: _kTextSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _kTextPrimary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = primary ? theme.colorScheme.primary : _kInputFill;
    final fg = primary ? Colors.white : _kTextPrimary;
    final border = primary ? theme.colorScheme.primary : _kCardBorder;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: primary ? Colors.white : (iconColor ?? fg),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "attach / open / remove" row for a PO or invoice copy.
class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.label,
    required this.fileName,
    required this.url,
    required this.isBusy,
    required this.isDisabled,
    required this.onAttach,
    required this.onRemove,
    required this.onOpen,
  });

  final String label;
  final String? fileName;
  final String? url;
  final bool isBusy;
  final bool isDisabled;
  final VoidCallback onAttach;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  bool get _hasFile => (url ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (isBusy) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Uploading $label…',
            style: const TextStyle(fontSize: 13, color: _kTextSecondary),
          ),
        ],
      );
    }

    if (!_hasFile) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: isDisabled ? null : onAttach,
          icon: const Icon(Icons.attach_file_rounded, size: 16),
          label: Text('Attach $label'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kTextSecondary,
            side: const BorderSide(color: _kCardBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: _kInputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kCardBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            size: 18,
            color: _kTextSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kLabelColor,
                  ),
                ),
                Text(
                  fileName?.trim().isNotEmpty == true
                      ? fileName!.trim()
                      : 'Attached file',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kTextPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open',
            visualDensity: VisualDensity.compact,
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'Replace',
            visualDensity: VisualDensity.compact,
            onPressed: isDisabled ? null : onAttach,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            onPressed: isDisabled ? null : onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kCardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060C172B),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _kInputFill,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: _kLabelColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _kTextPrimary,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    if (action != null) action!,
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Shows children side-by-side when width is comfortable (≥ 520),
/// otherwise stacks them vertically. Used inside section cards for
/// paired inputs (e.g., Phone / Email).
class _ResponsiveFieldGrid extends StatelessWidget {
  const _ResponsiveFieldGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 520 && children.length == 2) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: children[0]),
              const SizedBox(width: 12),
              Expanded(child: children[1]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        );
      },
    );
  }
}

class _InstallationRow extends StatelessWidget {
  const _InstallationRow({
    required this.label,
    required this.hasDate,
    required this.onTap,
  });

  final String label;
  final bool hasDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kInputFill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kCardBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_rounded, size: 18, color: _kTextSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Installation Date',
                      style: TextStyle(
                        color: _kLabelColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        color: hasDate ? _kTextPrimary : _kTextMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _kTextMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _kInputFill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.history_toggle_off_rounded,
                size: 30,
                color: _kTextMuted,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No activity yet',
              style: theme.textTheme.titleSmall?.copyWith(
                color: _kTextPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Status changes, notes, and scheduled\nfollow-ups will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: _kTextMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.userName,
    required this.relativeTime,
    required this.exactTime,
    required this.isFirst,
    required this.isLast,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String userName;
  final String relativeTime;
  final String exactTime;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 6,
                  color: isFirst ? Colors.transparent : _kCardBorder,
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: iconColor.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 14, color: iconColor),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : _kCardBorder,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Container(
                decoration: BoxDecoration(
                  color: _kInputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kCardBorder),
                ),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _kTextPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: exactTime,
                          child: Text(
                            relativeTime,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _kTextMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _kTextSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 13,
                          color: _kTextMuted,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            userName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _kTextMuted,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
