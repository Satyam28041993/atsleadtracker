import 'package:flutter/material.dart';

class TemplateEditor extends StatelessWidget {
  const TemplateEditor({
    required this.controller,
    required this.loading,
    required this.saving,
    required this.onTemplateChanged,
    required this.onInsertVariable,
    required this.onSave,
    required this.previewMessage,
    super.key,
  });

  final TextEditingController controller;
  final bool loading;
  final bool saving;
  final ValueChanged<String> onTemplateChanged;
  final ValueChanged<String> onInsertVariable;
  final VoidCallback onSave;
  final String previewMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x141D4ED8),
                  blurRadius: 18,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              maxLines: 6,
              onChanged: onTemplateChanged,
              decoration: InputDecoration(
                labelText: 'Message Template',
                hintText: 'Hi {name}, this is ... regarding {requirement}.',
                alignLabelWithHint: true,
                fillColor: const Color(0xFFFBFDFF),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF4F46E5),
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Quick variables',
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFF475569),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _VariableChip(
                label: '[name]',
                token: '{name}',
                onTap: onInsertVariable,
              ),
              _VariableChip(
                label: '[requirement]',
                token: '{requirement}',
                onTap: onInsertVariable,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live Preview',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  previewMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Tooltip(
            message: 'Save this template for all users',
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x332563EB),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: saving ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: const Color(0xFF94A3B8),
                  minimumSize: const Size(170, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(saving ? 'Saving...' : 'Save Template'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _VariableChip extends StatefulWidget {
  const _VariableChip({
    required this.label,
    required this.token,
    required this.onTap,
  });

  final String label;
  final String token;
  final ValueChanged<String> onTap;

  @override
  State<_VariableChip> createState() => _VariableChipState();
}

class _VariableChipState extends State<_VariableChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onTap(widget.token),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFE0E7FF) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF6366F1)
                  : const Color(0xFFD8E0EB),
            ),
          ),
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF334155),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
