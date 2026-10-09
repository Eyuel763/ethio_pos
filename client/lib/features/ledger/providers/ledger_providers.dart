import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/providers/database_providers.dart';
import '../models/ledger_entry.dart';

class CustomerSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
}

final customerSearchQueryProvider =
    NotifierProvider<CustomerSearchQueryNotifier, String>(CustomerSearchQueryNotifier.new);

final totalOutstandingDebtProvider = Provider<double>((ref) {
  final customersAsync = ref.watch(customersStreamProvider);
  return customersAsync.maybeWhen(
    data: (customers) => customers.fold<double>(
      0.0,
      (sum, customer) => sum + customer.totalDebt,
    ),
    orElse: () => 0.0,
  );
});

final filteredCustomersProvider = Provider<List<CustomersTableData>>((ref) {
  final query = ref.watch(customerSearchQueryProvider).trim().toLowerCase();
  final customersAsync = ref.watch(customersStreamProvider);

  return customersAsync.maybeWhen(
    data: (customers) {
      final filtered = customers.where((c) {
        if (query.isEmpty) return true;
        final nameMatch = c.fullName.toLowerCase().contains(query);
        final phoneMatch = c.phoneNumber?.toLowerCase().contains(query) ?? false;
        return nameMatch || phoneMatch;
      }).toList();

      // Sort: customers with outstanding debt first (descending), then alphabetically
      filtered.sort((a, b) {
        if (b.totalDebt != a.totalDebt) {
          return b.totalDebt.compareTo(a.totalDebt);
        }
        return a.fullName.compareTo(b.fullName);
      });

      return filtered;
    },
    orElse: () => [],
  );
});

final customerDetailStreamProvider =
    StreamProvider.family<CustomersTableData?, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return db.watchCustomerById(customerId);
});

final customerSalesStreamProvider =
    StreamProvider.family<List<SalesTableData>, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return db.watchCustomerSales(customerId);
});

final customerRepaymentsStreamProvider =
    StreamProvider.family<List<DebtRepaymentsTableData>, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return db.watchCustomerRepayments(customerId);
});

final customerHistoryStreamProvider =
    FutureProvider.family<List<LedgerEntry>, String>((ref, customerId) async {
  final db = ref.watch(databaseProvider);

  final sales = await db.getCustomerSales(customerId);
  final repayments = await db.getCustomerRepayments(customerId);

  final List<LedgerEntry> entries = [];

  for (final sale in sales) {
    final items = await db.getSaleItems(sale.id);
    entries.add(CreditSaleLedgerEntry(
      id: sale.id,
      date: sale.createdAt,
      sale: sale,
      items: items,
    ));
  }

  for (final rep in repayments) {
    entries.add(RepaymentLedgerEntry(
      id: rep.id,
      date: rep.createdAt,
      repayment: rep,
    ));
  }

  // Sort descending: latest transactions first
  entries.sort((a, b) => b.date.compareTo(a.date));
  return entries;
});
