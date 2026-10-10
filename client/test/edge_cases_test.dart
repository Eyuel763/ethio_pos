import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/utils/formatters.dart';
import 'package:client/features/checkout/providers/cart_provider.dart';

void main() {
  const uuid = Uuid();
  late AppDatabase db;
  late ProviderContainer container;
  const shopId = '00000000-0000-0000-0000-000000000001';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('Flutter Client Edge-Cases & Hardening (Sub-Phase 5.2)', () {
    test('1. Cart & Currency Formatting Edge Cases (Fractional Quantities & Large Amounts)', () {
      // Currency formatter boundary checks
      expect(CurrencyFormatter.format(0.0, isAmharic: false), '0.00 ETB');
      expect(CurrencyFormatter.format(0.0, isAmharic: true), '0.00 ብር');
      expect(CurrencyFormatter.format(1250000.75, isAmharic: false), '1,250,000.75 ETB');
      expect(CurrencyFormatter.format(1250000.75, isAmharic: true), '1,250,000.75 ብር');

      final cartNotifier = container.read(cartProvider.notifier);

      final bulkTeff = ProductsTableData(
        id: 'prod-teff',
        shopId: shopId,
        nameAm: 'ማኛ ጤፍ በኪሎ',
        nameEn: 'Magna Teff per Kg',
        category: 'Groceries',
        unitType: 'kg',
        sellingPrice: 120.0,
        costPrice: 95.0,
        stockQuantity: 100.0,
        minStockLevel: 10.0,
        isDeleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Add item to cart
      cartNotifier.addProduct(bulkTeff);
      expect(container.read(cartProvider).subtotal, 120.0);

      // Fractional update (e.g. 2.75 kg weighed on scale)
      cartNotifier.setQuantity('prod-teff', 2.75);
      // 2.75 * 120.00 = 330.00 ETB
      expect(container.read(cartProvider).subtotal, 330.0);
      expect(container.read(cartProvider).items['prod-teff']!.quantity, 2.75);

      // Removing item drops subtotal back to 0
      cartNotifier.removeItem('prod-teff');
      expect(container.read(cartProvider).subtotal, 0.0);
      expect(container.read(cartProvider).items.isEmpty, isTrue);
    });

    test('2. Unicode & Ge\'ez Fidelity in Drift Outbox Serialization', () async {
      final amharicProdId = uuid.v4();
      const teffNameAm = 'የደብረ ማርቆስ ማኛ ጤፍ (ጥራት ያለው)';
      const teffNameEn = 'Debre Marqos Magna Teff (Premium)';

      // Insert product with complex Amharic script
      await db.upsertProduct(
        ProductsTableCompanion.insert(
          id: amharicProdId,
          shopId: shopId,
          nameAm: teffNameAm,
          nameEn: teffNameEn,
          sellingPrice: 140.0,
          stockQuantity: const drift.Value(50.0),
        ),
      );

      // Queue mutation with Amharic payload
      final payloadMap = {
        'id': amharicProdId,
        'name_am': teffNameAm,
        'name_en': teffNameEn,
        'note': 'በቅናሽ የተሸጠ የዐይነት ምርት',
      };

      await db.into(db.syncQueueTable).insert(
        SyncQueueTableCompanion.insert(
          entityType: 'product',
          entityId: amharicProdId,
          operation: 'CREATE',
          payload: jsonEncode(payloadMap),
        ),
      );

      // Retrieve and decode from SQLite outbox
      final pendingOps = await db.getPendingSyncOperations();
      expect(pendingOps.length, 1);
      final decodedPayload = jsonDecode(pendingOps.first.payload) as Map<String, dynamic>;

      // Assert perfect Unicode character fidelity (no question marks or Mojibake)
      expect(decodedPayload['name_am'], teffNameAm);
      expect(decodedPayload['note'], 'በቅናሽ የተሸጠ የዐይነት ምርት');
    });

    test('3. Negative Stock Tolerant Selling (Retail Rush Hour Guarantee)', () async {
      // In fast-paced Ethiopian retail shops, a cashier must be allowed to sell
      // stock even if the stock count reaches 0 before the shipment is entered in the app.
      final rushProdId = uuid.v4();
      await db.upsertProduct(
        ProductsTableCompanion.insert(
          id: rushProdId,
          shopId: shopId,
          nameAm: 'ዳቦ',
          nameEn: 'Fresh Bread',
          sellingPrice: 15.0,
          stockQuantity: const drift.Value(2.0), // Only 2 in stock
        ),
      );

      final saleId = uuid.v4();

      // Customer buys 5 breads (overselling by 3)
      await db.recordSaleAtomic(
        sale: SalesTableCompanion.insert(
          id: saleId,
          shopId: shopId,
          paymentType: 'cash',
          subtotal: 75.0,
          grandTotal: 75.0,
          amountPaid: 75.0,
          amountDue: 0.0,
        ),
        items: [
          SaleItemsTableCompanion.insert(
            id: uuid.v4(),
            saleId: saleId,
            productId: rushProdId,
            productName: 'Fresh Bread',
            unitPrice: 15.0,
            quantity: 5.0,
            totalPrice: 75.0,
          ),
        ],
        syncPayloadJson: '{"id": "$saleId"}',
      );

      // Stock should cleanly transition to -3 without SQLite crash
      final product = await db.getProductById(rushProdId);
      expect(product!.stockQuantity, -3.0);
    });

    test('4. Soft-Delete Integrity (Sales History Preserved When Item is Deleted)', () async {
      final discontinuedProdId = uuid.v4();
      await db.upsertProduct(
        ProductsTableCompanion.insert(
          id: discontinuedProdId,
          shopId: shopId,
          nameAm: 'የቆየ ምርት',
          nameEn: 'Old Discontinued Item',
          sellingPrice: 50.0,
          stockQuantity: const drift.Value(10.0),
        ),
      );

      final pastSaleId = uuid.v4();
      await db.recordSaleAtomic(
        sale: SalesTableCompanion.insert(
          id: pastSaleId,
          shopId: shopId,
          paymentType: 'cash',
          subtotal: 50.0,
          grandTotal: 50.0,
          amountPaid: 50.0,
          amountDue: 0.0,
        ),
        items: [
          SaleItemsTableCompanion.insert(
            id: uuid.v4(),
            saleId: pastSaleId,
            productId: discontinuedProdId,
            productName: 'Old Discontinued Item',
            unitPrice: 50.0,
            quantity: 1.0,
            totalPrice: 50.0,
          ),
        ],
        syncPayloadJson: '{"id": "$pastSaleId"}',
      );

      // Soft-delete the product
      await (db.update(db.productsTable)..where((tbl) => tbl.id.equals(discontinuedProdId)))
          .write(const ProductsTableCompanion(isDeleted: drift.Value(true)));

      // Active products stream excludes soft-deleted product
      final activeProducts = await db.watchAllProducts().first;
      expect(activeProducts.any((p) => p.id == discontinuedProdId), isFalse);

      // Past sale line items still reference the discontinued product name and ID
      final items = await db.getSaleItems(pastSaleId);
      expect(items.length, 1);
      expect(items.first.productId, discontinuedProdId);
      expect(items.first.productName, 'Old Discontinued Item');
    });
  });
}
