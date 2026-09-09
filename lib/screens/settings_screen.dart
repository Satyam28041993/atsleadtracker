import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/export_io.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/bulk_upload_service.dart';
import '../services/message_template_service.dart';
import '../services/source_service.dart';
import 'widgets/settings/backup_card.dart';
import 'widgets/settings/cloud_backup_card.dart';
import 'widgets/settings/settings_card.dart';
import 'widgets/settings/template_editor.dart';
import 'widgets/settings/upload_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _templateController;
  late final TextEditingController _newSourceController;
  final MessageTemplateService _templateService =
      MessageTemplateService.instance;
  final BulkUploadService _bulkUploadService = BulkUploadService();
  final BackupService _backupService = BackupService();
  final AuthService _authService = AuthService();
  StreamSubscription<String>? _templateSubscription;
  bool _loading = true;
  bool _loadingUserContext = true;
  bool _saving = false;
  bool _isEditing = false;
  bool _downloadingTemplate = false;
  bool _uploadingLeads = false;
  bool _purgingLeads = false;
  String _uploaderRole = 'employee';
  String _uploaderName = 'System';
  BulkUploadProgress? _progress;
  bool _isTenderUploadMode = false;
  BackupKind? _backingUpKind;
  static const String _sampleName = 'Aarav';
  static const String _sampleRequirement = 'CNC Machine';

  @override
  void initState() {
    super.initState();
    _templateController = TextEditingController();
    _newSourceController = TextEditingController();
    _templateSubscription = _templateService.watchTemplate().listen((template) {
      if (!mounted || _saving) return;
      if (_isEditing && _templateController.text.trim().isNotEmpty) return;
      _templateController.value = TextEditingValue(
        text: template,
        selection: TextSelection.collapsed(offset: template.length),
      );
    });
    _loadTemplate();
    _loadUploaderContext();
  }

  @override
  void dispose() {
    _templateSubscription?.cancel();
    _templateController.dispose();
    _newSourceController.dispose();
    super.dispose();
  }

  Future<void> _loadUploaderContext() async {
    try {
      final role = await _bulkUploadService.getCurrentUserRole();
      final name = await _bulkUploadService.getCurrentUserName();
      if (!mounted) return;
      setState(() {
        _uploaderRole = role;
        _uploaderName = name;
        _loadingUserContext = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingUserContext = false);
      _showToast('Could not load user role for bulk upload.');
    }
  }

  Future<void> _loadTemplate() async {
    try {
      final template = await _templateService.getTemplate();
      if (!mounted) return;
      _templateController.text = template;
    } catch (_) {
      if (!mounted) return;
      _showToast('Could not load WhatsApp template.');
      _templateController.text = '';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveTemplate() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _templateService.saveTemplate(_templateController.text);
      _isEditing = false;
      if (mounted) _showToast('Template saved successfully.');
    } catch (_) {
      if (mounted) _showToast('Could not save template.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _downloadTemplate() async {
    if (_downloadingTemplate || _uploadingLeads) return;
    setState(() => _downloadingTemplate = true);
    try {
      final isAdmin = _uploaderRole == 'admin';
      final bytes = _isTenderUploadMode
          ? await _bulkUploadService.buildTenderTemplateBytes(isAdmin: isAdmin)
          : await _bulkUploadService.buildTemplateBytes(isAdmin: isAdmin);
      final suffix = _isTenderUploadMode ? '_tender' : '';
      final fileName = isAdmin
          ? 'lead_upload_template${suffix}_admin.xlsx'
          : 'lead_upload_template${suffix}_employee.xlsx';
      await FilePicker.saveFile(
        dialogTitle: 'Save Lead Upload Template',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['xlsx'],
        bytes: bytes,
      );
      if (!mounted) return;
      _showToast(
        kIsWeb
            ? 'Template download started.'
            : 'Template generated successfully.',
      );
    } catch (_) {
      if (!mounted) return;
      _showToast('Could not generate template.');
    } finally {
      if (mounted) {
        setState(() => _downloadingTemplate = false);
      }
    }
  }

  Future<void> _selectAndUploadLeads() async {
    if (_uploadingLeads || _downloadingTemplate) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showToast('You must be signed in to upload leads.');
      return;
    }

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['xlsx', 'xls'],
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    if (!mounted) return;
    final file = picked.files.first;
    final confirm = await _confirmUpload(file.name);
    if (!confirm) return;
    await _uploadLeads(file.bytes, user.uid);
  }

  Future<void> _uploadLeads(Uint8List? bytes, String uploaderUid) async {
    if (bytes == null || bytes.isEmpty) {
      _showToast('Could not read selected file.');
      return;
    }

    setState(() {
      _uploadingLeads = true;
      _progress = const BulkUploadProgress(
        processedRows: 0,
        totalRows: 0,
        uploadedRows: 0,
        failedRows: 0,
      );
    });

    try {
      final summary = _isTenderUploadMode
          ? await _bulkUploadService.uploadTenderLeadsFromExcelBytes(
              Uint8List.fromList(bytes),
              uploaderUid: uploaderUid,
              uploaderRole: _uploaderRole,
              uploaderName: _uploaderName,
              onProgress: (progress) {
                if (!mounted) return;
                setState(() => _progress = progress);
              },
            )
          : await _bulkUploadService.uploadLeadsFromExcelBytes(
              Uint8List.fromList(bytes),
              uploaderUid: uploaderUid,
              uploaderRole: _uploaderRole,
              uploaderName: _uploaderName,
              onProgress: (progress) {
                if (!mounted) return;
                setState(() => _progress = progress);
              },
            );
      if (!mounted) return;
      _showToast(
        'Successfully uploaded ${summary.uploadedRows} leads. ${summary.failedRows} rows failed due to missing/invalid info.',
      );
      if (summary.failureMessages.isNotEmpty) {
        final details = summary.failureMessages.take(5).join('\n');
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Upload Summary'),
            content: Text(
              '$details${summary.failureMessages.length > 5 ? '\n…and ${summary.failureMessages.length - 5} more.' : ''}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showToast('Bulk upload failed. Please check the file format.');
    } finally {
      if (mounted) {
        setState(() => _uploadingLeads = false);
      }
    }
  }

  Future<bool> _confirmUpload(String fileName) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Upload'),
          content: Text(
            'Upload "$fileName" now? Existing leads will remain unchanged, and valid rows will be added.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );
    return accepted ?? false;
  }

  void _insertVariable(String token) {
    final selection = _templateController.selection;
    final text = _templateController.text;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(0, text.length);
    final next = text.replaceRange(safeStart, safeEnd, token);
    _templateController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: safeStart + token.length),
    );
    setState(() => _isEditing = true);
  }

  String _buildPreviewMessage() {
    final text = _templateController.text.trim();
    if (text.isEmpty) {
      return 'Your message preview appears here as you type.';
    }
    return text
        .replaceAll('{name}', _sampleName)
        .replaceAll('{requirement}', _sampleRequirement);
  }

  void _showToast(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  Widget _buildUploadSection(String uploaderDescription) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload Type',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  Text(
                    _isTenderUploadMode ? 'Tender Leads' : 'Normal Leads',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _isTenderUploadMode,
                activeColor: Colors.orange.shade700,
                onChanged: _uploadingLeads || _downloadingTemplate
                    ? null
                    : (val) => setState(() => _isTenderUploadMode = val),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        UploadCard(
          description: uploaderDescription,
          loadingUserContext: _loadingUserContext,
          downloadingTemplate: _downloadingTemplate,
          uploadingLeads: _uploadingLeads,
          onDownload: _downloadTemplate,
          onSelectAndUpload: _selectAndUploadLeads,
          progress: _progress,
          onPurge: _uploaderRole == 'admin' ? _purgeAllLeads : null,
          purgingLeads: _purgingLeads,
          isTenderMode: _isTenderUploadMode,
        ),
      ],
    );
  }

  String _backupDialogTitle(BackupKind kind) {
    switch (kind) {
      case BackupKind.leads:
        return 'Save Leads Backup';
      case BackupKind.tenders:
        return 'Save Tenders Backup';
      case BackupKind.quotations:
        return 'Save Quotations Backup';
      case BackupKind.products:
        return 'Save Products Backup';
    }
  }

  Future<void> _runBackup(BackupKind kind) async {
    if (_backingUpKind != null) return;

    if (kind == BackupKind.quotations) {
      final option = await askQuotationBackupOption(context);
      if (!mounted || option == null) return;
      setState(() => _backingUpKind = kind);
      try {
        if (option == QuotationBackupOption.zip) {
          _showToast('Generating quotation PDFs…');
        } else if (option == QuotationBackupOption.both) {
          _showToast('Preparing CSV and PDF ZIP…');
        }
        final files = await _backupService.buildQuotationBackups(option);
        var savedCount = 0;
        for (final file in files) {
          final savedPath = await saveBackupToDevice(
            file,
            dialogTitle: file.fileName.endsWith('.zip')
                ? 'Save Quotation PDFs (ZIP)'
                : 'Save Quotations Backup (CSV)',
          );
          if (wasSaved(savedPath)) savedCount++;
        }
        if (!mounted) return;
        if (savedCount > 0) {
          _showToast(
            savedCount == files.length
                ? 'Quotation backup saved ($savedCount file${savedCount == 1 ? '' : 's'}).'
                : 'Saved $savedCount of ${files.length} files.',
          );
        }
      } catch (e) {
        if (!mounted) return;
        _showToast(
          e is StateError
              ? e.message
              : 'Quotation backup failed. Please try again.',
        );
      } finally {
        if (mounted) {
          setState(() => _backingUpKind = null);
        }
      }
      return;
    }

    setState(() => _backingUpKind = kind);
    try {
      final file = await _backupService.buildBackup(kind);
      final savedPath = await saveBackupToDevice(
        file,
        dialogTitle: _backupDialogTitle(kind),
      );
      if (!mounted) return;
      if (wasSaved(savedPath)) {
        _showToast('Backup saved: ${file.fileName}');
      }
    } catch (_) {
      if (!mounted) return;
      _showToast('Backup failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _backingUpKind = null);
      }
    }
  }

  Widget _buildBackupCard(double sideSpacing) {
    final theme = Theme.of(context);
    return SettingsCard(
      title: 'Data Backup',
      leading: const Icon(
        Icons.backup_rounded,
        color: Color(0xFF059669),
      ),
      padding: EdgeInsets.all(sideSpacing),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
          initiallyExpanded: false,
          title: Text(
            'Download backup to PC',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
            ),
          ),
          subtitle: Text(
            'Leads, Tenders, Quotations, Products',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF94A3B8),
            ),
          ),
          children: [
            BackupCard(
              backingUpKind: _backingUpKind,
              onBackup: _runBackup,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudBackupCard(double sideSpacing) {
    return SettingsCard(
      title: 'Automatic Cloud Backup',
      leading: const Icon(
        Icons.cloud_done_outlined,
        color: Color(0xFF0284C7),
      ),
      padding: EdgeInsets.all(sideSpacing),
      child: const CloudBackupCard(),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    IconData? icon,
    double topSpacing = 8,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF2563EB)),
            ),
          if (icon != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Configure messaging, imports, team access, and backups in one place.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminTeamSection(double spacing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          title: 'Team Administration',
          subtitle: 'Lead sources and employee accounts',
          icon: Icons.groups_outlined,
          topSpacing: 20,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 720;
            if (sideBySide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildSourcesConfigCard(spacing)),
                  const SizedBox(width: 18),
                  Expanded(child: _buildEmployeeConfigCard(spacing)),
                ],
              );
            }
            return Column(
              children: [
                _buildSourcesConfigCard(spacing),
                const SizedBox(height: 18),
                _buildEmployeeConfigCard(spacing),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAdminBackupSection(double spacing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          title: 'Backup & Safety',
          subtitle: 'Download local copies or rely on automatic cloud backups',
          icon: Icons.shield_outlined,
          topSpacing: 20,
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 720;
            if (sideBySide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildBackupCard(spacing)),
                  const SizedBox(width: 18),
                  Expanded(child: _buildCloudBackupCard(spacing)),
                ],
              );
            }
            return Column(
              children: [
                _buildBackupCard(spacing),
                const SizedBox(height: 18),
                _buildCloudBackupCard(spacing),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSettingsBody({
    required bool isDesktop,
    required double spacing,
    required String uploaderDescription,
  }) {
    final whatsappCard = SettingsCard(
      title: 'WhatsApp Integration',
      subtitle:
          'Create a polished outreach message with reusable variables and instant preview.',
      padding: EdgeInsets.all(spacing),
      child: TemplateEditor(
        controller: _templateController,
        loading: _loading,
        saving: _saving,
        onTemplateChanged: (_) {
          if (!_isEditing) {
            setState(() => _isEditing = true);
          } else {
            setState(() {});
          }
        },
        onInsertVariable: _insertVariable,
        onSave: _saveTemplate,
        previewMessage: _buildPreviewMessage(),
      ),
    );

    final dataManagementCard = SettingsCard(
      title: 'Data Management',
      subtitle: 'Download templates and bulk import leads or tenders.',
      leading: const Icon(
        Icons.storage_rounded,
        color: Color(0xFF1D4ED8),
      ),
      padding: EdgeInsets.all(spacing),
      child: _buildUploadSection(uploaderDescription),
    );

    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            title: 'Communication',
            subtitle: 'WhatsApp message templates for your team',
            icon: Icons.chat_outlined,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: whatsappCard),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: dataManagementCard),
            ],
          ),
          if (_uploaderRole == 'admin') ...[
            _buildAdminTeamSection(spacing),
            _buildAdminBackupSection(spacing),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          title: 'Communication',
          subtitle: 'WhatsApp message templates for your team',
          icon: Icons.chat_outlined,
        ),
        whatsappCard,
        const SizedBox(height: 18),
        _buildSectionHeader(
          title: 'Data Operations',
          subtitle: 'Templates, uploads, and imports',
          icon: Icons.cloud_upload_outlined,
          topSpacing: 4,
        ),
        dataManagementCard,
        if (_uploaderRole == 'admin') ...[
          _buildAdminTeamSection(spacing),
          _buildAdminBackupSection(spacing),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploaderDescription = _uploaderRole == 'admin'
        ? 'Admin template includes Assigned To with employee dropdown.'
        : 'Employee template locks every uploaded lead to your account.';

    return ColoredBox(
      color: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 1100;
                final spacing = isDesktop ? 24.0 : (constraints.maxWidth >= 768 ? 20.0 : 16.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPageHeader(),
                    const SizedBox(height: 20),
                    _buildSettingsBody(
                      isDesktop: isDesktop,
                      spacing: spacing,
                      uploaderDescription: uploaderDescription,
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildSourcesConfigCard(double sideSpacing) {
    final theme = Theme.of(context);
    return SettingsCard(
      title: 'Lead Sources Configuration',
      leading: const Icon(
        Icons.source_rounded,
        color: Color(0xFF8B5CF6),
      ),
      padding: EdgeInsets.all(sideSpacing),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
          initiallyExpanded: false,
          title: Text(
            'Manage lead sources',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
            ),
          ),
          subtitle: Text(
            'Add or remove lead channels',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF94A3B8),
            ),
          ),
          children: [
            StreamBuilder<List<String>>(
              stream: SourceService.instance.watchSources(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final sources =
                    snapshot.data ?? kDefaultLeadSources;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...sources.map((source) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.label_outline_rounded,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                source,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              onPressed: sources.length <= 1
                                  ? null
                                  : () async {
                                      final updated =
                                          List<String>.from(sources)
                                            ..remove(source);
                                      await SourceService.instance.saveSources(
                                        updated,
                                      );
                                      _showToast(
                                        'Source deleted successfully.',
                                      );
                                    },
                              tooltip: sources.length <= 1
                                  ? 'Must have at least one source'
                                  : 'Delete source',
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newSourceController,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1E293B),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Add new lead source (e.g. Website)',
                              hintStyle: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 13,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _addNewSource(sources),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: () => _addNewSource(sources),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          child: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addNewSource(List<String> currentSources) async {
    final text = _newSourceController.text.trim();
    if (text.isEmpty) return;
    if (currentSources.any((s) => s.toLowerCase() == text.toLowerCase())) {
      _showToast('This source already exists.');
      return;
    }
    final updated = List<String>.from(currentSources)..add(text);
    await SourceService.instance.saveSources(updated);
    _newSourceController.clear();
    _showToast('Source added successfully.');
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Incorrect password. Use the same password as login.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a moment and try again.';
      case 'invalid-email':
        return e.message ?? 'This account cannot be verified with a password.';
      default:
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'Password verification failed.';
    }
  }

  Future<String?> _promptPurgePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim() ?? '';
    if (email.isEmpty) {
      _showToast('Cannot purge: your account has no email login.');
      return null;
    }

    final passwordController = TextEditingController();
    var obscure = true;

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Confirm your password'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Enter your login password to permanently delete all leads.',
                    ),
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        email,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: obscure,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Login password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: obscure ? 'Show password' : 'Hide password',
                          onPressed: () =>
                              setDialogState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onSubmitted: (_) {
                        final pwd = passwordController.text;
                        if (pwd.isNotEmpty) {
                          Navigator.of(dialogContext).pop(pwd);
                        }
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    onPressed: () {
                      final pwd = passwordController.text;
                      if (pwd.isEmpty) return;
                      Navigator.of(dialogContext).pop(pwd);
                    },
                    child: const Text('Verify & continue'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      passwordController.dispose();
    }
  }

  Future<void> _purgeAllLeads() async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 10),
              const Text('Purge All Leads?'),
            ],
          ),
          content: const Text(
            'This will permanently delete all leads, follow-ups, and timeline events from the database. This action is irreversible. You will need to enter your login password on the next step.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    final password = await _promptPurgePassword();
    if (password == null || password.isEmpty || !mounted) return;

    try {
      await _authService.reauthenticateWithPassword(password: password);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showToast(_authErrorMessage(e));
      return;
    } catch (_) {
      if (!mounted) return;
      _showToast('Could not verify password. Try again.');
      return;
    }

    if (!mounted) return;
    setState(() => _purgingLeads = true);
    try {
      final query = await FirebaseFirestore.instance.collection('leads').get();
      if (query.docs.isEmpty) {
        _showToast('No leads found to delete.');
        setState(() => _purgingLeads = false);
        return;
      }

      var batch = FirebaseFirestore.instance.batch();
      var count = 0;
      for (final doc in query.docs) {
        final events = await doc.reference.collection('events').get();
        for (final ev in events.docs) {
          batch.delete(ev.reference);
        }

        final sfu = await doc.reference.collection('smart_follow_ups').get();
        for (final fu in sfu.docs) {
          batch.delete(fu.reference);
        }

        batch.delete(doc.reference);
        count++;
        if (count >= 300) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          count = 0;
        }
      }
      if (count > 0) {
        await batch.commit();
      }

      _showToast('Successfully purged all leads data.');
    } catch (e) {
      _showToast('Failed to delete some leads due to security rules.');
    } finally {
      if (mounted) {
        setState(() => _purgingLeads = false);
      }
    }
  }

  Widget _buildEmployeeConfigCard(double sideSpacing) {
    final theme = Theme.of(context);
    return SettingsCard(
      title: 'Employee Accounts Management',
      leading: const Icon(
        Icons.people_alt_rounded,
        color: Color(0xFF10B981),
      ),
      padding: EdgeInsets.all(sideSpacing),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
          initiallyExpanded: false,
          title: Text(
            'Manage employee accounts',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
            ),
          ),
          subtitle: Text(
            'Add, edit, or remove employees',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF94A3B8),
            ),
          ),
          children: [
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'employee')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Column(
                    children: [
                      Text(
                        'No employee accounts yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...docs.map((doc) {
                      final data = doc.data();
                      final name = (data['name'] as String? ?? '').trim();
                      final email = (data['email'] as String? ?? '').trim();
                      final mobile = (data['mobile'] as String? ?? '').trim();
                      final firstLetter =
                          name.isNotEmpty ? name[0].toUpperCase() : 'E';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              radius: 18,
                              child: Text(
                                firstLetter,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name.isNotEmpty
                                        ? name
                                        : 'Unnamed Employee',
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF1E293B),
                                        ),
                                  ),
                                  if (email.isNotEmpty)
                                    Text(
                                      email,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: const Color(0xFF64748B),
                                          ),
                                    ),
                                  if (mobile.isNotEmpty)
                                    Text(
                                      '📱 $mobile',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: const Color(0xFF64748B),
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: Color(0xFF64748B),
                                    size: 20,
                                  ),
                                  onPressed: () => _openEditEmployeeDialog(
                                    doc.id,
                                    name,
                                    email,
                                    mobile,
                                  ),
                                  tooltip: 'Edit details',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _removeEmployee(doc.id, name),
                                  tooltip: 'Delete account',
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
            FilledButton.icon(
              onPressed: _openAddEmployeeDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Employee Account'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeEmployee(String uid, String name) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 10),
              const Text('Remove Employee?'),
            ],
          ),
          content: Text(
            'This will remove "$name" from the portal. Note: Their email remains registered. To reuse this email or completely delete them, you must also remove them from the Firebase Console. Are you sure?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      _showToast("Employee '$name' removed successfully.");
    } catch (e) {
      _showToast('Could not remove employee: $e');
    }
  }

  Future<void> _openAddEmployeeDialog() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _AddEmployeeDialog(),
    );
    if (added == true && mounted) {
      _showToast('Employee account created successfully.');
    }
  }

  Future<void> _openEditEmployeeDialog(String uid, String currentName, String email, String currentMobile) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _EditEmployeeDialog(
        currentName: currentName,
        email: email,
        currentMobile: currentMobile,
      ),
    );
    if (result != null && mounted) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'name': result['name']?.trim() ?? '',
          'mobile': result['mobile']?.trim() ?? '',
        });
        _showToast('Employee details updated successfully.');
      } catch (e) {
        _showToast('Could not update employee details: $e');
      }
    }
  }
}

