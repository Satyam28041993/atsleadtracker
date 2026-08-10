import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/lead_model.dart';
import '../../services/auth_service.dart';
import '../../services/duplicate_lead_service.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import 'duplicate_lead_warning_dialog.dart';
import 'lead_date_field.dart';
import 'lead_product_lines_editor.dart';
import '../../utils/flexible_date_parse.dart';

class QuickAddTenderSheet extends StatefulWidget {
  const QuickAddTenderSheet({
    super.key,
    required this.leadService,
    required this.authService,
    required this.currentUserRole,
    required this.currentUserId,
    required this.productService,
  });

  final LeadService leadService;
  final AuthService authService;
  final ProductService productService;
  final String currentUserRole;
  final String currentUserId;

  @override
  State<QuickAddTenderSheet> createState() => _QuickAddTenderSheetState();
}

class _QuickAddTenderSheetState extends State<QuickAddTenderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _bidNoController = TextEditingController();
  final _companyController = TextEditingController();
  final List<LeadProductLineFields> _productLines = [LeadProductLineFields()];
  final _qtyController = TextEditingController();
  DateTime _leadDate = todayDateOnly();
  DateTime? _dueDate;
  final _priceController = TextEditingController();
  final _technicalController = TextEditingController();
  final _commercialController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactDesignationController = TextEditingController();

  final _duplicateService = DuplicateLeadService();

  bool _isSaving = false;
  bool _isCheckingDuplicates = false;
  String? _selectedEmployeeUid;

  bool get _isAdmin => widget.currentUserRole == 'admin';

  bool get _isBusy => _isSaving || _isCheckingDuplicates;

  String? get _busyLabel {
    if (_isCheckingDuplicates) return 'Checking for duplicates…';
    if (_isSaving) return 'Saving...';
    return null;
  }

  /// Warns if this party is already in the CRM. Never blocks the save — a
  /// failed check simply lets the tender through.
  Future<bool> _confirmNotDuplicate() async {
    setState(() => _isCheckingDuplicates = true);
    DuplicateLeadResult result;
    try {
      result = await _duplicateService.check(
        phone: _contactPhoneController.text,
        company: _companyController.text,
      );
    } catch (_) {
      return true;
    } finally {
      if (mounted) setState(() => _isCheckingDuplicates = false);
    }

    if (!result.hasMatches) return true;
    if (!mounted) return true;
    return DuplicateLeadWarningDialog.show(context, result: result);
  }

  @override
  void dispose() {
    _bidNoController.dispose();
    _companyController.dispose();
    for (final line in _productLines) {
      line.dispose();
    }
    _qtyController.dispose();
    _priceController.dispose();
    _technicalController.dispose();
    _commercialController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _contactDesignationController.dispose();
    super.dispose();
  }



  Future<void> _submitTender({String? assigneeUid}) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final uid = _isAdmin ? assigneeUid : widget.currentUserId;
    if (uid == null || uid.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please choose who this tender is assigned to.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!await _confirmNotDuplicate()) return;
    if (!mounted) return;

    setState(() => _isSaving = true);
    try {
      final contactName = _contactNameController.text.trim();
      final contactPhone = _contactPhoneController.text.trim();
      await widget.leadService.addLead(
        Lead(
          id: '',
          name: contactName,
          phone: contactPhone,
          email: '',
          company: _companyController.text.trim(),
          status: Lead.tenderStatuses.first,
          assignedTo: uid,
          leadDate: _leadDate,
          createdAt: DateTime.now(),
          remark: '',
          location: '',
          website: '',
          productLines: _productLines.map((e) => e.toLine()).toList(),
          source: 'Tender', // Keep source as Tender internally
          totalAmount: double.tryParse(_priceController.text) ?? 0,
          isTender: true,
          bidNo: _bidNoController.text.trim(),
          quantity: int.tryParse(_qtyController.text) ?? 1,
          dueDate: _dueDate,
          technicalStatus: _technicalController.text.trim(),
          commercialStatus: _commercialController.text.trim(),
          designation: _contactDesignationController.text.trim(),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Tender added successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not create tender right now.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
        child: _isAdmin
            ? _buildAdminForm(theme)
            : _buildEmployeeForm(theme),
      ),
    );
  }

  Widget _buildEmployeeForm(ThemeData theme) {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quick Add Tender',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            ..._commonFields(theme),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isBusy
                  ? null
                  : () => _submitTender(assigneeUid: widget.currentUserId),
              icon: _isBusy
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(_busyLabel ?? 'Create Tender'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminForm(ThemeData theme) {
    final adminUid = widget.currentUserId;

    return Builder(
      builder: (context) {
        return StreamBuilder<String?>(
          stream: widget.authService.watchUserName(adminUid),
          builder: (context, selfNameSnap) {
            final selfName = selfNameSnap.data;
            final selfLabel = (selfName != null && selfName.isNotEmpty) ? 'Me ($selfName)' : 'Assign to me';
            final selfOption = EmployeeAssignee(uid: adminUid, label: selfLabel);

            return StreamBuilder<List<EmployeeAssignee>>(
              stream: widget.leadService.getAssignableEmployeesStream(),
              builder: (context, snapshot) {
                final employees = snapshot.data ?? const <EmployeeAssignee>[];
                final others = employees.where((e) => e.uid != adminUid).toList(growable: false);
                final assignOptions = <EmployeeAssignee>[selfOption, ...others];

                final selectedUid = assignOptions.any((item) => item.uid == _selectedEmployeeUid)
                    ? _selectedEmployeeUid
                    : (others.isNotEmpty ? others.first.uid : selfOption.uid);

                return SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Quick Add Tender',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),
                        ..._commonFields(theme),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedUid,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Assign To',
                            border: OutlineInputBorder(),
                          ),
                          items: assignOptions
                              .map((assignee) => DropdownMenuItem<String>(
                                    value: assignee.uid,
                                    child: Text(assignee.label),
                                  ))
                              .toList(growable: false),
                          onChanged: _isSaving ? null : (value) => setState(() => _selectedEmployeeUid = value),
                          validator: (value) => value == null ? 'Please select an assignee' : null,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isBusy ? null : () => _submitTender(assigneeUid: selectedUid),
                          icon: _isBusy
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check_rounded),
                          label: Text(_busyLabel ?? 'Create Tender'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  List<Widget> _commonFields(ThemeData theme) {
    return [
      TextFormField(
        controller: _bidNoController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'BID NO', border: OutlineInputBorder()),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _companyController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'CUSTOMER NAME', border: OutlineInputBorder()),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _contactNameController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'CONTACT PERSON NAME', border: OutlineInputBorder()),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _contactPhoneController,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'CONTACT PERSON NUMBER', border: OutlineInputBorder()),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _contactDesignationController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'CONTACT PERSON DESIGNATION', border: OutlineInputBorder()),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      LeadProductLinesEditor(
        productService: widget.productService,
        lines: _productLines,
        onChanged: () => setState(() {}),
        productNameLabel: 'PRODUCT NAME',
        requireFirstLine: false,
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      LeadDateField(
        value: _leadDate,
        enabled: !_isSaving,
        onChanged: (d) => setState(() => _leadDate = d),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _qtyController,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'QTY', border: OutlineInputBorder()),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      InkWell(
        onTap: _isSaving
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
          decoration: const InputDecoration(
            labelText: 'DUE DATE',
            border: OutlineInputBorder(),
          ),
          child: Text(
            _dueDate != null ? DateFormat('dd.MM.yyyy').format(_dueDate!) : 'Select Date',
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _priceController,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'PRICE', border: OutlineInputBorder()),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _technicalController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'TECHNICAL', hintText: 'e.g. Qualified', border: OutlineInputBorder()),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _commercialController,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'COMMERCIAL', hintText: 'e.g. L 1', border: OutlineInputBorder()),
        enabled: !_isSaving,
      ),
    ];
  }
}
