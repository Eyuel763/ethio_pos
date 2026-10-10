import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/providers/locale_provider.dart';
import 'package:client/core/utils/formatters.dart';
import 'package:client/l10n/app_localizations.dart';
import '../providers/cart_provider.dart';

class ProductCatalogList extends ConsumerStatefulWidget {
  final List<ProductsTableData> products;

  const ProductCatalogList({
    super.key,
    required this.products,
  });

  @override
  ConsumerState<ProductCatalogList> createState() => _ProductCatalogListState();
}

class _ProductCatalogListState extends ConsumerState<ProductCatalogList> {
  String _selectedCategory = 'All';

  // Category visual helper
  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'groceries':
      case 'grocery':
        return Icons.shopping_bag_outlined;
      case 'fresh':
      case 'produce':
        return Icons.eco_outlined;
      case 'bakery':
        return Icons.bakery_dining_outlined;
      case 'spices':
      case 'spice':
        return Icons.soup_kitchen_outlined;
      case 'beverages':
      case 'drinks':
        return Icons.local_drink_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'groceries':
      case 'grocery':
        return const Color(0xFF2E7D32); // Green
      case 'fresh':
      case 'produce':
        return const Color(0xFFE65100); // Deep Orange
      case 'bakery':
        return const Color(0xFF8D6E63); // Brown
      case 'spices':
      case 'spice':
        return const Color(0xFFC62828); // Red
      case 'beverages':
      case 'drinks':
        return const Color(0xFF0277BD); // Blue
      default:
        return const Color(0xFF546E7A); // Blue-grey
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);

    // Extract unique categories
    final categories = <String>{'All'};
    for (final p in widget.products) {
      if (p.category.isNotEmpty) categories.add(p.category);
    }
    final categoryList = categories.toList();

    // Filter by selected category
    final filteredProducts = _selectedCategory == 'All'
        ? widget.products
        : widget.products
            .where((p) => p.category.toLowerCase() == _selectedCategory.toLowerCase())
            .toList();

    return Column(
      children: [
        // Horizontal Category Filter Chips
        if (categoryList.length > 2)
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: categoryList.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = categoryList[index];
                final isSelected = _selectedCategory == cat;
                final catLabel = cat == 'All' ? (l10n?.allCategories ?? 'All') : cat;

                return ChoiceChip(
                  label: Text(
                    catLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : Colors.grey.shade800,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: theme.colorScheme.primary,
                  backgroundColor: Colors.grey.shade100,
                  side: BorderSide(
                    color: isSelected ? theme.colorScheme.primary : Colors.grey.shade300,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedCategory = cat);
                    }
                  },
                );
              },
            ),
          ),

        const SizedBox(height: 4),

        // Scrollable List of Products
        Expanded(
          child: filteredProducts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        isAmharic ? 'ምንም ዕቃ አልተገኘም' : 'No products found',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: filteredProducts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final p = filteredProducts[index];
                    final displayName = isAmharic
                        ? (p.nameAm.isNotEmpty ? p.nameAm : p.nameEn)
                        : (p.nameEn.isNotEmpty ? p.nameEn : p.nameAm);
                    final secondaryName = isAmharic ? p.nameEn : p.nameAm;

                    final cartItem = cart.items[p.id];
                    final inCartQty = cartItem?.quantity ?? 0.0;
                    final isInCart = inCartQty > 0;

                    final catColor = _getCategoryColor(p.category);
                    final catIcon = _getCategoryIcon(p.category);

                    final isOutOfStock = p.stockQuantity <= 0;
                    final isLowStock = p.stockQuantity > 0 && p.stockQuantity <= p.minStockLevel;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isInCart
                              ? theme.colorScheme.primary.withValues(alpha: 0.5)
                              : Colors.grey.shade200,
                          width: isInCart ? 1.5 : 1,
                        ),
                      ),
                      color: isInCart
                          ? theme.colorScheme.primary.withValues(alpha: 0.04)
                          : Colors.white,
                      child: InkWell(
                        onTap: () {
                          ref.read(cartProvider.notifier).addProduct(p);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              // Category Avatar
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: catColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(catIcon, color: catColor, size: 24),
                              ),
                              const SizedBox(width: 12),

                              // Name, Price & Stock info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (secondaryName.isNotEmpty && secondaryName != displayName)
                                      Text(
                                        secondaryName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        // Selling Price
                                        Text(
                                          CurrencyFormatter.format(p.sellingPrice, isAmharic: isAmharic),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // Stock status badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isOutOfStock
                                                ? Colors.red.shade50
                                                : (isLowStock ? Colors.orange.shade50 : Colors.grey.shade100),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isOutOfStock
                                                ? (l10n?.outOfStock ?? 'Out of stock')
                                                : '${p.stockQuantity.toStringAsFixed(0)} ${p.unitType}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isOutOfStock
                                                  ? Colors.red.shade700
                                                  : (isLowStock ? Colors.orange.shade800 : Colors.grey.shade700),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              // Trailing Cart Controls / Add Button
                              if (isInCart)
                                Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove, size: 16),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          ref.read(cartProvider.notifier).decrementQuantity(p.id);
                                        },
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: Text(
                                          '${inCartQty.toInt()}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add, size: 16),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          ref.read(cartProvider.notifier).addProduct(p);
                                        },
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ElevatedButton.icon(
                                  onPressed: () {
                                    ref.read(cartProvider.notifier).addProduct(p);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: Text(
                                    l10n?.addToCart ?? 'Add',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
