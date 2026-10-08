import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  ProductsTable,
  CustomersTable,
  SalesTable,
  SaleItemsTable,
  DebtRepaymentsTable,
  SyncQueueTable,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
      );

  // -------------------------------------------------------------
  // PRODUCTS QUERIES & OPERATIONS
  // -------------------------------------------------------------

  Stream<List<ProductsTableData>> watchAllProducts() {
    return (select(productsTable)
          ..where((tbl) => tbl.isDeleted.equals(false))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.nameEn)]))
        .watch();
  }

  Future<ProductsTableData?> getProductByBarcode(String barcode) {
    return (select(productsTable)
          ..where((tbl) => tbl.barcode.equals(barcode) & tbl.isDeleted.equals(false))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<ProductsTableData?> getProductById(String id) {
    return (select(productsTable)
          ..where((tbl) => tbl.id.equals(id) & tbl.isDeleted.equals(false))
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<List<ProductsTableData>> watchLowStockProducts() {
    return (select(productsTable)
          ..where((tbl) =>
              tbl.isDeleted.equals(false) &
              tbl.stockQuantity.isSmallerOrEqual(tbl.minStockLevel)))
        .watch();
  }

  Future<void> upsertProduct(ProductsTableCompanion product) {
    return into(productsTable).insertOnConflictUpdate(product);
  }

  // -------------------------------------------------------------
  // CUSTOMERS & LEDGER QUERIES & OPERATIONS
  // -------------------------------------------------------------

  Stream<List<CustomersTableData>> watchAllCustomers() {
    return (select(customersTable)
          ..where((tbl) => tbl.isDeleted.equals(false))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.fullName)]))
        .watch();
  }

  Future<CustomersTableData?> getCustomerById(String id) {
    return (select(customersTable)
          ..where((tbl) => tbl.id.equals(id) & tbl.isDeleted.equals(false))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> upsertCustomer(CustomersTableCompanion customer) {
    return into(customersTable).insertOnConflictUpdate(customer);
  }

  // -------------------------------------------------------------
  // SALES & LEDGER TRANSACTIONS (ATOMIC WRITES)
  // -------------------------------------------------------------

  /// Records a complete sale atomically inside a Drift transaction:
  /// 1. Inserts the Sale row
  /// 2. Inserts all Line Items
  /// 3. Decrements local inventory stock quantities
  /// 4. If credit, updates customer total debt
  /// 5. Enqueues a sync operation into sync_queue
  Future<void> recordSaleAtomic({
    required SalesTableCompanion sale,
    required List<SaleItemsTableCompanion> items,
    required String syncPayloadJson,
  }) {
    return transaction(() async {
      // 1. Insert Sale header
      await into(salesTable).insert(sale);

      // 2. Insert Sale line items & decrement product stock
      for (final item in items) {
        await into(saleItemsTable).insert(item);

        final product = await getProductById(item.productId.value);
        if (product != null) {
          final newQty = product.stockQuantity - item.quantity.value;
          await (update(productsTable)..where((tbl) => tbl.id.equals(product.id)))
              .write(ProductsTableCompanion(
            stockQuantity: Value(newQty),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }

      // 3. If credit sale, update customer balance
      final customerId = sale.customerId.value;
      final amountDue = sale.amountDue.value;
      if (customerId != null && amountDue > 0) {
        final customer = await getCustomerById(customerId);
        if (customer != null) {
          final newDebt = customer.totalDebt + amountDue;
          await (update(customersTable)..where((tbl) => tbl.id.equals(customerId)))
              .write(CustomersTableCompanion(
            totalDebt: Value(newDebt),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }

      // 4. Enqueue into sync_queue
      await into(syncQueueTable).insert(
        SyncQueueTableCompanion.insert(
          entityType: 'sale',
          entityId: sale.id.value,
          operation: 'CREATE',
          payload: syncPayloadJson,
        ),
      );
    });
  }

  /// Records a customer repayment atomically:
  /// 1. Inserts the Repayment row
  /// 2. Decrements customer total debt
  /// 3. Enqueues mutation into sync_queue
  Future<void> recordRepaymentAtomic({
    required DebtRepaymentsTableCompanion repayment,
    required String syncPayloadJson,
  }) {
    return transaction(() async {
      await into(debtRepaymentsTable).insert(repayment);

      final customerId = repayment.customerId.value;
      final amount = repayment.amount.value;
      final customer = await getCustomerById(customerId);
      if (customer != null) {
        final newDebt = (customer.totalDebt - amount).clamp(0.0, double.infinity);
        await (update(customersTable)..where((tbl) => tbl.id.equals(customerId)))
            .write(CustomersTableCompanion(
          totalDebt: Value(newDebt),
          updatedAt: Value(DateTime.now()),
        ));
      }

      await into(syncQueueTable).insert(
        SyncQueueTableCompanion.insert(
          entityType: 'debt_repayment',
          entityId: repayment.id.value,
          operation: 'CREATE',
          payload: syncPayloadJson,
        ),
      );
    });
  }

  /// Adjusts stock quantity atomically and logs mutation to sync_queue:
  Future<void> adjustStockAtomic({
    required String productId,
    required double newQuantity,
    required String syncPayloadJson,
  }) {
    return transaction(() async {
      await (update(productsTable)..where((tbl) => tbl.id.equals(productId)))
          .write(ProductsTableCompanion(
        stockQuantity: Value(newQuantity),
        updatedAt: Value(DateTime.now()),
      ));

      await into(syncQueueTable).insert(
        SyncQueueTableCompanion.insert(
          entityType: 'product',
          entityId: productId,
          operation: 'UPDATE',
          payload: syncPayloadJson,
        ),
      );
    });
  }

  /// Retrieves all credit sales recorded for a specific customer
  Future<List<SalesTableData>> getCustomerSales(String customerId) {
    return (select(salesTable)
          ..where((tbl) => tbl.customerId.equals(customerId))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .get();
  }

  /// Retrieves itemized products for a specific sale
  Future<List<SaleItemsTableData>> getSaleItems(String saleId) {
    return (select(saleItemsTable)
          ..where((tbl) => tbl.saleId.equals(saleId)))
        .get();
  }

  /// Retrieves repayments for a customer
  Future<List<DebtRepaymentsTableData>> getCustomerRepayments(String customerId) {
    return (select(debtRepaymentsTable)
          ..where((tbl) => tbl.customerId.equals(customerId))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .get();
  }

  // -------------------------------------------------------------
  // SYNC QUEUE OUTBOX OPERATIONS
  // -------------------------------------------------------------

  Future<List<SyncQueueTableData>> getPendingSyncOperations({int limit = 50}) {
    return (select(syncQueueTable)
          ..where((tbl) => tbl.status.equals('PENDING'))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.id)])
          ..limit(limit))
        .get();
  }

  Future<void> markSyncStatus(List<int> ids, String status) {
    return (update(syncQueueTable)..where((tbl) => tbl.id.isIn(ids)))
        .write(SyncQueueTableCompanion(status: Value(status)));
  }

  Future<void> removeAcknowledgedSync(List<int> ids) {
    return (delete(syncQueueTable)..where((tbl) => tbl.id.isIn(ids))).go();
  }

  Future<void> incrementSyncRetry(int id) {
    return customUpdate(
      'UPDATE sync_queue SET retry_count = retry_count + 1, status = ? WHERE id = ?',
      variables: [Variable.withString('FAILED'), Variable.withInt(id)],
      updates: {syncQueueTable},
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'ethio_pos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
