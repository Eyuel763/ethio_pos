import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';

/// Singleton provider for the Drift AppDatabase instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Stream provider for reactive product catalog updates across the app.
final productsStreamProvider = StreamProvider<List<ProductsTableData>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllProducts();
});

/// Stream provider for low-stock alerts.
final lowStockProductsStreamProvider = StreamProvider<List<ProductsTableData>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchLowStockProducts();
});

/// Stream provider for all customer credit ledger entries.
final customersStreamProvider = StreamProvider<List<CustomersTableData>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllCustomers();
});
