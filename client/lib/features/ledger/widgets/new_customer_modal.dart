import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:client/core/database/app_database.dart';
import 'package:client/core/utils/formatters.dart';
import 'package:client/core/sync/sync_providers.dart';
import 'package:client/core/providers/database_providers.dart';
import 'package:client/core/providers/locale_provider.dart';
import 'package:client/l10n/app_localizations.dart';

class NewCustomerModal extends ConsumerStatefulWidget {
  const NewCustomerModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const NewCustomerModal(),
    );
  }

  @override
  ConsumerState<NewCustomerModal> createState() => _NewCustomerModalState();
}

class _NewCustomerModalState extends ConsumerState<NewCustomerModal> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _initialDebtController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _initialDebtController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      final db = ref.read(databaseProvider);
      final shopId = ref.read(shopIdProvider);
      final newId = UuidUtil.generate();
      final phone = _phoneController.text.trim().isNotEmpty
          ? _phoneController.text.trim()
          : null;
      final initialDebt =
          double.tryParse(_initialDebtController.text.trim()) ?? 0.0;

      await db.upsertCustomer(
        CustomersTableCompanion.insert(
          id: newId,
          shopId: shopId,
          fullName: name,
          phoneNumber: drift.Value(phone),
          totalDebt: drift.Value(initialDebt),
          createdAt: drift.Value(DateTime.now()),
        ),
      );

      // Enqueue to sync queue
      await db.into(db.syncQueueTable).insert(
        SyncQueueTableCompanion.insert(
          entityType: 'customer',
          entityId: newId,
          operation: 'CREATE',
          payload: jsonEncode({
            'id': newId,
            'full_name': name,
            'phone_number': phone,
            'total_debt': initialDebt,
          }),
        ),
      );

      // Non-blocking sync trigger
      ref.read(syncManagerProvider).triggerSync();

      if (!mounted) return;
      Navigator.of(context).pop();

      final isAmharic = ref.read(localeProvider.notifier).isAmharic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAmharic
                ? 'ደንበኛ በተሳካ ሁኔታ ተመዝግቧል!'
                : 'Customer created successfully!',
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating customer: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                  child: Icon(Icons.person_add, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n?.newCustomer ?? 'New Customer',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Customer Name
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n?.customerName ?? 'Customer Name',
                hintText: 'e.g. Kebede Tadesse / ከበደ ታደሰ',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Phone Number
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n?.phoneNumber ?? 'Phone Number',
                hintText: 'e.g. 0911234567',
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Initial Debt (Optional)
            TextField(
              controller: _initialDebtController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                labelText: '${l10n?.previousBalance ?? 'Previous Balance'} (ETB)',
                hintText: '0.00',
                prefixIcon: const Icon(Icons.account_balance_wallet),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Submit Button
            ElevatedButton(
              onPressed: _isSubmitting || _nameController.text.trim().isEmpty
                  ? null
                  : _handleSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      l10n?.saveCustomer ?? 'Save Customer',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
