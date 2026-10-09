import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/utils/formatters.dart';
import '../providers/cart_provider.dart';

class QuickKeysGrid extends ConsumerWidget {
  final List<ProductsTableData> products;

  const QuickKeysGrid({
    super.key,
    required this.products,
  });

  // Category tile accent colors
  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'groceries':
        return const Color(0xFFE8F5E9); // Light green
      case 'fresh':
      case 'produce':
        return const Color(0xFFFFF3E0); // Light orange
      case 'bakery':
        return const Color(0xFFEFEBE9); // Light brown
      case 'spices':
        return const Color(0xFFFFEBEE); // Light red
      default:
        return const Color(0xFFE3F2FD); // Light blue
    }
  }

  Color _getBorderColor(String category) {
    switch (category.toLowerCase()) {
      case 'groceries':
        return const Color(0xFF81C784);
      case 'fresh':
      case 'produce':
        return const Color(0xFFFFB74D);
      case 'bakery':
        return const Color(0xFFA1887F);
      case 'spices':
        return const Color(0xFFE57373);
      default:
        return const Color(0xFF64B5F6);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;

    if (products.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: Text(
          isAmharic ? 'ዕቃዎች አልተገኙም' : 'No products found',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final p = products[index];
          final bgColor = _getCategoryColor(p.category);
          final borderColor = _getBorderColor(p.category);
          final displayName = isAmharic ? p.nameAm : p.nameEn;

          return InkWell(
            onTap: () {
              ref.read(cartProvider.notifier).addProduct(p);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 105,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        CurrencyFormatter.format(p.sellingPrice, isAmharic: isAmharic),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${p.stockQuantity.toStringAsFixed(0)} ${p.unitType}',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
