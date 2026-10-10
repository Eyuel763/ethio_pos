import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/l10n/app_localizations.dart';
import 'core/providers/locale_provider.dart';
import 'core/sync/sync_providers.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/shell/main_shell_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('Error loading SharedPreferences: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const EthioPosApp(),
    ),
  );
}

class EthioPosApp extends ConsumerStatefulWidget {
  const EthioPosApp({super.key});

  @override
  ConsumerState<EthioPosApp> createState() => _EthioPosAppState();
}

class _EthioPosAppState extends ConsumerState<EthioPosApp> {
  @override
  void initState() {
    super.initState();
    // Start background sync manager auto-sync loop (every 15s) in live app
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Don't start recurring timer during tests
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        ref.read(syncManagerProvider).startAutoSync(intervalSeconds: 15);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeLocale = ref.watch(localeProvider);
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: 'EthioPOS',
      debugShowCheckedModeBanner: false,
      locale: activeLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20), // Rich retail green
          primary: const Color(0xFF1B5E20),
          secondary: const Color(0xFF00796B),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
        ),
      ),
      home: authState.isAuthenticated ? const MainShellScreen() : const LoginScreen(),
    );
  }
}
