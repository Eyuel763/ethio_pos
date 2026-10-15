import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/sync/sync_providers.dart';
import '../models/auth_state.dart';

final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

class AuthNotifier extends Notifier<AuthState> {
  static const _keyToken = 'auth_token';
  static const _keyShopId = 'auth_shop_id';
  static const _keyShopName = 'auth_shop_name';
  static const _keyUsername = 'auth_username';
  static const _keyFullName = 'auth_full_name';
  static const _keyIsDemo = 'auth_is_demo';

  @override
  AuthState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    if (prefs == null) return const AuthState.initial();

    final token = prefs.getString(_keyToken);
    final shopId = prefs.getString(_keyShopId);
    final shopName = prefs.getString(_keyShopName);
    final username = prefs.getString(_keyUsername);
    final fullName = prefs.getString(_keyFullName);
    final isDemo = prefs.getBool(_keyIsDemo) ?? false;

    if (token != null && shopId != null && username != null) {
      // Sync with sync providers
      Future.microtask(() {
        ref.read(authTokenProvider.notifier).setToken(token);
        ref.read(shopIdProvider.notifier).setShopId(shopId);
      });

      return AuthState.authenticated(
        token: token,
        shopId: shopId,
        shopName: shopName ?? 'Store',
        username: username,
        fullName: fullName,
        isOfflineDemo: isDemo,
      );
    }

    return const AuthState.initial();
  }

  /// Sign in with username and password
  Future<bool> login({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(
        '/api/v1/auth/login',
        data: {
          'username': username.trim(),
          'password': password,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final accessToken = data['accessToken'] as String;
        final shop = data['shop'] as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>;

        final shopId = shop['id'] as String;
        final shopName = shop['name'] as String;
        final loggedUsername = user['username'] as String;

        // Persist session
        final prefs = ref.read(sharedPreferencesProvider);
        await prefs?.setString(_keyToken, accessToken);
        await prefs?.setString(_keyShopId, shopId);
        await prefs?.setString(_keyShopName, shopName);
        await prefs?.setString(_keyUsername, loggedUsername);
        await prefs?.setBool(_keyIsDemo, false);

        // Update core providers
        ref.read(authTokenProvider.notifier).setToken(accessToken);
        ref.read(shopIdProvider.notifier).setShopId(shopId);

        state = AuthState.authenticated(
          token: accessToken,
          shopId: shopId,
          shopName: shopName,
          username: loggedUsername,
          isOfflineDemo: false,
        );

        // Trigger initial cloud sync for new shop
        ref.read(syncManagerProvider).triggerSync();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Login failed. Please check your credentials.',
        );
        return false;
      }
    } on DioException catch (e) {
      String message = 'Unable to connect to server';
      if (e.response != null) {
        if (e.response?.statusCode == 401) {
          message = 'Invalid username or password';
        } else if (e.response?.data is Map && e.response?.data['message'] != null) {
          final serverMsg = e.response?.data['message'];
          message = serverMsg is List ? serverMsg.join(', ') : serverMsg.toString();
        }
      }
      state = state.copyWith(isLoading: false, errorMessage: message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Register a new shop and admin account
  Future<bool> register({
    required String shopName,
    required String username,
    required String password,
    String? fullName,
    String? phoneNumber,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(
        '/api/v1/auth/register',
        data: {
          'shopName': shopName.trim(),
          'username': username.trim(),
          'password': password,
          if (fullName != null && fullName.trim().isNotEmpty) 'fullName': fullName.trim(),
          if (phoneNumber != null && phoneNumber.trim().isNotEmpty) 'phoneNumber': phoneNumber.trim(),
        },
      );

      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        final data = response.data;
        final accessToken = data['accessToken'] as String;
        final shop = data['shop'] as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>;

        final shopId = shop['id'] as String;
        final createdShopName = shop['name'] as String;
        final createdUsername = user['username'] as String;

        // Persist session
        final prefs = ref.read(sharedPreferencesProvider);
        await prefs?.setString(_keyToken, accessToken);
        await prefs?.setString(_keyShopId, shopId);
        await prefs?.setString(_keyShopName, createdShopName);
        await prefs?.setString(_keyUsername, createdUsername);
        if (fullName != null) await prefs?.setString(_keyFullName, fullName);
        await prefs?.setBool(_keyIsDemo, false);

        // Update core providers
        ref.read(authTokenProvider.notifier).setToken(accessToken);
        ref.read(shopIdProvider.notifier).setShopId(shopId);

        state = AuthState.authenticated(
          token: accessToken,
          shopId: shopId,
          shopName: createdShopName,
          username: createdUsername,
          fullName: fullName,
          isOfflineDemo: false,
        );

        // Trigger initial cloud sync for new shop
        ref.read(syncManagerProvider).triggerSync();
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Registration failed. Please try again.',
        );
        return false;
      }
    } on DioException catch (e) {
      String message = 'Unable to connect to server';
      if (e.response != null) {
        if (e.response?.statusCode == 409) {
          message = 'Username is already taken';
        } else if (e.response?.data is Map && e.response?.data['message'] != null) {
          final serverMsg = e.response?.data['message'];
          message = serverMsg is List ? serverMsg.join(', ') : serverMsg.toString();
        }
      }
      state = state.copyWith(isLoading: false, errorMessage: message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Continue in Demo / Offline Mode using a local offline store profile
  Future<void> loginDemoMode() async {
    const demoShopId = 'local-demo-shop-001';
    const demoShopName = 'Local Demo Store';
    const demoUsername = 'demo_user';

    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.remove(_keyToken);
    await prefs?.setString(_keyShopId, demoShopId);
    await prefs?.setString(_keyShopName, demoShopName);
    await prefs?.setString(_keyUsername, demoUsername);
    await prefs?.setBool(_keyIsDemo, true);

    ref.read(authTokenProvider.notifier).setToken(null);
    ref.read(shopIdProvider.notifier).setShopId(demoShopId);

    state = const AuthState.authenticated(
      token: null,
      shopId: demoShopId,
      shopName: demoShopName,
      username: demoUsername,
      isOfflineDemo: true,
    );
  }

  /// Sign out and clear stored session
  Future<void> logout() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.remove(_keyToken);
    await prefs?.remove(_keyShopId);
    await prefs?.remove(_keyShopName);
    await prefs?.remove(_keyUsername);
    await prefs?.remove(_keyFullName);
    await prefs?.remove(_keyIsDemo);

    ref.read(authTokenProvider.notifier).setToken(null);
    ref.read(shopIdProvider.notifier).setShopId('');

    state = const AuthState.initial();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
