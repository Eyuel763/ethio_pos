import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:client/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // In-memory sqlite database for fast, isolated tests
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('should insert product and retrieve by barcode', () async {
    const prodId = 'prod-1';
    await db.upsertProduct(
      ProductsTableCompanion.insert(
        id: prodId,
        shopId: 'shop-1',
        nameAm: 'ዘይት 5L',
        nameEn: '5L Oil',
        sellingPrice: 450.0,
        barcode: const drift.Value('123456789012'),
        stockQuantity: const drift.Value(15.0),
      ),
    );

    final product = await db.getProductByBarcode('123456789012');
    expect(product, isNotNull);
    expect(product!.nameEn, '5L Oil');
    expect(product.sellingPrice, 450.0);
    expect(product.stockQuantity, 15.0);
  });

  test('should record sale atomically, decrement stock, update credit balance, and enqueue sync', () async {
    const prodId = 'prod-oil';
    const custId = 'cust-kebede';
    const saleId = 'sale-101';

    // 1. Seed Product
    await db.upsertProduct(
      ProductsTableCompanion.insert(
        id: prodId,
        shopId: 'shop-1',
        nameAm: 'ዘይት',
        nameEn: 'Cooking Oil',
        sellingPrice: 450.0,
        stockQuantity: const drift.Value(10.0),
      ),
    );

    // 2. Seed Customer
    await db.upsertCustomer(
      CustomersTableCompanion.insert(
        id: custId,
        shopId: 'shop-1',
        fullName: 'Kebede Tadesse',
        totalDebt: const drift.Value(100.0),
      ),
    );

    // 3. Record Sale atomically: 2 oils bought on credit (paid 100, due 800)
    await db.recordSaleAtomic(
      sale: SalesTableCompanion.insert(
        id: saleId,
        shopId: 'shop-1',
        customerId: const drift.Value(custId),
        paymentType: 'credit',
        subtotal: 900.0,
        grandTotal: 900.0,
        amountPaid: 100.0,
        amountDue: 800.0,
      ),
      items: [
        SaleItemsTableCompanion.insert(
          id: 'item-1',
          saleId: saleId,
          productId: prodId,
          productName: 'Cooking Oil',
          unitPrice: 450.0,
          quantity: 2.0,
          totalPrice: 900.0,
        ),
      ],
      syncPayloadJson: '{"entity_type": "sale", "entity_id": "$saleId"}',
    );

    // Verify product stock decremented: 10 - 2 = 8
    final updatedProduct = await db.getProductById(prodId);
    expect(updatedProduct!.stockQuantity, 8.0);

    // Verify customer debt incremented: 100 + 800 = 900
    final updatedCustomer = await db.getCustomerById(custId);
    expect(updatedCustomer!.totalDebt, 900.0);

    // Verify sync outbox queue has 1 pending operation
    final pendingSync = await db.getPendingSyncOperations();
    expect(pendingSync.length, 1);
    expect(pendingSync.first.entityId, saleId);
    expect(pendingSync.first.status, 'PENDING');
  });

  test('should record repayment atomically, decrement debt, and enqueue sync', () async {
    const custId = 'cust-almaz';
    const repId = 'rep-501';

    // Seed Customer with 500 ETB debt
    await db.upsertCustomer(
      CustomersTableCompanion.insert(
        id: custId,
        shopId: 'shop-1',
        fullName: 'Almaz Ayana',
        totalDebt: const drift.Value(500.0),
      ),
    );

    // Repay 200 ETB
    await db.recordRepaymentAtomic(
      repayment: DebtRepaymentsTableCompanion.insert(
        id: repId,
        shopId: 'shop-1',
        customerId: custId,
        amount: 200.0,
        paymentMethod: const drift.Value('telebirr'),
      ),
      syncPayloadJson: '{"entity_type": "debt_repayment", "entity_id": "$repId"}',
    );

    // Verify balance: 500 - 200 = 300
    final updatedCustomer = await db.getCustomerById(custId);
    expect(updatedCustomer!.totalDebt, 300.0);

    // Verify sync outbox queue
    final pendingSync = await db.getPendingSyncOperations();
    expect(pendingSync.length, 1);
    expect(pendingSync.first.entityId, repId);
  });
}
