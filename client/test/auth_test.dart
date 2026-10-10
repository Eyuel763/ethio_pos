import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/providers/database_providers.dart';
import 'package:client/features/auth/models/auth_state.dart';
import 'package:client/features/auth/providers/auth_provider.dart';
import 'package:client/features/auth/screens/login_screen.dart';
import 'package:client/features/auth/screens/register_shop_screen.dart';
import 'package:client/l10n/app_localizations.dart';

void main() {
  group('AuthState Model Tests', () {
    test('initial state is unauthenticated and not loading', () {
      const state = AuthState.initial();
      expect(state.isAuthenticated, false);
      expect(state.isLoading, false);
      expect(state.token, isNull);
      expect(state.shopId, isNull);
      expect(state.shopName, isNull);
    });

    test('authenticated state populates fields', () {
      const state = AuthState.authenticated(
        token: 'test_token',
        shopId: 'shop_123',
        shopName: 'Mercato Shop',
        username: 'mercato_admin',
        isOfflineDemo: false,
      );
      expect(state.isAuthenticated, true);
      expect(state.token, 'test_token');
      expect(state.shopId, 'shop_123');
      expect(state.shopName, 'Mercato Shop');
      expect(state.username, 'mercato_admin');
      expect(state.isOfflineDemo, false);
    });

    test('copyWith updates specified fields', () {
      const state = AuthState.initial();
      final updated = state.copyWith(
        isLoading: true,
        errorMessage: 'Invalid credentials',
      );
      expect(updated.isLoading, true);
      expect(updated.errorMessage, 'Invalid credentials');
      expect(updated.isAuthenticated, false);
    });
  });

  group('AuthNotifier Tests', () {
    test('loginDemoMode activates demo shop and token', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authProvider.notifier);
      await notifier.loginDemoMode();

      final state = container.read(authProvider);
      expect(state.isAuthenticated, true);
      expect(state.isOfflineDemo, true);
      expect(state.username, 'bole_admin');
      expect(state.shopName, contains('Demo'));

      // Test logout
      await notifier.logout();
      final loggedOutState = container.read(authProvider);
      expect(loggedOutState.isAuthenticated, false);
      expect(loggedOutState.token, isNull);
    });
  });

  group('Auth Screens Widget Tests', () {
    testWidgets('LoginScreen renders header, inputs, and demo button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LoginScreen(),
          ),
        ),
      );

      // Verify header and buttons
      expect(find.text('EthioPOS'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.byType(ElevatedButton), findsOneWidget); // Sign in button
      expect(find.byType(OutlinedButton), findsOneWidget); // Demo mode button
    });

    testWidgets('RegisterShopScreen renders registration fields and validates required inputs', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RegisterShopScreen(),
          ),
        ),
      );

      // Verify form fields: shopName, ownerName, phone, username, password, confirmPassword
      expect(find.byType(TextFormField), findsNWidgets(6));

      // Attempt to submit empty form
      final submitButton = find.byType(ElevatedButton);
      expect(submitButton, findsOneWidget);
      await tester.tap(submitButton);
      await tester.pump();

      // Check validation error
      expect(find.text('እባክዎ የመደብሩን ስም ያስገቡ'), findsOneWidget);
    });
  });
}
