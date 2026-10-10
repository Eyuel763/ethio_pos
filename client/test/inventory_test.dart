import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/providers/database_providers.dart';
import 'package:client/features/inventory/providers/inventory_providers.dart';

void main() {
  group('Inventory Providers & Filtering Tests', () {
    final testProducts = [
      ProductsTableData(
        id: 'prod-oil',
        shopId: 'shop-1',
        barcode: '11112222',
        nameEn: '5L Cooking Oil',
        nameAm: 'ዘይት 5L',
        category: 'Groceries',
        unitType: 'piece',
        sellingPrice: 450.0,
        costPrice: 400.0,
        stockQuantity: 4.0, // Low stock (min is 5.0)
        minStockLevel: 5.0,
        isDeleted: false,
        createdAt: DateTime(2026, 10, 6),
        updatedAt: DateTime(2026, 10, 6),
      ),
      ProductsTableData(
        id: 'prod-sugar',
        shopId: 'shop-1',
        barcode: '33334444',
        nameEn: 'Sugar 1kg',
        nameAm: 'ስኳር 1ኪ.ግ',
        category: 'Groceries',
        unitType: 'kg',
        sellingPrice: 120.0,
        costPrice: 100.0,
        stockQuantity: 0.0, // Out of stock
        minStockLevel: 10.0,
        isDeleted: false,
        createdAt: DateTime(2026, 10, 6),
        updatedAt: DateTime(2026, 10, 6),
      ),
      ProductsTableData(
        id: 'prod-injera',
        shopId: 'shop-1',
        barcode: null,
        nameEn: 'Injera',
        nameAm: 'እንጀራ',
        category: 'Bakery',
        unitType: 'piece',
        sellingPrice: 15.0,
        costPrice: 12.0,
        stockQuantity: 35.0, // Normal stock
        minStockLevel: 10.0,
        isDeleted: false,
        createdAt: DateTime(2026, 10, 6),
        updatedAt: DateTime(2026, 10, 6),
      ),
    ];

    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          productsStreamProvider.overrideWith((ref) => Stream.value(testProducts)),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('calculates inventory metrics accurately', () async {
      container.listen(productsStreamProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final metrics = container.read(inventoryMetricsProvider);
      expect(metrics.totalCount, 3);
      expect(metrics.lowStockCount, 1); // Oil (4 <= 5)
      expect(metrics.outOfStockCount, 1); // Sugar (0 <= 0)

      // Total Value = (4 * 450) + (0 * 120) + (35 * 15) = 1800 + 0 + 525 = 2325.0
      expect(metrics.totalStockValue, 2325.0);
    });

    test('filters products by stock status (All, Low Stock, Out of Stock)', () async {
      container.listen(productsStreamProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 1. All Items: out of stock & low stock sorted first
      final all = container.read(filteredInventoryProductsProvider);
      expect(all.length, 3);
      expect(all[0].id, 'prod-sugar'); // out of stock first
      expect(all[1].id, 'prod-oil');   // low stock second
      expect(all[2].id, 'prod-injera'); // normal stock third

      // 2. Low Stock filter
      container.read(inventoryStockFilterProvider.notifier).setFilter(StockFilter.lowStock);
      final low = container.read(filteredInventoryProductsProvider);
      expect(low.length, 1);
      expect(low.first.id, 'prod-oil');

      // 3. Out of Stock filter
      container.read(inventoryStockFilterProvider.notifier).setFilter(StockFilter.outOfStock);
      final out = container.read(filteredInventoryProductsProvider);
      expect(out.length, 1);
      expect(out.first.id, 'prod-sugar');
    });

    test('searches products by English, Amharic name, and Barcode', () async {
      container.listen(productsStreamProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Search by English
      container.read(inventorySearchQueryProvider.notifier).setQuery('injera');
      var results = container.read(filteredInventoryProductsProvider);
      expect(results.length, 1);
      expect(results.first.nameEn, 'Injera');

      // Search by Amharic
      container.read(inventorySearchQueryProvider.notifier).setQuery('ዘይት');
      results = container.read(filteredInventoryProductsProvider);
      expect(results.length, 1);
      expect(results.first.nameEn, '5L Cooking Oil');

      // Search by Barcode
      container.read(inventorySearchQueryProvider.notifier).setQuery('3333');
      results = container.read(filteredInventoryProductsProvider);
      expect(results.length, 1);
      expect(results.first.id, 'prod-sugar');
    });
  });

  group('Inventory Database Operations Tests', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.upsertProduct(
        ProductsTableCompanion.insert(
          id: 'prod-oil',
          shopId: 'shop-1',
          nameEn: '5L Cooking Oil',
          nameAm: 'ዘይት 5L',
          sellingPrice: 450.0,
          stockQuantity: const drift.Value(4.0),
          minStockLevel: const drift.Value(5.0),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('adjustStockAtomic updates stock quantity and logs to sync queue', () async {
      await db.adjustStockAtomic(
        productId: 'prod-oil',
        newQuantity: 14.0,
        syncPayloadJson: '{"id": "prod-oil", "stock_quantity": 14.0, "stock_delta": 10.0}',
      );

      final updated = await db.getProductById('prod-oil');
      expect(updated, isNotNull);
      expect(updated!.stockQuantity, 14.0);

      final pending = await db.getPendingSyncOperations();
      expect(pending.length, 1);
      expect(pending.first.entityType, 'product');
      expect(pending.first.operation, 'UPDATE');
      expect(pending.first.entityId, 'prod-oil');
    });

    test('upsertProductAtomic creates new product and records sync mutation', () async {
      final newProd = ProductsTableCompanion.insert(
        id: 'prod-bread',
        shopId: 'shop-1',
        nameEn: 'Special Bread',
        nameAm: 'ልዩ ዳቦ',
        sellingPrice: 20.0,
        stockQuantity: const drift.Value(50.0),
      );

      await db.upsertProductAtomic(
        product: newProd,
        operation: 'CREATE',
        syncPayloadJson: '{"id": "prod-bread", "name_en": "Special Bread"}',
      );

      final retrieved = await db.getProductById('prod-bread');
      expect(retrieved, isNotNull);
      expect(retrieved!.nameEn, 'Special Bread');
      expect(retrieved.stockQuantity, 50.0);

      final pending = await db.getPendingSyncOperations();
      expect(pending.length, 1);
      expect(pending.first.entityType, 'product');
      expect(pending.first.operation, 'CREATE');
      expect(pending.first.entityId, 'prod-bread');
    });
  });
}
