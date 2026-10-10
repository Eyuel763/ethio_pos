import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';

enum SyncStatus {
  synced,
  syncing,
  offline,
}

class SyncState {
  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final int pendingCount;
  final String? errorMessage;

  const SyncState({
    required this.status,
    this.lastSyncedAt,
    this.pendingCount = 0,
    this.errorMessage,
  });

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncedAt,
    int? pendingCount,
    String? errorMessage,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      pendingCount: pendingCount ?? this.pendingCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class SyncManager {
  final AppDatabase database;
  final Dio dio;
  final String shopId;
  String? authToken;

  Timer? _autoSyncTimer;
  bool _isSyncing = false;

  final _syncStateController = StreamController<SyncState>.broadcast();
  Stream<SyncState> get syncStateStream => _syncStateController.stream;

  SyncState _currentState = const SyncState(status: SyncStatus.offline);
  SyncState get currentState => _currentState;

  SyncManager({
    required this.database,
    required this.dio,
    required this.shopId,
    this.authToken,
  }) {
    _emitState(_currentState);
  }

  void _emitState(SyncState state) {
    _currentState = state;
    if (!_syncStateController.isClosed) {
      _syncStateController.add(state);
    }
  }

  void updateAuthToken(String token) {
    authToken = token;
  }

  /// Starts automatic periodic sync every [intervalSeconds].
  void startAutoSync({int intervalSeconds = 15}) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      triggerSync();
    });
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// Triggers a push & pull sync cycle asynchronously without blocking UI callers.
  Future<void> triggerSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    int pendingCount = _currentState.pendingCount;
    try {
      final pendingOperations = await database.getPendingSyncOperations(limit: 50);
      pendingCount = pendingOperations.length;

      _emitState(_currentState.copyWith(
        status: SyncStatus.syncing,
        pendingCount: pendingCount,
      ));

      // 1. PUSH: Push pending outbox mutations if any exist
      if (pendingOperations.isNotEmpty) {
        await _pushMutations(pendingOperations);
      }

      // 2. PULL: Pull incremental changes from backend
      await _pullUpdates();

      // Recalculate remaining pending queue count
      final remaining = await database.getPendingSyncOperations(limit: 50);
      _emitState(_currentState.copyWith(
        status: SyncStatus.synced,
        lastSyncedAt: DateTime.now(),
        pendingCount: remaining.length,
        errorMessage: null,
      ));
    } on DioException catch (dioErr) {
      debugPrint('[SyncManager] Network/Dio error: ${dioErr.message}');
      int count = pendingCount;
      try {
        final remaining = await database.getPendingSyncOperations(limit: 50);
        count = remaining.length;
      } catch (_) {}
      _emitState(_currentState.copyWith(
        status: SyncStatus.offline,
        pendingCount: count,
        errorMessage: dioErr.message ?? 'Network connection unavailable',
      ));
    } catch (e) {
      debugPrint('[SyncManager] Sync error: $e');
      int count = pendingCount;
      try {
        final remaining = await database.getPendingSyncOperations(limit: 50);
        count = remaining.length;
      } catch (_) {}
      _emitState(_currentState.copyWith(
        status: SyncStatus.offline,
        pendingCount: count,
        errorMessage: e.toString(),
      ));
    } finally {
      _isSyncing = false;
    }
  }

  /// Pack and POST pending mutations to /api/v1/sync/push
  Future<void> _pushMutations(List<SyncQueueTableData> operations) async {
    final mutationsPayload = <Map<String, dynamic>>[];
    final operationIds = <int>[];

    for (final op in operations) {
      try {
        final parsedData = jsonDecode(op.payload);
        mutationsPayload.add({
          'sync_id': op.id,
          'entity_type': op.entityType,
          'operation': op.operation,
          'entity_id': op.entityId,
          'data': parsedData,
        });
        operationIds.add(op.id);
      } catch (e) {
        debugPrint('[SyncManager] Error parsing payload for sync_id ${op.id}: $e');
      }
    }

    if (mutationsPayload.isEmpty) return;

    // Mark items as SYNCING locally
    await database.markSyncStatus(operationIds, 'SYNCING');

    final requestBody = {
      'shop_id': shopId,
      'client_timestamp': DateTime.now().toUtc().toIso8601String(),
      'mutations': mutationsPayload,
    };

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
    };
    if (authToken != null) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    try {
      final response = await dio.post(
        '/api/v1/sync/push',
        data: requestBody,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        final results = response.data['results'] as List<dynamic>?;
        if (results != null) {
          final acknowledgedIds = <int>[];
          for (final item in results) {
            if (item['status'] == 'SUCCESS') {
              acknowledgedIds.add(item['sync_id'] as int);
            } else {
              // Increment retry count on failure
              await database.incrementSyncRetry(item['sync_id'] as int);
            }
          }

          // Safely remove acknowledged entries from SQLite outbox queue
          if (acknowledgedIds.isNotEmpty) {
            await database.removeAcknowledgedSync(acknowledgedIds);
          }
        }
      } else {
        // Revert status to PENDING on non-200 responses
        await database.markSyncStatus(operationIds, 'PENDING');
      }
    } catch (_) {
      // Revert status to PENDING on network or unexpected errors so they are retried
      await database.markSyncStatus(operationIds, 'PENDING');
      rethrow;
    }
  }

  /// Pull incremental catalog & customer changes via GET /api/v1/sync/pull
  Future<void> _pullUpdates() async {
    final lastSyncIso = _currentState.lastSyncedAt?.toUtc().toIso8601String();
    final queryParams = <String, dynamic>{};
    if (lastSyncIso != null) {
      queryParams['last_synced_at'] = lastSyncIso;
    }

    final headers = <String, dynamic>{};
    if (authToken != null) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    final response = await dio.get(
      '/api/v1/sync/pull',
      queryParameters: queryParams,
      options: Options(headers: headers),
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data['data'];
      if (data != null) {
        // Upsert pulled products
        final products = data['products'] as List<dynamic>?;
        if (products != null) {
          for (final p in products) {
            final productId = p['id'] as String;
            final serverStock = _parseDouble(p['stockQuantity'], 0.0);

            // Guard: protect local positive stock from negative server stubs
            final localProduct = await database.getProductById(productId);
            double resolvedStock = serverStock;
            if (serverStock < 0 && localProduct != null && localProduct.stockQuantity >= 0) {
              resolvedStock = localProduct.stockQuantity;
            }

            await database.upsertProduct(
              ProductsTableCompanion(
                id: drift.Value(productId),
                shopId: drift.Value(p['shopId'] ?? shopId),
                barcode: drift.Value(p['barcode']),
                nameAm: drift.Value(p['nameAm'] ?? ''),
                nameEn: drift.Value(p['nameEn'] ?? ''),
                category: drift.Value(p['category'] ?? 'General'),
                unitType: drift.Value(p['unitType'] ?? 'piece'),
                sellingPrice: drift.Value(_parseDouble(p['sellingPrice'], 0.0)),
                costPrice: drift.Value(_parseDouble(p['costPrice'], 0.0)),
                stockQuantity: drift.Value(resolvedStock),
                minStockLevel: drift.Value(_parseDouble(p['minStockLevel'], 5.0)),
                isDeleted: drift.Value(p['isDeleted'] ?? false),
              ),
            );
          }
        }

        // Upsert pulled customers
        final customers = data['customers'] as List<dynamic>?;
        if (customers != null) {
          for (final c in customers) {
            await database.upsertCustomer(
              CustomersTableCompanion(
                id: drift.Value(c['id']),
                shopId: drift.Value(c['shopId'] ?? shopId),
                fullName: drift.Value(c['fullName'] ?? ''),
                phoneNumber: drift.Value(c['phoneNumber']),
                totalDebt: drift.Value(_parseDouble(c['totalDebt'], 0.0)),
                isDeleted: drift.Value(c['isDeleted'] ?? false),
              ),
            );
          }
        }
      }
    }
  }

  double _parseDouble(dynamic value, [double defaultValue = 0.0]) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  void dispose() {
    stopAutoSync();
    _syncStateController.close();
  }
}
