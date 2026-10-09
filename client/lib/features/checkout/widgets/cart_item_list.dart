import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/utils/formatters.dart';
import '../providers/cart_provider.dart';

class CartItemList extends ConsumerWidget {
  const CartItemList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;

    if (cart.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              isAmharic ? 'የተመረጡ ዕቃዎች የሉም' : 'Cart is empty',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final items = cart.itemList;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final displayName = isAmharic ? item.product.nameAm : item.product.nameEn;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      '${item.quantity} x ${CurrencyFormatter.format(item.customUnitPrice, isAmharic: isAmharic)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              Text(
                CurrencyFormatter.format(item.totalPrice, isAmharic: isAmharic),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(width: 8),
              // Quantity controls: - | + | delete
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    color: Colors.grey.shade700,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ref.read(cartProvider.notifier).decrementQuantity(item.product.id);
                    },
                  ),
                  Text(
                    '${item.quantity.toInt()}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    color: Theme.of(context).colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ref.read(cartProvider.notifier).addProduct(item.product);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ref.read(cartProvider.notifier).removeItem(item.product.id);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