class _AddEmployeeDialog extends StatefulWidget {
  const _AddEmployeeDialog();

  @override
  State<_AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<_AddEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final nameStr = _nameController.text.trim();
      final emailStr = _emailController.text.trim();
      final pwdStr = _passwordController.text;

      // 1. Initialize temporary secondary app
      final appName = 'EmpGen_${DateTime.now().millisecondsSinceEpoch}';
      final secondaryApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      String newUid;
      try {
        // 2. Create in Firebase Auth
        final cred = await secondaryAuth.createUserWithEmailAndPassword(
          email: emailStr,
          password: pwdStr,
        );
        newUid = cred.user!.uid;
      } on FirebaseAuthException catch (authE) {
        if (authE.code == 'email-already-in-use') {
          try {
            // Attempt to restore existing auth account if password matches
            final signCred = await secondaryAuth.signInWithEmailAndPassword(
              email: emailStr,
              password: pwdStr,
            );
            newUid = signCred.user!.uid;
          } catch (_) {
            await secondaryApp.delete();
            setState(() {
              _loading = false;
              _error = 'Email already exists. To restore this account, please use its original password.';
            });
            return;
          }
        } else {
          await secondaryApp.delete();
          setState(() {
            _loading = false;
            _error = authE.message ?? 'Authentication failed.';
          });
          return;
        }
      }

