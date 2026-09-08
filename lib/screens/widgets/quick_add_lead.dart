import 'package:flutter/material.dart';

import '../../models/lead_model.dart';
import '../../services/auth_service.dart';
import '../../services/duplicate_lead_service.dart';
import '../../services/lead_service.dart';
import '../../services/product_service.dart';
import '../../services/source_service.dart';
import 'duplicate_lead_warning_dialog.dart';
import 'lead_date_field.dart';
import 'lead_product_lines_editor.dart';
import '../../utils/flexible_date_parse.dart';

/// Bottom sheet to create a lead. Admins pick assignee; employees self-assign via [currentUserId].
class QuickAddLeadSheet extends StatefulWidget {
  const QuickAddLeadSheet({
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

  /// `'admin'` or `'employee'`.
  final String currentUserRole;
  final String currentUserId;

  @override
  State<QuickAddLeadSheet> createState() => _QuickAddLeadSheetState();
}

class _QuickAddLeadSheetState extends State<QuickAddLeadSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _companyController = TextEditingController();
  final _locationController = TextEditingController();
  final _websiteController = TextEditingController();
  final List<LeadProductLineFields> _productLines = [LeadProductLineFields()];
  final _remarkController = TextEditingController();
  final _duplicateService = DuplicateLeadService();
  DateTime _leadDate = todayDateOnly();

  bool _isSaving = false;
  bool _isCheckingDuplicates = false;
  String? _selectedEmployeeUid;
  String? _selectedSource;

  bool get _isAdmin => widget.currentUserRole == 'admin';

  bool get _isBusy => _isSaving || _isCheckingDuplicates;

  String? get _busyLabel {
    if (_isCheckingDuplicates) return 'Checking for duplicates…';
    if (_isSaving) return 'Saving...';
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _companyController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    for (final line in _productLines) {
      line.dispose();
    }
    _remarkController.dispose();
    super.dispose();
  }



  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    if (!value.contains('@')) {
      return 'Please enter a valid email';
    }
    return null;
  }

  /// Warns if this party already exists in the CRM. Returns true when the save
  /// should continue — including when the check itself could not run, so a
  /// backend hiccup never stops someone from entering a lead.
  Future<bool> _confirmNotDuplicate() async {
    setState(() => _isCheckingDuplicates = true);
    DuplicateLeadResult result;
    try {
      result = await _duplicateService.check(
        phone: _phoneController.text,
        email: _emailController.text,
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

  Future<void> _submitLead({String? assigneeUid}) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final uid = _isAdmin ? assigneeUid : widget.currentUserId;
    if (uid == null || uid.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please choose who this lead is assigned to.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!await _confirmNotDuplicate()) return;
    if (!mounted) return;

    setState(() => _isSaving = true);
    try {
      await widget.leadService.addLead(
        Lead(
          id: '',
          name: _nameController.text,
          phone: _phoneController.text,
          email: _emailController.text,
          company: _companyController.text,
          status: Lead.statuses.first,
          assignedTo: uid,
          leadDate: _leadDate,
          createdAt: DateTime.now(),
          remark: _remarkController.text,
          location: _locationController.text,
          website: _websiteController.text,
          productLines: _productLines.map((e) => e.toLine()).toList(),
          source: _selectedSource ?? '',
          totalAmount: 0,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Lead added successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not create lead right now.'),
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
              'Quick Add Lead',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'This lead will be assigned to you.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF657084),
              ),
            ),
            const SizedBox(height: 18),
            ..._commonFields(theme),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text('Initial status: ${Lead.statuses.first}'),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isBusy
                  ? null
                  : () => _submitLead(assigneeUid: widget.currentUserId),
              icon: _isBusy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_busyLabel ?? 'Create Lead'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
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
            final selfLabel = (selfName != null && selfName.isNotEmpty)
                ? 'Me ($selfName)'
                : 'Assign to me';
            final selfOption = EmployeeAssignee(uid: adminUid, label: selfLabel);

            return StreamBuilder<List<EmployeeAssignee>>(
              stream: widget.leadService.getAssignableEmployeesStream(),
              builder: (context, snapshot) {
                final employees = snapshot.data ?? const <EmployeeAssignee>[];
                final others = employees
                    .where((e) => e.uid != adminUid)
                    .toList(growable: false);
                final assignOptions = <EmployeeAssignee>[
                  selfOption,
                  ...others,
                ];

                final selectedUid =
                    assignOptions.any((item) => item.uid == _selectedEmployeeUid)
                    ? _selectedEmployeeUid
                    : (others.isNotEmpty ? others.first.uid : selfOption.uid);

                return SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Quick Add Lead',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Create and assign a lead in seconds.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF657084),
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
                              .map(
                                (assignee) => DropdownMenuItem<String>(
                                  value: assignee.uid,
                                  child: Text(assignee.label),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _isSaving
                              ? null
                              : (value) => setState(
                                  () => _selectedEmployeeUid = value,
                                ),
                          validator: (value) => value == null
                              ? 'Please select an assignee'
                              : null,
                        ),
                        if (others.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'No other team members yet. You can assign to yourself or add users with role "employee".',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF657084),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(
                            label: Text(
                              'Initial status: ${Lead.statuses.first}',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isBusy
                              ? null
                              : () => _submitLead(assigneeUid: selectedUid),
                          icon: _isBusy
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(_busyLabel ?? 'Create Lead'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) ...[
                          const SizedBox(height: 10),
                          const Center(child: CircularProgressIndicator()),
                        ],
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
      StreamBuilder<List<String>>(
        stream: SourceService.instance.watchSources(),
        builder: (context, snapshot) {
          final sources = snapshot.data ?? kDefaultLeadSources;
          if (_selectedSource == null && sources.isNotEmpty) {
            _selectedSource = sources.first;
          }
          return DropdownButtonFormField<String>(
            value: _selectedSource,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Source',
              border: OutlineInputBorder(),
            ),
            items: sources.map((s) => DropdownMenuItem<String>(
              value: s,
              child: Text(s),
            )).toList(),
            onChanged: _isSaving
                ? null
                : (value) => setState(() => _selectedSource = value),
          );
        },
      ),
      const SizedBox(height: 12),
      LeadDateField(
        value: _leadDate,
        enabled: !_isSaving,
        onChanged: (d) => setState(() => _leadDate = d),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _companyController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Company Name',
          border: OutlineInputBorder(),
        ),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _nameController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Customer Name',
          border: OutlineInputBorder(),
        ),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Contact No.',
          border: OutlineInputBorder(),
        ),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Email ID',
          border: OutlineInputBorder(),
        ),
        validator: _emailValidator,
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _locationController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Location',
          border: OutlineInputBorder(),
        ),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _websiteController,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Website',
          border: OutlineInputBorder(),
        ),
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      LeadProductLinesEditor(
        productService: widget.productService,
        lines: _productLines,
        onChanged: () => setState(() {}),
        productNameLabel: 'Requirement',
        requireFirstLine: false,
        enabled: !_isSaving,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _remarkController,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Remark',
          border: OutlineInputBorder(),
        ),
        enabled: !_isSaving,
      ),
    ];
  }
}
