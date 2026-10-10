import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:client/core/database/app_database.dart';
import 'package:client/features/checkout/providers/cart_provider.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('FR-2.1 Barcode Scanning & Product Lookup Logic', () {
    test('should resolve product by EAN-13 barcode and add directly to cart', () async {
      const barcode = '6281006561021';
      final productCompanion = ProductsTableCompanion.insert(
        id: 'prod-oil-ean',
        shopId: 'shop-1',
        nameAm: 'ዘይት 5L',
        nameEn: 'Sunflower Oil 5L',
        barcode: const drift.Value(barcode),
        sellingPrice: 450.0,
        stockQuantity: const drift.Value(25.0),
      );

      await db.upsertProduct(productCompanion);

      // Verify barcode query directly simulates camera scanner lookup
      final scannedProduct = await db.getProductByBarcode(barcode);
      expect(scannedProduct, isNotNull);
      expect(scannedProduct!.id, 'prod-oil-ean');
      expect(scannedProduct.barcode, barcode);

      // Add to cart upon detection
      container.read(cartProvider.notifier).addProduct(scannedProduct);
      expect(container.read(cartProvider).totalItemCount, 1);
      expect(container.read(cartProvider).subtotal, 450.0);
      expect(container.read(cartProvider).items.values.first.product.barcode, barcode);

      // Continuous scanning of the same item increments quantity
      container.read(cartProvider.notifier).addProduct(scannedProduct);
      expect(container.read(cartProvider).totalItemCount, 2);
      expect(container.read(cartProvider).subtotal, 900.0);
    });

    test('should return null when unknown barcode is scanned and leave cart intact', () async {
      const unknownBarcode = '9999999999999';

      final scannedProduct = await db.getProductByBarcode(unknownBarcode);
      expect(scannedProduct, isNull);
      expect(container.read(cartProvider).items.isEmpty, isTrue);
    });
  });
}