      // 3. Save profile document in Firestore
      await FirebaseFirestore.instance.collection('users').doc(newUid).set({
        'name': nameStr,
        'email': emailStr,
        'role': 'employee',
        'isOnline': false,
        'lastActive': FieldValue.serverTimestamp(),
      });

      // 4. Clean up secondary app
      await secondaryApp.delete();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not create account: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Employee Account'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    hintText: 'e.g. Satyam Singh',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Please enter employee name' : null,
                  enabled: !_loading,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Work Email *',
                    hintText: 'e.g. employee@at-epl.com',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Please enter email';
                    if (!v.contains('@')) return 'Please enter a valid email';
                    return null;
                  },
                  enabled: !_loading,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password *',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please enter password';
                    if (v.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                  enabled: !_loading,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Create Account'),
        ),
      ],
    );
  }
}

class _EditEmployeeDialog extends StatefulWidget {
  const _EditEmployeeDialog({
    required this.currentName,
    required this.email,
    required this.currentMobile,
  });
  final String currentName;
  final String email;
  final String currentMobile;

  @override
  State<_EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

class _EditEmployeeDialogState extends State<_EditEmployeeDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _mobileController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _mobileController = TextEditingController(text: widget.currentMobile);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Employee'),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.email, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop({
              'name': _nameController.text,
              'mobile': _mobileController.text,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
