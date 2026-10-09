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
import '../providers/ledger_providers.dart';

class RepaymentModal extends ConsumerStatefulWidget {
  final CustomersTableData customer;

  const RepaymentModal({super.key, required this.customer});

  static Future<void> show(BuildContext context, CustomersTableData customer) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RepaymentModal(customer: customer),
    );
  }

  @override
  ConsumerState<RepaymentModal> createState() => _RepaymentModalState();
}

class _RepaymentModalState extends ConsumerState<RepaymentModal> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _paymentMethod = 'CASH'; // 'CASH', 'TELEBIRR', 'CBE_BIRR'
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitRepayment() async {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount <= 0) return;

    setState(() => _isSubmitting = true);

    try {
      final db = ref.read(databaseProvider);
      final shopId = ref.read(shopIdProvider);
      final repaymentId = UuidUtil.generate();
      final notes = _noteController.text.trim();

      final repaymentCompanion = DebtRepaymentsTableCompanion.insert(
        id: repaymentId,
        shopId: shopId,
        customerId: widget.customer.id,
        amount: amount,
        paymentMethod: drift.Value(_paymentMethod),
        note: drift.Value(notes.isNotEmpty ? notes : null),
        createdAt: drift.Value(DateTime.now()),
      );

      final syncPayload = {
        'id': repaymentId,
        'customer_id': widget.customer.id,
        'amount': amount,
        'payment_method': _paymentMethod,
        'note': notes.isNotEmpty ? notes : null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Atomic SQLite write: insert repayment + update customer balance + enqueue outbox
      await db.recordRepaymentAtomic(
        repayment: repaymentCompanion,
        syncPayloadJson: jsonEncode(syncPayload),
      );

      // Invalidate customer history provider so detail screen updates immediately
      ref.invalidate(customerHistoryStreamProvider(widget.customer.id));

      // Asynchronous background sync trigger
      ref.read(syncManagerProvider).triggerSync();

      if (!mounted) return;
      Navigator.of(context).pop();

      final isAmharic = ref.read(localeProvider.notifier).isAmharic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAmharic
                ? 'ክፍያው በተሳካ ሁኔታ ተመዝግቧል!'
                : 'Repayment recorded successfully!',
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error recording repayment: $e'),
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
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;

    final enteredAmount = double.tryParse(_amountController.text) ?? 0.0;
    final remainingDebt =
        (widget.customer.totalDebt - enteredAmount).clamp(0.0, double.infinity);

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
                  backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                  child: const Icon(Icons.payment, color: Color(0xFF2E7D32)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.recordRepayment ?? 'Record Repayment',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.customer.fullName,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Current Debt Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n?.balance ?? 'Balance',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(
                      widget.customer.totalDebt,
                      isAmharic: isAmharic,
                    ),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Repayment Amount Input + Full Amount Button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: l10n?.repaymentAmount ?? 'Repayment Amount',
                      hintText: '0.00',
                      prefixIcon: const Icon(Icons.money),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton(
                    onPressed: () {
                      _amountController.text =
                          widget.customer.totalDebt.toStringAsFixed(2);
                      setState(() {});
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(l10n?.fullAmount ?? 'Full Amount'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Payment Method Selector
            Text(
              l10n?.paymentMethod ?? 'Payment Method',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'CASH',
                  label: Text(l10n?.cash ?? 'Cash'),
                  icon: const Icon(Icons.attach_money, size: 16),
                ),
                ButtonSegment(
                  value: 'TELEBIRR',
                  label: Text(l10n?.telebirr ?? 'Telebirr'),
                  icon: const Icon(Icons.phone_android, size: 16),
                ),
                ButtonSegment(
                  value: 'CBE_BIRR',
                  label: Text(l10n?.cbeBirr ?? 'CBE Birr'),
                  icon: const Icon(Icons.account_balance, size: 16),
                ),
              ],
              selected: {_paymentMethod},
              onSelectionChanged: (selected) {
                setState(() => _paymentMethod = selected.first);
              },
            ),
            const SizedBox(height: 16),

            // Reference / Note input
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: l10n?.referenceOrNote ?? 'Reference / Note (Optional)',
                hintText: 'e.g. Telebirr Txn #1234',
                prefixIcon: const Icon(Icons.notes),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Remaining Debt Preview
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n?.remainingDebt ?? 'Remaining Debt',
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(remainingDebt, isAmharic: isAmharic),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: remainingDebt > 0
                          ? Colors.red.shade700
                          : const Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Submit Button
            ElevatedButton(
              onPressed: _isSubmitting || enteredAmount <= 0
                  ? null
                  : _submitRepayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
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
                      l10n?.saveRepayment ?? 'Save Repayment',
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
