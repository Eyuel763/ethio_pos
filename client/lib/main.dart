import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/l10n/app_localizations.dart';
import 'core/providers/locale_provider.dart';
import 'core/sync/sync_providers.dart';
import 'features/shell/main_shell_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: EthioPosApp()));
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
      home: const MainShellScreen(),
    );
  }
}
