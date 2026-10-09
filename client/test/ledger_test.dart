import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/providers/database_providers.dart';
import 'package:client/features/ledger/utils/debt_receipt_formatter.dart';
import 'package:client/features/ledger/providers/ledger_providers.dart';

void main() {
  group('DebtReceiptFormatter Tests', () {
    test('formats customer debt summary correctly', () {
      final customer = CustomersTableData(
        id: 'cust-1',
        shopId: 'shop-1',
        fullName: 'Kebede Tadesse',
        phoneNumber: '0911234567',
        totalDebt: 775.0,
        createdAt: DateTime(2026, 10, 6),
        updatedAt: DateTime(2026, 10, 6),
        isDeleted: false,
      );

      final summary = DebtReceiptFormatter.formatCustomerDebtSummary(
        customer: customer,
        shopName: 'Test Shop',
      );

      expect(summary, contains('Test Shop'));
      expect(summary, contains('Kebede Tadesse'));
      expect(summary, contains('0911234567'));
      expect(summary, contains('775.00 ETB'));
      expect(summary, contains('775.00 ብር'));
    });

    test('formats credit sale receipt with line items', () {
      final customer = CustomersTableData(
        id: 'cust-1',
        shopId: 'shop-1',
        fullName: 'Kebede Tadesse',
        phoneNumber: '0911234567',
        totalDebt: 775.0,
        createdAt: DateTime(2026, 10, 6),
        updatedAt: DateTime(2026, 10, 6),
        isDeleted: false,
      );

      final sale = SalesTableData(
        id: 'sale-1',
        shopId: 'shop-1',
        customerId: 'cust-1',
        paymentType: 'CREDIT',
        subtotal: 450.0,
        discount: 0.0,
        grandTotal: 450.0,
        amountPaid: 100.0,
        amountDue: 350.0,
        createdAt: DateTime(2026, 10, 6, 11, 28),
        updatedAt: DateTime(2026, 10, 6, 11, 28),
      );

      final items = [
        const SaleItemsTableData(
          id: 'item-1',
          saleId: 'sale-1',
          productId: 'prod-1',
          productName: '5L Cooking Oil',
          unitPrice: 450.0,
          quantity: 1.0,
          totalPrice: 450.0,
        ),
      ];

      final receipt = DebtReceiptFormatter.formatCreditSaleReceipt(
        customer: customer,
        sale: sale,
        items: items,
        previousBalance: 625.0,
        isAmharic: false,
      );

      expect(receipt, contains('5L Cooking Oil'));
      expect(receipt, contains('450.00 ETB'));
      expect(receipt, contains('100.00 ETB'));
      expect(receipt, contains('350.00 ETB'));
      expect(receipt, contains('625.00 ETB'));
      expect(receipt, contains('975.00 ETB'));
    });

    test('formats repayment receipt', () {
      final customer = CustomersTableData(
        id: 'cust-1',
        shopId: 'shop-1',
        fullName: 'Kebede Tadesse',
        totalDebt: 575.0,
        createdAt: DateTime(2026, 10, 6),
        updatedAt: DateTime(2026, 10, 6),
        isDeleted: false,
      );

      final repayment = DebtRepaymentsTableData(
        id: 'rep-1',
        shopId: 'shop-1',
        customerId: 'cust-1',
        amount: 200.0,
        paymentMethod: 'TELEBIRR',
        note: 'Txn #1234',
        createdAt: DateTime(2026, 10, 6, 11, 29),
      );

      final receipt = DebtReceiptFormatter.formatRepaymentReceipt(
        customer: customer,
        repayment: repayment,
        previousBalance: 775.0,
        isAmharic: false,
      );

      expect(receipt, contains('Kebede Tadesse'));
      expect(receipt, contains('TELEBIRR'));
      expect(receipt, contains('Txn #1234'));
      expect(receipt, contains('200.00 ETB'));
      expect(receipt, contains('775.00 ETB'));
      expect(receipt, contains('575.00 ETB'));
    });
  });

  group('Ledger Providers Tests', () {
    final testCustomers = [
      CustomersTableData(
        id: 'cust-1',
        shopId: 'shop-1',
        fullName: 'Kebede Tadesse',
        phoneNumber: '0911234567',
        totalDebt: 775.0,
        createdAt: DateTime(2026, 10, 6),
        updatedAt: DateTime(2026, 10, 6),
        isDeleted: false,
      ),
      CustomersTableData(
        id: 'cust-2',
        shopId: 'shop-1',
        fullName: 'Almaz Ayana',
        phoneNumber: '0922987654',
        totalDebt: 645.0,
        createdAt: DateTime(2026, 10, 6),
        updatedAt: DateTime(2026, 10, 6),
        isDeleted: false,
      ),
      CustomersTableData(
        id: 'cust-3',
        shopId: 'shop-1',
        fullName: 'Chala Bekele',
        phoneNumber: '0933112233',
        totalDebt: 0.0,
        createdAt: DateTime(2026, 10, 6),
        updatedAt: DateTime(2026, 10, 6),
        isDeleted: false,
      ),
    ];

    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          customersStreamProvider.overrideWith((ref) => Stream.value(testCustomers)),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('calculates total outstanding debt and filters by search query', () async {
      // Pump container to receive stream value
      container.listen(customersStreamProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Total debt: 775 + 645 = 1420.0
      final totalDebt = container.read(totalOutstandingDebtProvider);
      expect(totalDebt, 1420.0);

      // Filtered customers without query - highest debt first
      final allFiltered = container.read(filteredCustomersProvider);
      expect(allFiltered.length, 3);
      expect(allFiltered[0].fullName, 'Kebede Tadesse');
      expect(allFiltered[1].fullName, 'Almaz Ayana');
      expect(allFiltered[2].fullName, 'Chala Bekele');

      // Search by partial phone number
      container.read(customerSearchQueryProvider.notifier).setQuery('0922');
      final searchResult = container.read(filteredCustomersProvider);
      expect(searchResult.length, 1);
      expect(searchResult.first.fullName, 'Almaz Ayana');

      // Search by partial name
      container.read(customerSearchQueryProvider.notifier).setQuery('chala');
      final nameResult = container.read(filteredCustomersProvider);
      expect(nameResult.length, 1);
      expect(nameResult.first.fullName, 'Chala Bekele');
    });
  });

  group('Ledger Database Tests', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.upsertCustomer(
        CustomersTableCompanion.insert(
          id: 'cust-1',
          shopId: 'shop-1',
          fullName: 'Kebede Tadesse',
          phoneNumber: const drift.Value('0911234567'),
          totalDebt: const drift.Value(775.0),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('records repayment atomically, reduces debt and enqueues sync queue row', () async {
      const repaymentId = 'rep-test-1';
      final companion = DebtRepaymentsTableCompanion.insert(
        id: repaymentId,
        shopId: 'shop-1',
        customerId: 'cust-1',
        amount: 275.0,
        paymentMethod: const drift.Value('CASH'),
        note: const drift.Value('Partial payment'),
        createdAt: drift.Value(DateTime.now()),
      );

      await db.recordRepaymentAtomic(
        repayment: companion,
        syncPayloadJson: '{"id": "$repaymentId", "amount": 275.0}',
      );

      // Verify customer debt is reduced: 775.0 - 275.0 = 500.0
      final updatedCustomer = await db.getCustomerById('cust-1');
      expect(updatedCustomer, isNotNull);
      expect(updatedCustomer!.totalDebt, 500.0);

      // Verify sync queue outbox
      final pendingOps = await db.getPendingSyncOperations();
      expect(pendingOps.length, 1);
      expect(pendingOps.first.entityType, 'debt_repayment');
      expect(pendingOps.first.entityId, repaymentId);
    });

    test('retrieves customer sales and repayments correctly', () async {
      final customer = await db.getCustomerById('cust-1');
      expect(customer, isNotNull);
      expect(customer!.fullName, 'Kebede Tadesse');

      final repayments = await db.getCustomerRepayments('cust-1');
      expect(repayments, isEmpty);
    });
  });
}
