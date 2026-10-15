import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:client/core/database/app_database.dart';
import 'package:client/core/providers/database_providers.dart';
import 'package:client/core/sync/sync_providers.dart';
import 'package:client/core/utils/formatters.dart';
import 'package:client/core/providers/locale_provider.dart';
import 'package:client/features/checkout/screens/barcode_scanner_screen.dart';
import 'package:client/l10n/app_localizations.dart';

class ProductFormModal extends ConsumerStatefulWidget {
  final ProductsTableData? product; // null if creating, populated if editing
  final String? initialBarcode;

  const ProductFormModal({super.key, this.product, this.initialBarcode});

  static Future<void> show(BuildContext context, {ProductsTableData? product, String? initialBarcode}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProductFormModal(product: product, initialBarcode: initialBarcode),
    );
  }

  @override
  ConsumerState<ProductFormModal> createState() => _ProductFormModalState();
}

class _ProductFormModalState extends ConsumerState<ProductFormModal> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameEnController;
  late final TextEditingController _nameAmController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _stockQuantityController;
  late final TextEditingController _minStockController;

  late String _category;
  late String _unitType;
  bool _isSubmitting = false;

  final List<String> _categories = [
    'General',
    'Groceries',
    'Bakery',
    'Dairy',
    'Beverages',
    'Spices',
    'Fresh',
    'Household',
  ];

  final List<String> _unitTypes = [
    'piece',
    'kg',
    'liter',
    'packet',
    'bundle',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameEnController = TextEditingController(text: p?.nameEn ?? '');
    _nameAmController = TextEditingController(text: p?.nameAm ?? '');
    _barcodeController = TextEditingController(text: p?.barcode ?? widget.initialBarcode ?? '');
    _sellingPriceController = TextEditingController(
      text: p != null ? p.sellingPrice.toStringAsFixed(2) : '',
    );
    _costPriceController = TextEditingController(
      text: p != null && p.costPrice > 0 ? p.costPrice.toStringAsFixed(2) : '',
    );
    _stockQuantityController = TextEditingController(
      text: p != null ? p.stockQuantity.toStringAsFixed(0) : '0',
    );
    _minStockController = TextEditingController(
      text: p != null ? p.minStockLevel.toStringAsFixed(0) : '5',
    );
    _category = p?.category ?? 'General';
    _unitType = p?.unitType ?? 'piece';
  }

  @override
  void dispose() {
    _nameEnController.dispose();
    _nameAmController.dispose();
    _barcodeController.dispose();
    _sellingPriceController.dispose();
    _costPriceController.dispose();
    _stockQuantityController.dispose();
    _minStockController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final scannedCode = await BarcodeScannerScreen.scanBarcode(context);
    if (scannedCode != null && scannedCode.isNotEmpty) {
      setState(() {
        _barcodeController.text = scannedCode;
      });

      // Check if product already exists with this barcode
      if (mounted) {
        final db = ref.read(databaseProvider);
        final existing = await db.getProductByBarcode(scannedCode);
        if (existing != null && existing.id != widget.product?.id && mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n?.duplicateBarcodeWarning ?? "A product with this barcode already exists"}: ${existing.nameEn}'),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final db = ref.read(databaseProvider);
      final shopId = ref.read(shopIdProvider);
      final isEditing = widget.product != null;
      final productId = widget.product?.id ?? UuidUtil.generate();

      final nameEn = _nameEnController.text.trim();
      final nameAm = _nameAmController.text.trim();
      final barcode = _barcodeController.text.trim().isNotEmpty
          ? _barcodeController.text.trim()
          : null;
      final sellingPrice = double.tryParse(_sellingPriceController.text.trim()) ?? 0.0;
      final costPrice = double.tryParse(_costPriceController.text.trim()) ?? 0.0;
      final stockQuantity = double.tryParse(_stockQuantityController.text.trim()) ?? 0.0;
      final minStockLevel = double.tryParse(_minStockController.text.trim()) ?? 5.0;

      final companion = ProductsTableCompanion(
        id: drift.Value(productId),
        shopId: drift.Value(shopId),
        nameEn: drift.Value(nameEn),
        nameAm: drift.Value(nameAm),
        barcode: drift.Value(barcode),
        category: drift.Value(_category),
        unitType: drift.Value(_unitType),
        sellingPrice: drift.Value(sellingPrice),
        costPrice: drift.Value(costPrice),
        stockQuantity: drift.Value(stockQuantity),
        minStockLevel: drift.Value(minStockLevel),
        updatedAt: drift.Value(DateTime.now()),
      );

      final syncPayload = {
        'id': productId,
        'shop_id': shopId,
        'name_en': nameEn,
        'name_am': nameAm,
        'barcode': barcode,
        'category': _category,
        'unit_type': _unitType,
        'selling_price': sellingPrice,
        'cost_price': costPrice,
        'stock_quantity': stockQuantity,
        'min_stock_level': minStockLevel,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Atomic SQLite write + mutation queue
      await db.upsertProductAtomic(
        product: companion,
        operation: isEditing ? 'UPDATE' : 'CREATE',
        syncPayloadJson: jsonEncode(syncPayload),
      );

      // Non-blocking sync trigger
      ref.read(syncManagerProvider).triggerSync();

      if (!mounted) return;
      Navigator.of(context).pop();

      final isAmharic = ref.read(localeProvider.notifier).isAmharic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAmharic ? 'ዕቃው በተሳካ ሁኔታ ተመዝግቧል!' : 'Product saved successfully!',
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving product: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isEditing = widget.product != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                    child: Icon(
                      isEditing ? Icons.edit : Icons.add_box,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing
                          ? (l10n?.adjustStock ?? 'Edit Product')
                          : (l10n?.addItem ?? 'Add Item'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Product Name En & Am
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nameEnController,
                      decoration: InputDecoration(
                        labelText: l10n?.nameEn ?? 'Name (English)',
                        hintText: 'e.g. 5L Cooking Oil',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'English name required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _nameAmController,
                      decoration: InputDecoration(
                        labelText: l10n?.nameAm ?? 'Name (Amharic)',
                        hintText: 'ምሳሌ፡ ዘይት 5L',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty
                          ? 'Amharic name required'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Barcode + Camera Scan & Generate buttons
              TextFormField(
                controller: _barcodeController,
                decoration: InputDecoration(
                  labelText: l10n?.barcode ?? 'Barcode',
                  hintText: 'Scan or type barcode',
                  prefixIcon: const Icon(Icons.qr_code),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.camera_alt_outlined, size: 22, color: Color(0xFF1B5E20)),
                        tooltip: l10n?.scanBarcodePrompt ?? 'Scan Barcode',
                        onPressed: _scanBarcode,
                      ),
                      IconButton(
                        icon: const Icon(Icons.auto_awesome, size: 20),
                        tooltip: 'Generate Barcode',
                        onPressed: () {
                          final generated = DateTime.now().millisecondsSinceEpoch.toString();
                          _barcodeController.text = generated;
                        },
                      ),
                    ],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Category & Unit Type
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: InputDecoration(
                        labelText: l10n?.category ?? 'Category',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: _categories.map((c) {
                        final isAmharic = ref.watch(localeProvider.notifier).isAmharic;
                        final localized = CategoryLocalizer.getLocalizedName(c, isAmharic: isAmharic);
                        return DropdownMenuItem(value: c, child: Text(localized));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _category = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _unitType,
                      decoration: InputDecoration(
                        labelText: l10n?.unitType ?? 'Unit',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: _unitTypes.map((u) {
                        return DropdownMenuItem(value: u, child: Text(u));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _unitType = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Selling Price & Cost Price
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sellingPriceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        labelText: '${l10n?.sellingPrice ?? 'Selling Price'} (ETB)',
                        prefixIcon: const Icon(Icons.sell),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Price required';
                        final num = double.tryParse(val);
                        if (num == null || num <= 0) return 'Invalid price';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _costPriceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        labelText: '${l10n?.costPrice ?? 'Cost Price'} (ETB)',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Stock Quantity & Min Alert Level
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stockQuantityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        labelText: '${l10n?.initialStock ?? 'Stock'} ($_unitType)',
                        prefixIcon: const Icon(Icons.inventory_2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _minStockController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n?.minStockAlert ?? 'Min Alert Level',
                        prefixIcon: const Icon(Icons.warning_amber),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Save Button
              ElevatedButton(
                onPressed: _isSubmitting ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Text(
                        l10n?.saveChanges ?? 'Save Product',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
