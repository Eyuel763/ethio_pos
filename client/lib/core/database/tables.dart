import 'package:drift/drift.dart';

/// Products table storing catalog, pricing, barcodes, and local stock quantities.
class ProductsTable extends Table {
  @override
  String get tableName => 'products';

  // Client-generated UUID (v4)
  TextColumn get id => text()();

  // Multi-tenant shop identifier
  TextColumn get shopId => text().named('shop_id')();

  // Scannable manufacturer barcode (EAN-13, UPC)
  TextColumn get barcode => text().nullable()();

  // Bilingual names
  TextColumn get nameAm => text().named('name_am')();
  TextColumn get nameEn => text().named('name_en')();

  // Category classification (e.g. Groceries, Fresh, Spices)
  TextColumn get category => text().withDefault(const Constant('General'))();

  // Unit of measure: piece, kg, liter, packet, bundle
  TextColumn get unitType => text().named('unit_type').withDefault(const Constant('piece'))();

  // Pricing in ETB (stored as Real / double in SQLite)
  RealColumn get sellingPrice => real().named('selling_price')();
  RealColumn get costPrice => real().named('cost_price').withDefault(const Constant(0.0))();

  // Stock inventory tracking
  RealColumn get stockQuantity => real().named('stock_quantity').withDefault(const Constant(0.0))();
  RealColumn get minStockLevel => real().named('min_stock_level').withDefault(const Constant(5.0))();

  // Soft delete flag for reliable offline sync
  BoolColumn get isDeleted => boolean().named('is_deleted').withDefault(const Constant(false))();

  // Timestamps
  DateTimeColumn get createdAt => dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Customers table for credit ledger patrons (ዕዳ).
class CustomersTable extends Table {
  @override
  String get tableName => 'customers';

  // Client-generated UUID (v4)
  TextColumn get id => text()();

  TextColumn get shopId => text().named('shop_id')();
  TextColumn get fullName => text().named('full_name')();
  TextColumn get phoneNumber => text().named('phone_number').nullable()();

  // Outstanding debt balance in ETB
  RealColumn get totalDebt => real().named('total_debt').withDefault(const Constant(0.0))();

  BoolColumn get isDeleted => boolean().named('is_deleted').withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Sales table storing finalized transaction headers.
class SalesTable extends Table {
  @override
  String get tableName => 'sales';

  // Client-generated UUID (v4)
  TextColumn get id => text()();

  TextColumn get shopId => text().named('shop_id')();
  TextColumn get customerId => text().named('customer_id').nullable()();

  // Payment type: 'cash', 'mobile_transfer', 'credit'
  TextColumn get paymentType => text().named('payment_type')();

  RealColumn get subtotal => real()();
  RealColumn get discount => real().withDefault(const Constant(0.0))();
  RealColumn get grandTotal => real().named('grand_total')();
  RealColumn get amountPaid => real().named('amount_paid')();
  RealColumn get amountDue => real().named('amount_due')();

  DateTimeColumn get createdAt => dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Line items associated with each sale transaction.
class SaleItemsTable extends Table {
  @override
  String get tableName => 'sale_items';

  // Client-generated UUID (v4)
  TextColumn get id => text()();

  TextColumn get saleId => text().named('sale_id')();
  TextColumn get productId => text().named('product_id')();
  TextColumn get productName => text().named('product_name')();

  RealColumn get unitPrice => real().named('unit_price')();
  RealColumn get quantity => real()();
  RealColumn get totalPrice => real().named('total_price')();

  @override
  Set<Column> get primaryKey => {id};
}

/// Customer debt repayments table (ዕዳ ክፍያ).
class DebtRepaymentsTable extends Table {
  @override
  String get tableName => 'debt_repayments';

  // Client-generated UUID (v4)
  TextColumn get id => text()();

  TextColumn get shopId => text().named('shop_id')();
  TextColumn get customerId => text().named('customer_id')();
  RealColumn get amount => real()();
  TextColumn get paymentMethod => text().named('payment_method').withDefault(const Constant('cash'))();
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime().named('created_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local Outbox Queue table for background synchronization.
class SyncQueueTable extends Table {
  @override
  String get tableName => 'sync_queue';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text().named('entity_type')(); // 'product', 'customer', 'sale', 'debt_repayment'
  TextColumn get entityId => text().named('entity_id')();
  TextColumn get operation => text()(); // 'CREATE', 'UPDATE', 'DELETE'
  TextColumn get payload => text()(); // JSON string
  TextColumn get status => text().withDefault(const Constant('PENDING'))(); // 'PENDING', 'SYNCING', 'FAILED'
  IntColumn get retryCount => integer().named('retry_count').withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().named('created_at').withDefault(currentDateAndTime)();
}
