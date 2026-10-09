import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../models/cart_item.dart';

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  /// Adds a product to the cart (or increments quantity if already in cart)
  void addProduct(ProductsTableData product, {double quantity = 1.0, double? customPrice}) {
    final currentItems = Map<String, CartItem>.from(state.items);
    final unitPrice = customPrice ?? product.sellingPrice;

    if (currentItems.containsKey(product.id)) {
      final existing = currentItems[product.id]!;
      currentItems[product.id] = existing.copyWith(
        quantity: existing.quantity + quantity,
        customUnitPrice: customPrice ?? existing.customUnitPrice,
      );
    } else {
      currentItems[product.id] = CartItem(
        product: product,
        quantity: quantity,
        customUnitPrice: unitPrice,
      );
    }

    state = state.copyWith(items: currentItems);
  }

  /// Decrements product quantity or removes if quantity reaches 0
  void decrementQuantity(String productId) {
    final currentItems = Map<String, CartItem>.from(state.items);
    if (!currentItems.containsKey(productId)) return;

    final existing = currentItems[productId]!;
    if (existing.quantity > 1) {
      currentItems[productId] = existing.copyWith(quantity: existing.quantity - 1);
    } else {
      currentItems.remove(productId);
    }

    state = state.copyWith(items: currentItems);
  }

  /// Explicitly sets quantity (e.g. for fractional/kg items)
  void setQuantity(String productId, double quantity) {
    final currentItems = Map<String, CartItem>.from(state.items);
    if (!currentItems.containsKey(productId)) return;

    if (quantity <= 0) {
      currentItems.remove(productId);
    } else {
      currentItems[productId] = currentItems[productId]!.copyWith(quantity: quantity);
    }

    state = state.copyWith(items: currentItems);
  }

  /// Removes an item completely from the cart
  void removeItem(String productId) {
    final currentItems = Map<String, CartItem>.from(state.items);
    currentItems.remove(productId);
    state = state.copyWith(items: currentItems);
  }

  /// Applies optional order-level discount in ETB
  void setDiscount(double discount) {
    state = state.copyWith(discount: discount);
  }

  /// Clears the entire cart
  void clearCart() {
    state = const CartState();
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
