import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/sync/sync_manager.dart';

class MockInterceptor extends Interceptor {
  final Map<String, dynamic> Function(RequestOptions options) onPost;
  final Map<String, dynamic> Function(RequestOptions options) onGet;

  MockInterceptor({required this.onPost, required this.onGet});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method == 'POST' && options.path == '/api/v1/sync/push') {
      final responseData = onPost(options);
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: responseData,
      ));
      return;
    }

    if (options.method == 'GET' && options.path == '/api/v1/sync/pull') {
      final responseData = onGet(options);
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: responseData,
      ));
      return;
    }

    super.onRequest(options, handler);
  }
}

void main() {
  late AppDatabase db;
  late Dio dio;
  late SyncManager syncManager;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dio = Dio();
  });

  tearDown(() async {
    syncManager.dispose();
    await db.close();
  });

  test('SyncManager should push pending mutations and clear acknowledged queue entries', () async {
    const shopId = 'test-shop-123';
    var pushEndpointCalled = false;

    // Configure mock Dio interceptor simulating NestJS response
    dio.interceptors.add(
      MockInterceptor(
        onPost: (options) {
          pushEndpointCalled = true;
          final body = options.data as Map<String, dynamic>;
          final mutations = body['mutations'] as List<dynamic>;
          return {
            'status': 'success',
            'processed_at': DateTime.now().toIso8601String(),
            'results': mutations.map((m) => {
              'sync_id': m['sync_id'],
              'status': 'SUCCESS',
              'entity_id': m['entity_id'],
            }).toList(),
          };
        },
        onGet: (options) {
          return {
            'status': 'success',
            'data': {'products': [], 'customers': []},
          };
        },
      ),
    );

    syncManager = SyncManager(
      database: db,
      dio: dio,
      shopId: shopId,
      authToken: 'mock-jwt-token',
    );

    // Seed a pending mutation in SyncQueue
    await db.into(db.syncQueueTable).insert(
      SyncQueueTableCompanion.insert(
        entityType: 'sale',
        entityId: 'sale-999',
        operation: 'CREATE',
        payload: jsonEncode({'id': 'sale-999', 'subtotal': 150.0}),
      ),
    );

    // Verify 1 pending item exists locally
    final beforeSync = await db.getPendingSyncOperations();
    expect(beforeSync.length, 1);

    // Trigger sync cycle
    await syncManager.triggerSync();

    // Verify push occurred
    expect(pushEndpointCalled, isTrue);

    // Verify acknowledged item was removed from outbox
    final afterSync = await db.getPendingSyncOperations();
    expect(afterSync.isEmpty, isTrue);

    // Verify final state is synced
    expect(syncManager.currentState.status, SyncStatus.synced);
    expect(syncManager.currentState.pendingCount, 0);
  });

  test('SyncManager should pull products and update local Drift SQLite database', () async {
    const shopId = 'test-shop-123';

    dio.interceptors.add(
      MockInterceptor(
        onPost: (options) => {'status': 'success', 'results': []},
        onGet: (options) => {
          'status': 'success',
          'data': {
            'products': [
              {
                'id': 'cloud-prod-1',
                'shopId': shopId,
                'nameAm': 'ዳቦ',
                'nameEn': 'Bread',
                'category': 'Bakery',
                'unitType': 'piece',
                'sellingPrice': 25.0,
                'costPrice': 20.0,
                'stockQuantity': 50.0,
                'minStockLevel': 10.0,
                'isDeleted': false,
              }
            ],
            'customers': [],
          },
        },
      ),
    );

    syncManager = SyncManager(
      database: db,
      dio: dio,
      shopId: shopId,
    );

    await syncManager.triggerSync();

    // Verify pulled product is in local SQLite
    final pulledProduct = await db.getProductById('cloud-prod-1');
    expect(pulledProduct, isNotNull);
    expect(pulledProduct!.nameEn, 'Bread');
    expect(pulledProduct.sellingPrice, 25.0);
    expect(pulledProduct.stockQuantity, 50.0);
  });
}
