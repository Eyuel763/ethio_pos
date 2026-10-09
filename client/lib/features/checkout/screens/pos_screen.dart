import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/utils/formatters.dart';
import '../providers/cart_provider.dart';
import '../widgets/quick_keys_grid.dart';
import '../widgets/cart_item_list.dart';
import '../widgets/checkout_modal.dart';
import 'package:client/l10n/app_localizations.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final TextEditingController _searchController = TextEditingController();

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

  void _handleSimulateScan() async {
    final db = ref.read(databaseProvider);
    final isAmharic = ref.read(localeProvider.notifier).isAmharic;
    final products = await db.select(db.productsTable).get();

    if (products.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isAmharic ? 'ዕቃዎች አልተገኙም' : 'No products in database to scan')),
      );
      return;
    }

    // Pick first product as barcode scan simulation
    final scannedProduct = products.first;
    ref.read(cartProvider.notifier).addProduct(scannedProduct);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scanned: ${isAmharic ? scannedProduct.nameAm : scannedProduct.nameEn} (EAN-13)'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l10n?.searchProduct ?? 'Search product...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  label: Text(
                    isAmharic ? 'ቃኝ' : 'Scan',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _handleSimulateScan,
                ),
              ],
            ),
          ),

          // 2. Quick-Key Categories & Grid
          productsAsync.when(
            data: (allProducts) {
              final query = _searchController.text.trim().toLowerCase();
              var filtered = allProducts;
              if (query.isNotEmpty) {
                filtered = filtered.where((p) =>
                  p.nameEn.toLowerCase().contains(query) ||
                  p.nameAm.contains(query) ||
                  (p.barcode != null && p.barcode!.contains(query))
                ).toList();
              }
              return QuickKeysGrid(products: filtered);
            },
            loading: () => const SizedBox(height: 110, child: Center(child: CircularProgressIndicator())),
            error: (err, _) => Text('Error: $err'),
          ),

          const Divider(height: 1),

          // 3. Cart Items Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${l10n?.currentCart ?? "Cart"} (${cart.totalItemCount})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                ),
                if (cart.items.isNotEmpty)
                  GestureDetector(
                    onTap: () => ref.read(cartProvider.notifier).clearCart(),
                    child: Text(
                      l10n?.clearCart ?? 'CLEAR',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
                  ),
              ],
            ),
          ),

          // 4. Cart Items List
          const Expanded(
            child: CartItemList(),
          ),

          // 5. Thumb-Friendly Bottom Charge Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -3),
                  blurRadius: 6,
                ),
              ],
            ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: cart.items.isEmpty ? null : _showCheckoutModal,
                  child: Text(
                    '${l10n?.charge ?? "CHARGE"} (${CurrencyFormatter.format(cart.grandTotal, isAmharic: isAmharic)})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
