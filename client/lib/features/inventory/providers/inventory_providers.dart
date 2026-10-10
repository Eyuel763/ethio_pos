import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/providers/database_providers.dart';

enum StockFilter { all, lowStock, outOfStock }

class InventorySearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
}

final inventorySearchQueryProvider =
    NotifierProvider<InventorySearchQueryNotifier, String>(
  InventorySearchQueryNotifier.new,
);

class InventoryStockFilterNotifier extends Notifier<StockFilter> {
  @override
  StockFilter build() => StockFilter.all;

  void setFilter(StockFilter filter) => state = filter;
}

final inventoryStockFilterProvider =
    NotifierProvider<InventoryStockFilterNotifier, StockFilter>(
  InventoryStockFilterNotifier.new,
);

class InventoryCategoryFilterNotifier extends Notifier<String> {
  @override
  String build() => 'All';

  void setCategory(String category) => state = category;
}

final inventoryCategoryFilterProvider =
    NotifierProvider<InventoryCategoryFilterNotifier, String>(
  InventoryCategoryFilterNotifier.new,
);

class InventoryMetrics {
  final int totalCount;
  final int lowStockCount;
  final int outOfStockCount;
  final double totalStockValue;

  const InventoryMetrics({
    required this.totalCount,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.totalStockValue,
  });
}

final inventoryMetricsProvider = Provider<InventoryMetrics>((ref) {
  final productsAsync = ref.watch(productsStreamProvider);

  return productsAsync.maybeWhen(
    data: (products) {
      int lowStock = 0;
      int outOfStock = 0;
      double totalValue = 0.0;

      for (final p in products) {
        if (p.stockQuantity <= 0) {
          outOfStock++;
        } else if (p.stockQuantity <= p.minStockLevel) {
          lowStock++;
        }
        totalValue += (p.stockQuantity * p.sellingPrice);
      }

      return InventoryMetrics(
        totalCount: products.length,
        lowStockCount: lowStock,
        outOfStockCount: outOfStock,
        totalStockValue: totalValue,
      );
    },
    orElse: () => const InventoryMetrics(
      totalCount: 0,
      lowStockCount: 0,
      outOfStockCount: 0,
      totalStockValue: 0.0,
    ),
  );
});

final filteredInventoryProductsProvider =
    Provider<List<ProductsTableData>>((ref) {
  final productsAsync = ref.watch(productsStreamProvider);
  final query = ref.watch(inventorySearchQueryProvider).trim().toLowerCase();
  final stockFilter = ref.watch(inventoryStockFilterProvider);
  final categoryFilter = ref.watch(inventoryCategoryFilterProvider);

  return productsAsync.maybeWhen(
    data: (products) {
      final filtered = products.where((p) {
        // 1. Text / barcode search
        if (query.isNotEmpty) {
          final enMatch = p.nameEn.toLowerCase().contains(query);
          final amMatch = p.nameAm.toLowerCase().contains(query);
          final barcodeMatch = p.barcode?.toLowerCase().contains(query) ?? false;
          if (!enMatch && !amMatch && !barcodeMatch) return false;
        }

        // 2. Stock level filter
        switch (stockFilter) {
          case StockFilter.all:
            break;
          case StockFilter.lowStock:
            if (!(p.stockQuantity > 0 && p.stockQuantity <= p.minStockLevel)) {
              return false;
            }
            break;
          case StockFilter.outOfStock:
            if (p.stockQuantity > 0) return false;
            break;
        }

        // 3. Category filter
        if (categoryFilter != 'All' && p.category != categoryFilter) {
          return false;
        }

        return true;
      }).toList();

      // Sort: Out of stock first, then low stock, then alphabetical by name
      filtered.sort((a, b) {
        final aOut = a.stockQuantity <= 0;
        final bOut = b.stockQuantity <= 0;
        if (aOut != bOut) return aOut ? -1 : 1;

        final aLow = a.stockQuantity <= a.minStockLevel;
        final bLow = b.stockQuantity <= b.minStockLevel;
        if (aLow != bLow) return aLow ? -1 : 1;

        return a.nameEn.compareTo(b.nameEn);
      });

      return filtered;
    },
    orElse: () => [],
  );
});
