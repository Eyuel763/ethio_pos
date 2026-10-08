import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../providers/database_providers.dart';
import 'sync_manager.dart';

/// Provider for Dio HTTP client configured with base URL and timeouts.
final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: AppConfig.defaultBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
      },
    ),
  );
});

/// State notifier for authenticated shop ID
class ShopIdNotifier extends Notifier<String> {
  @override
  String build() => 'a2c3b4d5-e6f7-8901-abcd-ef2345678901';

  void setShopId(String id) => state = id;
}

final shopIdProvider = NotifierProvider<ShopIdNotifier, String>(ShopIdNotifier.new);

/// State notifier for auth token
class AuthTokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setToken(String? token) => state = token;
}

final authTokenProvider = NotifierProvider<AuthTokenNotifier, String?>(AuthTokenNotifier.new);

/// Singleton SyncManager provider.
final syncManagerProvider = Provider<SyncManager>((ref) {
  final db = ref.watch(databaseProvider);
  final dio = ref.watch(dioProvider);
  final shopId = ref.watch(shopIdProvider);
  final token = ref.watch(authTokenProvider);

  final manager = SyncManager(
    database: db,
    dio: dio,
    shopId: shopId,
    authToken: token,
  );

  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Stream provider broadcasting current sync state (Synced, Syncing, Offline)
final syncStateStreamProvider = StreamProvider<SyncState>((ref) {
  final manager = ref.watch(syncManagerProvider);
  return manager.syncStateStream;
});
