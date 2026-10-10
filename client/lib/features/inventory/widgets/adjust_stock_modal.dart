import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/providers/database_providers.dart';
import 'package:client/core/sync/sync_providers.dart';
import 'package:client/core/providers/locale_provider.dart';
import 'package:client/l10n/app_localizations.dart';

class AdjustStockModal extends ConsumerStatefulWidget {
  final ProductsTableData product;

  const AdjustStockModal({super.key, required this.product});

  static Future<void> show(BuildContext context, ProductsTableData product) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AdjustStockModal(product: product),
    );
  }

  @override
  ConsumerState<AdjustStockModal> createState() => _AdjustStockModalState();
}

class _AdjustStockModalState extends ConsumerState<AdjustStockModal> {
  final _quantityController = TextEditingController(text: '10');
  final _costPriceController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isDirectCount = false; // false = Add Quantity, true = Set Exact Total
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.product.costPrice > 0) {
      _costPriceController.text = widget.product.costPrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costPriceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _applyQuickAdd(double amount) {
    setState(() {
      _isDirectCount = false;
      final current = double.tryParse(_quantityController.text) ?? 0.0;
      _quantityController.text = (current + amount).toStringAsFixed(0);
    });
  }

  Future<void> _handleSave() async {
    final qtyInput = double.tryParse(_quantityController.text) ?? 0.0;
    final currentStock = widget.product.stockQuantity;
    final newStock = _isDirectCount ? qtyInput : (currentStock + qtyInput);
    if (newStock < 0) return;

    final stockDelta = newStock - currentStock;
    final newCostPrice = double.tryParse(_costPriceController.text) ?? widget.product.costPrice;
    final reason = _reasonController.text.trim();

    setState(() => _isSubmitting = true);

    try {
      final db = ref.read(databaseProvider);

      final syncPayload = {
        'id': widget.product.id,
        'shop_id': widget.product.shopId,
        'name_en': widget.product.nameEn,
        'name_am': widget.product.nameAm,
        'barcode': widget.product.barcode,
        'category': widget.product.category,
        'unit_type': widget.product.unitType,
        'selling_price': widget.product.sellingPrice,
        'cost_price': newCostPrice,
        'stock_quantity': newStock,
        'stock_delta': stockDelta,
        'min_stock_level': widget.product.minStockLevel,
        'reason': reason.isNotEmpty ? reason : (_isDirectCount ? 'Direct Stocktake' : 'Restock'),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Atomic SQLite write: updates stock + logs mutation into sync_queue
      await db.adjustStockAtomic(
        productId: widget.product.id,
        newQuantity: newStock,
        newCostPrice: newCostPrice,
        syncPayloadJson: jsonEncode(syncPayload),
      );

      // Trigger background sync non-blocking
      ref.read(syncManagerProvider).triggerSync();

      if (!mounted) return;
      Navigator.of(context).pop();

      final isAmharic = ref.read(localeProvider.notifier).isAmharic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAmharic
                ? 'ክምችቱ በተሳካ ሁኔታ ተስተካክሏል!'
                : 'Stock updated successfully!',
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating stock: $e'),
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
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;

    final productName = isAmharic ? widget.product.nameAm : widget.product.nameEn;
    final secondaryName = isAmharic ? widget.product.nameEn : widget.product.nameAm;
    final currentStock = widget.product.stockQuantity;
    final qtyInput = double.tryParse(_quantityController.text) ?? 0.0;
    final newCalculatedStock = _isDirectCount ? qtyInput : (currentStock + qtyInput);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
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
                  child: Icon(Icons.inventory, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        secondaryName,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Current Stock Indicator Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n?.currentStock ?? 'Current Stock',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${currentStock.toStringAsFixed(currentStock % 1 == 0 ? 0 : 2)} ${widget.product.unitType}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: currentStock <= 0
                          ? Colors.red
                          : (currentStock <= widget.product.minStockLevel
                              ? Colors.amber.shade900
                              : const Color(0xFF2E7D32)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Mode Toggle: Add Stock vs Exact Count
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l10n?.addStock ?? 'Stock +'),
                  icon: const Icon(Icons.add, size: 16),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(l10n?.adjustStock ?? 'Exact Count'),
                  icon: const Icon(Icons.edit_note, size: 16),
                ),
              ],
              selected: {_isDirectCount},
              onSelectionChanged: (selected) {
                setState(() {
                  _isDirectCount = selected.first;
                  if (_isDirectCount) {
                    _quantityController.text = currentStock.toStringAsFixed(0);
                  } else {
                    _quantityController.text = '10';
                  }
                });
              },
            ),
            const SizedBox(height: 14),

            // Quick increment chips (if in add stock mode)
            if (!_isDirectCount) ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final val in [5.0, 10.0, 20.0, 50.0, 100.0])
                    ActionChip(
                      label: Text('+${val.toInt()}'),
                      onPressed: () => _applyQuickAdd(val),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Quantity TextField
            TextField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _isDirectCount
                    ? (l10n?.newTotalStock ?? 'New Total Stock')
                    : (l10n?.quantityToAdd ?? 'Quantity to Add'),
                suffixText: widget.product.unitType,
                prefixIcon: const Icon(Icons.numbers),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Reason / Note
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: l10n?.referenceOrNote ?? 'Reason / Note (Optional)',
                hintText: _isDirectCount ? 'Physical stocktake' : 'Shipment delivery',
                prefixIcon: const Icon(Icons.notes),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Resulting Stock Preview Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n?.newTotalStock ?? 'New Total Stock',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  Text(
                    '${newCalculatedStock.toStringAsFixed(newCalculatedStock % 1 == 0 ? 0 : 2)} ${widget.product.unitType}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Save Button
            ElevatedButton(
              onPressed: _isSubmitting || newCalculatedStock < 0
                  ? null
                  : _handleSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
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
                      l10n?.saveChanges ?? 'Save Changes',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
