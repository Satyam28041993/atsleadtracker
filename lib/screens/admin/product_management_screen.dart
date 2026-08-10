import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/product_model.dart';
import '../../services/product_service.dart';

/// Admin catalog CRUD for the `products` Firestore collection.
class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key, required this.productService});

  final ProductService productService;

  @override
  State<ProductManagementScreen> createState() => _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  final Set<String> _selectedProductIds = {};
  List<Product> _currentItems = [];

  void _shareViaWhatsApp(List<Product> productsToShare) async {
    if (productsToShare.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('*Product Details:*');
    buffer.writeln('-----------------------------------');

    for (final p in productsToShare) {
      buffer.writeln('*Product Name:* ${p.name}');
      if (p.make.isNotEmpty) buffer.writeln('*Make:* ${p.make}');
      if (p.model.isNotEmpty) buffer.writeln('*Model:* ${p.model}');
      if (p.hsnNo.isNotEmpty) buffer.writeln('*HSN No:* ${p.hsnNo}');
      if (p.productOverview.isNotEmpty) {
        buffer.writeln('\n*Product Overview:*');
        buffer.writeln(p.productOverview);
      }
      if (p.keyFeatures.isNotEmpty) {
        buffer.writeln('\n*Key Feature:*');
        buffer.writeln(p.keyFeatures);
      }
      if (p.specification.isNotEmpty) {
        buffer.writeln('\n*Technical Specification:*');
        buffer.writeln(p.specification);
      }
      if (p.parametersMeasured.isNotEmpty) {
        buffer.writeln('\n*Parameter Measured:*');
        buffer.writeln(p.parametersMeasured);
      }
      if (p.accessories.isNotEmpty) {
        buffer.writeln('\n*Accessories:*');
        buffer.writeln(p.accessories);
      }
      if (p.basePrice > 0) {
        buffer.writeln('\n*Price:* INR ${p.basePrice.toStringAsFixed(0)}/-');
      }
      if (p.imageUrl.isNotEmpty) {
        buffer.writeln('\n👉 *Click to View Image:*');
        buffer.writeln(p.imageUrl);
      }
      buffer.writeln('\n-----------------------------------');
    }

    if (kIsWeb) {
      final encodedMessage = Uri.encodeComponent(buffer.toString());
      final url = Uri.parse('https://wa.me/?text=$encodedMessage');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      return;
    }

    final List<XFile> xFiles = [];
    try {
      final tempDir = await getTemporaryDirectory();
      for (var i = 0; i < productsToShare.length; i++) {
        final p = productsToShare[i];
        if (p.imageUrl.isNotEmpty) {
          final request = await HttpClient().getUrl(Uri.parse(p.imageUrl));
          final response = await request.close();
          if (response.statusCode == 200) {
            final bytes = await consolidateHttpClientResponseBytes(response);
            final file = File('${tempDir.path}/product_${i}_${DateTime.now().millisecondsSinceEpoch}.png');
            await file.writeAsBytes(bytes);
            xFiles.add(XFile(file.path));
          }
        }
      }
    } catch (_) {}

    if (xFiles.isNotEmpty) {
      await Share.shareXFiles(xFiles, text: buffer.toString());
    } else {
      await Share.share(buffer.toString());
    }
  }

  Future<void> _deleteProduct(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: const Text('This removes the catalog entry. Existing leads are unchanged.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.productService.deleteProduct(p.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete product.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        StreamBuilder<List<Product>>(
          stream: widget.productService.getProductsStream(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Could not load products.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = snapshot.data ?? const <Product>[];
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _currentItems = items;
              }
            });

            if (items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 56,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No products yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add analyzers and equipment to the catalog.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 800 ? 3 : (constraints.maxWidth > 500 ? 2 : 1));
                
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.8, // Slightly taller for the image and details
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final p = items[index];
                    final isSelected = _selectedProductIds.contains(p.id);

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isSelected ? BorderSide(color: theme.colorScheme.primary, width: 2) : BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      child: InkWell(
                        onTap: () => _openDetails(context, p),
                        onLongPress: () {
                          setState(() {
                            if (isSelected) {
                              _selectedProductIds.remove(p.id);
                            } else {
                              _selectedProductIds.add(p.id);
                            }
                          });
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  p.imageUrl.isNotEmpty
                                      ? Image.network(p.imageUrl, fit: BoxFit.cover)
                                      : Container(
                                          color: theme.colorScheme.surfaceContainerHighest,
                                          child: Icon(Icons.image_not_supported_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
                                        ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Checkbox(
                                      value: isSelected,
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedProductIds.add(p.id);
                                          } else {
                                            _selectedProductIds.remove(p.id);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 5,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 6),
                                    Text('Make: ${p.make.isEmpty ? '—' : p.make}', style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('Model: ${p.model.isEmpty ? '—' : p.model}', style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('HSN: ${p.hsnNo.isEmpty ? '—' : p.hsnNo}', style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const Spacer(),
                                    Text('INR ${p.basePrice.toStringAsFixed(0)}', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            SizedBox(
                              height: 40,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  Expanded(
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                      icon: const Icon(Icons.edit, size: 16),
                                      label: const Text('Edit', style: TextStyle(fontSize: 12)),
                                      onPressed: () => _openEditor(context, product: p),
                                    ),
                                  ),
                                  Container(width: 1, height: 24, color: theme.colorScheme.outlineVariant),
                                  Expanded(
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                      icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                      label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red)),
                                      onPressed: () => _deleteProduct(p),
                                    ),
                                  ),
                                  Container(width: 1, height: 24, color: theme.colorScheme.outlineVariant),
                                  Expanded(
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                      icon: const Icon(Icons.share, size: 16, color: Colors.green),
                                      label: const Text('Share', style: TextStyle(fontSize: 12, color: Colors.green)),
                                      onPressed: () => _shareViaWhatsApp([p]),
                                    ),
                                  ),
                                ],
                              ),
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
        ),
        if (_selectedProductIds.isNotEmpty)
          Positioned(
            left: 20,
            bottom: 20,
            child: FloatingActionButton.extended(
              heroTag: 'share_fab',
              backgroundColor: Colors.green,
              onPressed: () {
                final selectedProducts = _currentItems
                    .where((p) => _selectedProductIds.contains(p.id))
                    .toList();
                _shareViaWhatsApp(selectedProducts);
              },
              icon: const Icon(Icons.share, color: Colors.white),
              label: Text(
                'Share Selected (${_selectedProductIds.length})',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.extended(
            heroTag: 'add_fab',
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add product'),
          ),
        ),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context, {Product? product}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ProductEditorDialog(
        productService: widget.productService,
        initial: product,
      ),
    );
  }

  Future<void> _openDetails(BuildContext context, Product product) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ProductDetailsDialog(
        product: product,
        onEdit: () {
          Navigator.of(ctx).pop();
          _openEditor(context, product: product);
        },
        onShare: () {
          _shareViaWhatsApp([product]);
        },
      ),
    );
  }
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({
    required this.productService,
    this.initial,
  });

  final ProductService productService;
  final Product? initial;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _hsnNo;
  late final TextEditingController _specification;
  late final TextEditingController _accessories;
  late final TextEditingController _parametersMeasured;
  late final TextEditingController _price;
  late final TextEditingController _productOverview;
  late final TextEditingController _keyFeatures;

  PlatformFile? _selectedImage;
  String? _existingImageUrl;
  bool _saving = false;

  bool get _isEdit => widget.initial != null;

  String _extensionFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot >= name.length - 1) return 'png';
    return name.substring(dot + 1);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _existingImageUrl = p?.imageUrl;
    _name = TextEditingController(text: p?.name ?? '');
    _make = TextEditingController(text: p?.make ?? '');
    _model = TextEditingController(text: p?.model ?? '');
    _hsnNo = TextEditingController(text: p?.hsnNo ?? '');
    _specification = TextEditingController(text: p?.specification ?? '');
    _accessories = TextEditingController(text: p?.accessories ?? '');
    _parametersMeasured = TextEditingController(text: p?.parametersMeasured ?? '');
    _price = TextEditingController(
      text: p != null && p.basePrice > 0 ? p.basePrice.toString() : '',
    );
    _productOverview = TextEditingController(text: p?.productOverview ?? '');
    _keyFeatures = TextEditingController(text: p?.keyFeatures ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _make.dispose();
    _model.dispose();
    _hsnNo.dispose();
    _specification.dispose();
    _accessories.dispose();
    _parametersMeasured.dispose();
    _price.dispose();
    _productOverview.dispose();
    _keyFeatures.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    final price = double.tryParse(_price.text.replaceAll(',', '').trim()) ?? 0;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      String finalImageUrl = _existingImageUrl ?? '';
      String productId = widget.initial?.id ?? FirebaseFirestore.instance.collection('products').doc().id;

      // Upload image first if one was selected
      if (_selectedImage != null) {
        final bytes = _selectedImage!.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw StateError(
            'Could not read the selected image. Try a smaller JPG/PNG file.',
          );
        }
        final extension = _extensionFromName(_selectedImage!.name);
        finalImageUrl = await widget.productService.uploadProductImage(
          productId,
          bytes,
          extension,
        );
      }

      final product = Product(
        id: productId,
        name: name,
        make: _make.text.trim(),
        model: _model.text.trim(),
        hsnNo: _hsnNo.text.trim(),
        specification: _specification.text.trim(),
        accessories: _accessories.text.trim(),
        parametersMeasured: _parametersMeasured.text.trim(),
        basePrice: price,
        imageUrl: finalImageUrl,
        productOverview: _productOverview.text.trim(),
        keyFeatures: _keyFeatures.text.trim(),
      );
      if (_isEdit) {
        await widget.productService.updateProduct(product);
      } else {
        await widget.productService.addProduct(product);
      }
      if (mounted) {
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Product updated.' : 'Product added.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stackTrace) {
      print('!!! ERROR SAVING PRODUCT !!!');
      print('Error Type: ${e.runtimeType}');
      print('Error Message: $e');
      print('Stack Trace:\n$stackTrace');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Could not save product: $e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit product' : 'Add product'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selectedImage?.bytes != null)
                Container(
                  height: 150,
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: MemoryImage(_selectedImage!.bytes!),
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty)
                Container(
                  height: 150,
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: NetworkImage(_existingImageUrl!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        try {
                          final result = await FilePicker.pickFiles(
                            type: FileType.image,
                            withData: true,
                          );
                          if (result == null || result.files.isEmpty) return;
                          final file = result.files.first;
                          if (file.bytes == null || file.bytes!.isEmpty) {
                            _showMessage(
                              'Could not read the selected image. Try another JPG or PNG.',
                            );
                            return;
                          }
                          setState(() => _selectedImage = file);
                        } catch (e) {
                          _showMessage('Could not pick image: $e');
                        }
                      },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_selectedImage != null || (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) ? 'Change Image' : 'Upload Image'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Product Name *',
                  hintText: 'e.g. Portable Bio Gas Analyzer',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _make,
                decoration: const InputDecoration(
                  labelText: 'Make',
                  hintText: 'e.g. Applied Techno Systems',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _model,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  hintText: 'e.g. ATS- 201A',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hsnNo,
                decoration: const InputDecoration(
                  labelText: 'HSN No',
                  hintText: 'e.g. 90271000',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _productOverview,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Product Overview',
                  hintText: 'e.g. Compact and rugged instrument...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keyFeatures,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Key Feature',
                  hintText: 'e.g. Simultaneous multi-gas measurement...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _specification,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Technical Specification',
                  hintText: 'Accuracy, Display type, sampling method, etc.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _parametersMeasured,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Parameter Measured',
                  hintText: 'e.g. O2, EC, 0-25% V/V, 0.1%\nCO, NDIR, 0-50% V/V, 0.1%',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _accessories,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Accessories',
                  hintText: 'Calibration Certificate, User Manual, etc.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Base price',
                  prefixText: 'INR ',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isEdit)
          TextButton(
            onPressed: _saving
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete product?'),
                        content: const Text(
                          'This removes the catalog entry. Existing leads are unchanged.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true || !context.mounted) return;
                    setState(() => _saving = true);
                    try {
                      await widget.productService.deleteProduct(widget.initial!.id);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Product deleted.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not delete.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } finally {
                      if (context.mounted) {
                        setState(() => _saving = false);
                      }
                    }
                  },
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

class _ProductDetailsDialog extends StatelessWidget {
  const _ProductDetailsDialog({
    required this.product,
    required this.onEdit,
    required this.onShare,
  });

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: size.height * 0.85,
        ),
        width: size.width * 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Image Section with Close button
            Stack(
              children: [
                Container(
                  height: size.height * 0.35,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: isDark ? Colors.grey[900] : Colors.grey[100],
                  child: product.imageUrl.isNotEmpty
                      ? Image.network(
                          product.imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(Icons.broken_image_outlined, size: 64, color: theme.colorScheme.error),
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                        ),
                ),
                // Close button
                Positioned(
                  top: 12,
                  right: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.black.withOpacity(0.4),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ],
            ),

            // Details Content Section
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Make Badge (if present)
                    if (product.make.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          product.make,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Product Name
                    Text(
                      product.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Price Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Catalog Price',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              product.basePrice > 0
                                  ? 'INR ${product.basePrice.toStringAsFixed(0)}/-'
                                  : 'Contact for Price',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (product.hsnNo.isNotEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'HSN Code',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                product.hsnNo,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Model Info Row
                    if (product.model.isNotEmpty) ...[
                      _buildInfoRow(theme, Icons.settings_suggest_outlined, 'Model', product.model),
                      const SizedBox(height: 12),
                    ],

                    // Product Overview Section
                    if (product.productOverview.isNotEmpty) ...[
                      _buildSectionHeader(theme, Icons.info_outline_rounded, 'Product Overview'),
                      const SizedBox(height: 8),
                      _buildSectionContent(theme, product.productOverview),
                      const SizedBox(height: 20),
                    ],

                    // Key Feature Section
                    if (product.keyFeatures.isNotEmpty) ...[
                      _buildSectionHeader(theme, Icons.star_outline_rounded, 'Key Feature'),
                      const SizedBox(height: 8),
                      _buildSectionContent(theme, product.keyFeatures),
                      const SizedBox(height: 20),
                    ],

                    // Technical Specification Section
                    if (product.specification.isNotEmpty) ...[
                      _buildSectionHeader(theme, Icons.list_alt_outlined, 'Technical Specification'),
                      const SizedBox(height: 8),
                      _buildSectionContent(theme, product.specification),
                      const SizedBox(height: 20),
                    ],

                    // Parameter Measured Section
                    if (product.parametersMeasured.isNotEmpty) ...[
                      _buildSectionHeader(theme, Icons.analytics_outlined, 'Parameter Measured'),
                      const SizedBox(height: 8),
                      _buildSectionContent(theme, product.parametersMeasured),
                      const SizedBox(height: 20),
                    ],

                    // Accessories Section
                    if (product.accessories.isNotEmpty) ...[
                      _buildSectionHeader(theme, Icons.extension_outlined, 'Accessories'),
                      const SizedBox(height: 8),
                      _buildSectionContent(theme, product.accessories),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),

            // Footer Actions
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: theme.colorScheme.outline),
                      ),
                      onPressed: () {
                        onShare();
                      },
                      icon: const Icon(Icons.share_outlined, color: Colors.green),
                      label: const Text('Share Details', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit Product', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionContent(ThemeData theme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
      ),
    );
  }
}
