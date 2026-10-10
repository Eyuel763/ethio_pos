import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/l10n/app_localizations.dart';
import '../../core/providers/locale_provider.dart';
import '../auth/providers/auth_provider.dart';
import '../shared/widgets/sync_status_badge.dart';
import '../shared/widgets/language_switcher_button.dart';
import '../checkout/screens/pos_screen.dart';
import '../ledger/screens/ledger_screen.dart';
import '../inventory/screens/inventory_screen.dart';

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
    InventoryScreen(),
  ];

  void _showShopProfileModal() {
    final auth = ref.read(authProvider);
    final l10n = AppLocalizations.of(context);
    final isAmharic = ref.read(localeProvider.notifier).isAmharic;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with Store Avatar
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                      child: Icon(Icons.store, color: theme.colorScheme.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.shopName ?? 'Shop',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '@${auth.username ?? "user"}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (auth.isOfflineDemo)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Text(
                          isAmharic ? 'ሙከራ' : 'Demo',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),

                // Shop Details
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n?.activeShop ?? 'Active Shop',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    Flexible(
                      child: Text(
                        auth.shopName ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n?.username ?? 'Username',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    Text(
                      auth.username ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Logout Button
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final shouldLogout = await showDialog<bool>(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        title: Text(l10n?.logout ?? 'Logout'),
                        content: Text(
                          l10n?.logoutConfirm ?? 'Are you sure you want to log out?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(false),
                            child: Text(l10n?.cancel ?? 'Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(dialogCtx).pop(true),
                            child: Text(l10n?.logout ?? 'Logout'),
                          ),
                        ],
                      ),
                    );

                    if (shouldLogout == true) {
                      await ref.read(authProvider.notifier).logout();
                    }
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: Text(
                    l10n?.logout ?? 'Logout',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);

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
        title: InkWell(
          onTap: _showShopProfileModal,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront, color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 6),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        auth.shopName ?? (l10n?.appTitle ?? 'EthioPOS'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (auth.username != null)
                        Text(
                          '@${auth.username}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          const SyncStatusBadge(),
          const SizedBox(width: 4),
          const LanguageSwitcherButton(),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: l10n?.activeShop ?? 'Shop Account',
            onPressed: _showShopProfileModal,
          ),
          const SizedBox(width: 6),
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
