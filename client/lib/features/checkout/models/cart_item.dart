import '../../../core/database/app_database.dart';

class CartItem {
  final ProductsTableData product;
  final double quantity;
  final double customUnitPrice;

  const CartItem({
    required this.product,
    required this.quantity,
    required this.customUnitPrice,
  });

  double get totalPrice => quantity * customUnitPrice;

  CartItem copyWith({
    ProductsTableData? product,
    double? quantity,
    double? customUnitPrice,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      customUnitPrice: customUnitPrice ?? this.customUnitPrice,
    );
  }
}

class CartState {
  final Map<String, CartItem> items; // Keyed by productId
  final double discount;

  const CartState({
    this.items = const {},
    this.discount = 0.0,
  });

  List<CartItem> get itemList => items.values.toList();
  int get totalItemCount => items.values.fold(0, (sum, i) => sum + i.quantity.toInt());

  double get subtotal => items.values.fold(0.0, (sum, item) => sum + item.totalPrice);
  double get grandTotal => (subtotal - discount).clamp(0.0, double.infinity);

  CartState copyWith({
    Map<String, CartItem>? items,
    double? discount,
  }) {
    return CartState(
      items: items ?? this.items,
      discount: discount ?? this.discount,
    );
  }
}
