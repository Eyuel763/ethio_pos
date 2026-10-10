import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/sync/sync_manager.dart';

void main() {
  const uuid = Uuid();
  late AppDatabase db;
  late Dio dio;
  late SyncManager syncManager;
  const shopId = '00000000-0000-0000-0000-000000000001';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dio = Dio();
  });

  tearDown(() async {
    syncManager.dispose();
    await db.close();
  });

  group('Flutter Client End-to-End Sync Lifecycle (Sub-Phase 5.1)', () {
    test('5.1.1 Full Offline Lifecycle: POS Sale, Credit, Repayment, & Outbox Synchronization', () async {
      final productId = uuid.v4();
      final customerId = uuid.v4();
      final saleId = uuid.v4();
      final repaymentId = uuid.v4();

      // Interceptor to capture and validate exact outbox push contract
      Map<String, dynamic>? capturedPushPayload;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/api/v1/sync/push')) {
              capturedPushPayload = options.data as Map<String, dynamic>;
              final mutations = capturedPushPayload!['mutations'] as List<dynamic>;

              // Return SUCCESS for each mutation in the batch
              handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 'success',
                  'processed_at': DateTime.now().toIso8601String(),
                  'results': mutations.map((m) => {
                    'sync_id': m['sync_id'],
                    'status': 'SUCCESS',
                    'entity_id': m['entity_id'],
                  }).toList(),
                },
              ));
              return;
            }

            if (options.path.endsWith('/api/v1/sync/pull')) {
              handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 'success',
                  'server_timestamp': DateTime.now().toIso8601String(),
                  'data': {'products': [], 'customers': []},
                },
              ));
              return;
            }

            handler.next(options);
          },
        ),
      );

      syncManager = SyncManager(
        database: db,
        dio: dio,
        shopId: shopId,
        authToken: 'test-jwt-token',
      );

      // STEP 1: Create product offline
      await db.upsertProduct(
        ProductsTableCompanion.insert(
          id: productId,
          shopId: shopId,
          nameAm: 'የሱፍ ዘይት 5 ሊትር',
          nameEn: 'Sunflower Oil 5L',
          category: const drift.Value('Groceries'),
          unitType: const drift.Value('piece'),
          sellingPrice: 450.0,
          costPrice: const drift.Value(380.0),
          stockQuantity: const drift.Value(50.0),
          minStockLevel: const drift.Value(5.0),
        ),
      );

      // Queue product sync outbox mutation
      await db.into(db.syncQueueTable).insert(
        SyncQueueTableCompanion.insert(
          entityType: 'product',
          entityId: productId,
          operation: 'CREATE',
          payload: jsonEncode({
            'id': productId,
            'name_am': 'የሱፍ ዘይት 5 ሊትር',
            'name_en': 'Sunflower Oil 5L',
            'selling_price': 450.0,
            'stock_quantity': 50.0,
          }),
        ),
      );

      // STEP 2: Create customer profile offline
      await db.upsertCustomer(
        CustomersTableCompanion.insert(
          id: customerId,
          shopId: shopId,
          fullName: 'Chala Tadesse',
          phoneNumber: const drift.Value('0912345678'),
          totalDebt: const drift.Value(0.0),
        ),
      );

      // Queue customer sync outbox mutation
      await db.into(db.syncQueueTable).insert(
        SyncQueueTableCompanion.insert(
          entityType: 'customer',
          entityId: customerId,
          operation: 'CREATE',
          payload: jsonEncode({
            'id': customerId,
            'full_name': 'Chala Tadesse',
            'phone_number': '0912345678',
          }),
        ),
      );

      // STEP 3: Complete POS Partial Credit Sale offline:
      // Sells 2 units (450 * 2 = 900 ETB), Paid: 300 ETB, Added to Debt: 600 ETB
      final saleSyncPayload = jsonEncode({
        'id': saleId,
        'customer_id': customerId,
        'payment_type': 'credit',
        'subtotal': 900.0,
        'discount': 0.0,
        'grand_total': 900.0,
        'amount_paid': 300.0,
        'amount_due': 600.0,
        'created_at': DateTime.now().toIso8601String(),
        'items': [
          {
            'id': uuid.v4(),
            'product_id': productId,
            'product_name': 'Sunflower Oil 5L',
            'unit_price': 450.0,
            'quantity': 2.0,
            'total_price': 900.0,
          },
        ],
      });

      await db.recordSaleAtomic(
        sale: SalesTableCompanion.insert(
          id: saleId,
          shopId: shopId,
          customerId: drift.Value(customerId),
          paymentType: 'credit',
          subtotal: 900.0,
          discount: const drift.Value(0.0),
          grandTotal: 900.0,
          amountPaid: 300.0,
          amountDue: 600.0,
          createdAt: drift.Value(DateTime.now()),
        ),
        items: [
          SaleItemsTableCompanion.insert(
            id: uuid.v4(),
            saleId: saleId,
            productId: productId,
            productName: 'Sunflower Oil 5L',
            unitPrice: 450.0,
            quantity: 2.0,
            totalPrice: 900.0,
          ),
        ],
        syncPayloadJson: saleSyncPayload,
      );

      // STEP 4: Record debt repayment offline:
      // Repays 200 ETB via telebirr
      final repaymentSyncPayload = jsonEncode({
        'id': repaymentId,
        'customer_id': customerId,
        'amount': 200.0,
        'payment_method': 'telebirr',
        'note': 'Paid via Telebirr ref #TB1234',
        'created_at': DateTime.now().toIso8601String(),
      });

      await db.recordRepaymentAtomic(
        repayment: DebtRepaymentsTableCompanion.insert(
          id: repaymentId,
          shopId: shopId,
          customerId: customerId,
          amount: 200.0,
          paymentMethod: const drift.Value('telebirr'),
          note: const drift.Value('Paid via Telebirr ref #TB1234'),
          createdAt: drift.Value(DateTime.now()),
        ),
        syncPayloadJson: repaymentSyncPayload,
      );

      // VERIFY LOCAL OFFLINE STATE BEFORE SYNC:
      // 1. Product stock decremented: 50 - 2 = 48
      final product = await db.getProductById(productId);
      expect(product!.stockQuantity, 48.0);

      // 2. Customer debt: 0 + 600 - 200 = 400
      final customer = await db.getCustomerById(customerId);
      expect(customer!.totalDebt, 400.0);

      // 3. Exactly 4 pending mutations queued in outbox
      final pendingQueue = await db.getPendingSyncOperations();
      expect(pendingQueue.length, 4);
      expect(pendingQueue.map((m) => m.entityType).toList(), [
        'product',
        'customer',
        'sale',
        'debt_repayment',
      ]);

      // STEP 5: Trigger Synchronization (Device comes online)
      await syncManager.triggerSync();

      // VERIFY OUTBOX TRANSMISSION & PURGE:
      // 1. Push payload was transmitted with accurate structure
      expect(capturedPushPayload, isNotNull);
      expect(capturedPushPayload!['shop_id'], shopId);
      final transmittedMutations = capturedPushPayload!['mutations'] as List<dynamic>;
      expect(transmittedMutations.length, 4);

      // 2. All acknowledged mutations purged from local SQLite SyncQueue
      final remainingQueue = await db.getPendingSyncOperations();
      expect(remainingQueue.isEmpty, isTrue);

      // 3. Sync state updated to Synced with 0 pending items
      expect(syncManager.currentState.status, SyncStatus.synced);
      expect(syncManager.currentState.pendingCount, 0);
    });

    test('5.1.2 Offline Resilience: Local POS transactions never block when network is unreachable', () async {
      // Simulate network connection failure (Connection refused)
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                message: 'Connection refused',
              ),
            );
          },
        ),
      );

      syncManager = SyncManager(
        database: db,
        dio: dio,
        shopId: shopId,
        authToken: 'test-jwt-token',
      );

      // Perform sale transaction offline
      final saleId = uuid.v4();
      await db.recordSaleAtomic(
        sale: SalesTableCompanion.insert(
          id: saleId,
          shopId: shopId,
          paymentType: 'cash',
          subtotal: 100.0,
          grandTotal: 100.0,
          amountPaid: 100.0,
          amountDue: 0.0,
        ),
        items: [],
        syncPayloadJson: '{"entity_type": "sale", "entity_id": "$saleId"}',
      );

      // Attempt to sync while offline
      await syncManager.triggerSync();

      // 1. Local transaction remains safe in SQLite outbox
      final pending = await db.getPendingSyncOperations();
      expect(pending.length, 1);
      expect(pending.first.entityId, saleId);

      // 2. Sync state reflects offline status without crashing the app
      expect(syncManager.currentState.status, SyncStatus.offline);
      expect(syncManager.currentState.pendingCount, 1);
      expect(syncManager.currentState.errorMessage, isNotNull);
    });
  });
}
