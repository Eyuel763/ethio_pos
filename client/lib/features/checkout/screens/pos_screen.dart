import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/utils/formatters.dart';
import '../providers/cart_provider.dart';
import '../widgets/product_catalog_list.dart';
import '../widgets/cart_item_list.dart';
import '../widgets/checkout_modal.dart';
import 'barcode_scanner_screen.dart';
import 'package:client/l10n/app_localizations.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isCartExpanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showCheckoutModal() {
    final cart = ref.read(cartProvider);
    if (cart.items.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CheckoutModal(),
    );
  }

  void _openBarcodeScanner() {
    BarcodeScannerScreen.push(context);
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final cart = ref.watch(cartProvider);
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          // 1. Search Bar & Camera Barcode Scan Action Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l10n?.searchProduct ?? 'Search product...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  label: Text(
                    isAmharic ? 'ቃኝ' : 'Scan',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _openBarcodeScanner,
                ),
              ],
            ),
          ),

          // 2. Primary Scrollable List of Products
          Expanded(
            child: productsAsync.when(
              data: (allProducts) {
                final query = _searchController.text.trim().toLowerCase();
                var filtered = allProducts;
                if (query.isNotEmpty) {
                  filtered = filtered
                      .where((p) =>
                          p.nameEn.toLowerCase().contains(query) ||
                          p.nameAm.toLowerCase().contains(query) ||
                          (p.barcode != null && p.barcode!.contains(query)))
                      .toList();
                }
                return ProductCatalogList(products: filtered);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),

          // 3. Current Cart Items Section (Compact & Placed Down at the Bottom)
          if (cart.items.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    offset: const Offset(0, -2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cart Header Bar with Expand/Collapse & Clear
                  InkWell(
                    onTap: () {
                      setState(() => _isCartExpanded = !_isCartExpanded);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shopping_cart,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${l10n?.currentCart ?? "Cart"} (${cart.totalItemCount})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const Spacer(),
                          // Clear cart button
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              ref.read(cartProvider.notifier).clearCart();
                            },
                            child: Text(
                              l10n?.clearCart ?? 'CLEAR',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            _isCartExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_up,
                            color: Colors.grey.shade600,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Expandable Cart Items List (when toggled open)
                  if (_isCartExpanded) ...[
                    const Divider(height: 1),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: const CartItemList(),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // 4. Sticky Bottom Charge Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  offset: const Offset(0, -3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n?.subtotal ?? 'Subtotal:',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          CurrencyFormatter.format(cart.grandTotal, isAmharic: isAmharic),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade500,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: cart.items.isEmpty ? null : _showCheckoutModal,
                    child: Text(
                      '${l10n?.charge ?? "CHARGE"} (${CurrencyFormatter.format(cart.grandTotal, isAmharic: isAmharic)})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
