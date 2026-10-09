import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../core/sync/sync_providers.dart';
import 'package:client/l10n/app_localizations.dart';

class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStateAsync = ref.watch(syncStateStreamProvider);
    final syncManager = ref.read(syncManagerProvider);
    final syncState = syncStateAsync.value ?? syncManager.currentState;
    final l10n = AppLocalizations.of(context);

    Color dotColor = Colors.grey.shade600;
    String statusLabel = l10n?.offline ?? 'Offline';
    IconData iconData = Icons.cloud_off;

    switch (syncState.status) {
      case SyncStatus.synced:
        dotColor = const Color(0xFF2E7D32); // Forest green
        statusLabel = l10n?.synced ?? 'Synced';
        iconData = Icons.cloud_done;
        break;
      case SyncStatus.syncing:
        dotColor = const Color(0xFFEF6C00); // Deep orange
        statusLabel = l10n?.syncing ?? 'Syncing';
        iconData = Icons.sync;
        break;
      case SyncStatus.offline:
        dotColor = Colors.grey.shade600;
        statusLabel = l10n?.offline ?? 'Offline';
        iconData = Icons.cloud_off;
        break;
    }

    return InkWell(
      onTap: () {
        ref.read(syncManagerProvider).triggerSync();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syncState.pendingCount > 0
                  ? 'Syncing ${syncState.pendingCount} pending updates...'
                  : 'Syncing with cloud...',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: dotColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dotColor.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconData, size: 14, color: dotColor),
            const SizedBox(width: 5),
            Text(
              statusLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: dotColor,
              ),
            ),
            if (syncState.pendingCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${syncState.pendingCount}',
                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
