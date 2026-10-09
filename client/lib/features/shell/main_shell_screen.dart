import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/l10n/app_localizations.dart';
import '../shared/widgets/sync_status_badge.dart';
import '../shared/widgets/language_switcher_button.dart';
import '../checkout/screens/pos_screen.dart';
import '../ledger/screens/ledger_screen.dart';

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _selectedTabIndex = 0;

  // Tabs: 0 is POS, 1 is Ledger, 2 is Inventory
  final List<Widget> _tabs = const [
    PosScreen(),
    LedgerScreen(),
    Center(key: ValueKey('inventory_placeholder'), child: Text('Inventory Management Screen')),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final tabLabels = [
      l10n?.posTab ?? 'POS / Register',
      l10n?.ledgerTab ?? 'Credit Ledger',
      l10n?.inventoryTab ?? 'Inventory',
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        elevation: 1,
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront, color: theme.colorScheme.primary, size: 22),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n?.appTitle ?? 'EthioPOS',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        actions: const [
          SyncStatusBadge(),
          SizedBox(width: 6),
          LanguageSwitcherButton(),
          SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        height: 64,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.point_of_sale_outlined),
            selectedIcon: const Icon(Icons.point_of_sale),
            label: tabLabels[0],
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: tabLabels[1],
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: tabLabels[2],
          ),
        ],
      ),
    );
  }
}
