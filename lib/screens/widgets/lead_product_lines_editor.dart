import 'package:flutter/material.dart';

import '../../models/lead_product_line.dart';
import '../../models/product_model.dart';
import '../../services/product_service.dart';

/// Controllers for one product line in a lead/tender form.
class LeadProductLineFields {
  LeadProductLineFields({LeadProductLine? initial})
      : modelController = TextEditingController(text: initial?.modelNo ?? ''),
        _initialRequirement = initial?.requirement ?? '';

  final TextEditingController modelController;
  final String _initialRequirement;

  /// Set by [Autocomplete] fieldViewBuilder (do not dispose manually).
  TextEditingController? requirementController;

  void dispose() {
    modelController.dispose();
  }

  LeadProductLine toLine() {
    return LeadProductLine(
      requirement: requirementController?.text.trim() ?? '',
      modelNo: modelController.text.trim(),
    );
  }
}

/// Reusable multi-product editor (catalog autocomplete + model per line).
class LeadProductLinesEditor extends StatefulWidget {
  const LeadProductLinesEditor({
    super.key,
    required this.productService,
    required this.lines,
    required this.onChanged,
    this.productNameLabel = 'Requirement *',
    this.modelNoLabel = 'Model No',
    this.productHint = 'Search catalog or type a description',
    this.modelHint = 'Fills automatically from catalog or type manually',
    this.requireFirstLine = true,
    this.enabled = true,
  });

  final ProductService productService;
  final List<LeadProductLineFields> lines;
  final VoidCallback onChanged;
  final String productNameLabel;
  final String modelNoLabel;
  final String productHint;
  final String modelHint;
  final bool requireFirstLine;
  final bool enabled;

  @override
  State<LeadProductLinesEditor> createState() => _LeadProductLinesEditorState();
}

class _LeadProductLinesEditorState extends State<LeadProductLinesEditor> {
  void _notify() => widget.onChanged();

  void _addLine() {
    setState(() {
      widget.lines.add(LeadProductLineFields());
    });
    _notify();
  }

  void _removeLine(int index) {
    if (widget.lines.length <= 1) return;
    setState(() {
      widget.lines[index].dispose();
      widget.lines.removeAt(index);
    });
    _notify();
  }

  String? _validateRequirement(String? value, int index) {
    if (!widget.requireFirstLine || index > 0) return null;
    if (value == null || value.trim().isEmpty) {
      final label =
          widget.productNameLabel.replaceAll('*', '').trim().toLowerCase();
      return 'Please enter $label';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.enabled ? _addLine : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Product'),
          ),
        ),
        ...List.generate(widget.lines.length, (index) {
          final line = widget.lines[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Product #${index + 1}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.lines.length > 1)
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                        ),
                        onPressed:
                            widget.enabled ? () => _removeLine(index) : null,
                        tooltip: 'Remove product',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<Product>>(
                  stream: widget.productService.getProductsStream(),
                  builder: (context, snapshot) {
                    final products = snapshot.data ?? const <Product>[];
                    return Autocomplete<Product>(
                      displayStringForOption: (p) => p.name,
                      optionsBuilder: (TextEditingValue tev) {
                        final q = tev.text.trim().toLowerCase();
                        if (q.isEmpty) return products.take(16);
                        return products
                            .where((p) => p.name.toLowerCase().contains(q))
                            .take(24);
                      },
                      onSelected: (p) {
                        setState(() {
                          line.modelController.text = p.model;
                        });
                        _notify();
                      },
                      fieldViewBuilder: (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        line.requirementController = textEditingController;
                        if (line._initialRequirement.isNotEmpty &&
                            textEditingController.text.isEmpty) {
                          textEditingController.text = line._initialRequirement;
                        }
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          textInputAction: TextInputAction.next,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: widget.productNameLabel,
                            hintText: widget.productHint,
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) => _validateRequirement(v, index),
                          enabled: widget.enabled,
                          onChanged: (_) => _notify(),
                          onFieldSubmitted: (_) => onFieldSubmitted(),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: line.modelController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: widget.modelNoLabel,
                    hintText: widget.modelHint,
                    border: const OutlineInputBorder(),
                  ),
                  enabled: widget.enabled,
                  onChanged: (_) => _notify(),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
