import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/utils/formatters.dart';
import 'package:client/core/providers/locale_provider.dart';
import 'package:client/l10n/app_localizations.dart';
import '../providers/inventory_providers.dart';
import '../widgets/adjust_stock_modal.dart';
import '../widgets/product_form_modal.dart';
import '../../checkout/screens/barcode_scanner_screen.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;

    final products = ref.watch(filteredInventoryProductsProvider);
    final metrics = ref.watch(inventoryMetricsProvider);
    final currentStockFilter = ref.watch(inventoryStockFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          // Top Search & Add Item
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      ref.read(inventorySearchQueryProvider.notifier).setQuery(val);
                    },
                    decoration: InputDecoration(
                      hintText: l10n?.searchProduct ?? 'Search product or barcode...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(inventorySearchQueryProvider.notifier).setQuery('');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: l10n?.scanBarcodePrompt ?? 'Scan Barcode',
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                    foregroundColor: theme.colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner, size: 22),
                  onPressed: () async {
                    final scannedCode = await BarcodeScannerScreen.scanBarcode(context);
                    if (scannedCode != null && scannedCode.isNotEmpty && context.mounted) {
                      _searchController.text = scannedCode;
                      ref.read(inventorySearchQueryProvider.notifier).setQuery(scannedCode);
                    }
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => ProductFormModal.show(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(
                    l10n?.addItem ?? 'Add Item',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Filter Chips (All, Low Stock, Out of Stock)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('${l10n?.allProducts ?? 'All Items'} (${metrics.totalCount})'),
                  selected: currentStockFilter == StockFilter.all,
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(inventoryStockFilterProvider.notifier).setFilter(StockFilter.all);
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text('${l10n?.lowStock ?? 'Low Stock'} (${metrics.lowStockCount})'),
                    ],
                  ),
                  selected: currentStockFilter == StockFilter.lowStock,
                  selectedColor: Colors.amber.shade100,
                  onSelected: (selected) {
                    ref.read(inventoryStockFilterProvider.notifier).setFilter(
                          selected ? StockFilter.lowStock : StockFilter.all,
                        );
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 14, color: Colors.red),
                      const SizedBox(width: 4),
                      Text('${l10n?.outOfStock ?? 'Out of Stock'} (${metrics.outOfStockCount})'),
                    ],
                  ),
                  selected: currentStockFilter == StockFilter.outOfStock,
                  selectedColor: Colors.red.shade100,
                  onSelected: (selected) {
                    ref.read(inventoryStockFilterProvider.notifier).setFilter(
                          selected ? StockFilter.outOfStock : StockFilter.all,
                        );
                  },
                ),
              ],
            ),
          ),

          // Total Inventory Valuation Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n?.stockLevel ?? 'Stock Level'}: ${metrics.totalCount} items',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    CurrencyFormatter.format(metrics.totalStockValue, isAmharic: isAmharic),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Product List
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          l10n?.noProductsFound ?? 'No products found',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return _buildProductCard(
                        context: context,
                        product: product,
                        isAmharic: isAmharic,
                        l10n: l10n,
                        theme: theme,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard({
    required BuildContext context,
    required ProductsTableData product,
    required bool isAmharic,
    required AppLocalizations? l10n,
    required ThemeData theme,
  }) {
    final title = isAmharic ? '${product.nameAm} (${product.nameEn})' : '${product.nameEn} (${product.nameAm})';
    final isOutOfStock = product.stockQuantity <= 0;
    final isLowStock = !isOutOfStock && product.stockQuantity <= product.minStockLevel;

    Color badgeBgColor;
    Color badgeTextColor;
    IconData? badgeIcon;

    if (isOutOfStock) {
      badgeBgColor = Colors.red.shade50;
      badgeTextColor = Colors.red.shade700;
      badgeIcon = Icons.error_outline;
    } else if (isLowStock) {
      badgeBgColor = Colors.amber.shade50;
      badgeTextColor = Colors.amber.shade900;
      badgeIcon = Icons.warning_amber;
    } else {
      badgeBgColor = Colors.green.shade50;
      badgeTextColor = const Color(0xFF2E7D32);
      badgeIcon = Icons.check_circle_outline;
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOutOfStock
              ? Colors.red.shade200
              : (isLowStock ? Colors.amber.shade200 : Colors.grey.shade200),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left icon avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: badgeBgColor,
              child: Icon(badgeIcon, color: badgeTextColor, size: 20),
            ),
            const SizedBox(width: 12),

            // Product Information
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          CategoryLocalizer.getLocalizedName(product.category, isAmharic: isAmharic),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        ),
                      ),
                      if (product.barcode != null && product.barcode!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '#${product.barcode}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    CurrencyFormatter.format(product.sellingPrice, isAmharic: isAmharic),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            // Right: Stock level badge + Quick Action Buttons
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBgColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: badgeTextColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${product.stockQuantity.toStringAsFixed(product.stockQuantity % 1 == 0 ? 0 : 2)} ${product.unitType}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: badgeTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Edit Product button
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.blueGrey,
                      tooltip: 'Edit',
                      onPressed: () => ProductFormModal.show(context, product: product),
                    ),
                    const SizedBox(width: 8),

                    // Stock + button
                    ElevatedButton.icon(
                      onPressed: () => AdjustStockModal.show(context, product),
                      icon: const Icon(Icons.add, size: 14),
                      label: Text(
                        l10n?.addStock ?? 'Stock +',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
