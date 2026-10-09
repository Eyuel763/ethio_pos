import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/utils/formatters.dart';
import 'package:client/core/providers/locale_provider.dart';
import 'package:client/l10n/app_localizations.dart';
import '../providers/ledger_providers.dart';
import '../models/ledger_entry.dart';
import '../widgets/repayment_modal.dart';
import '../widgets/debt_receipt_dialog.dart';
import '../utils/debt_receipt_formatter.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailStreamProvider(customerId));
    final historyAsync = ref.watch(customerHistoryStreamProvider(customerId));
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy (h:mm a)');

    return customerAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Customer Detail')),
        body: Center(child: Text('Error: $err')),
      ),
      data: (customer) {
        if (customer == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Customer Detail')),
            body: Center(child: Text(l10n?.noCustomersFound ?? 'Customer not found')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(customer.fullName),
            elevation: 1,
            backgroundColor: theme.colorScheme.surface,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Customer Summary Header Card
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: customer.totalDebt > 0
                        ? Colors.red.shade200
                        : Colors.grey.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                          child: Icon(Icons.person, color: theme.colorScheme.primary, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer.fullName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (customer.phoneNumber != null && customer.phoneNumber!.isNotEmpty)
                                Row(
                                  children: [
                                    const Icon(Icons.phone, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      customer.phoneNumber!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              l10n?.balance ?? 'Balance',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(customer.totalDebt, isAmharic: isAmharic),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: customer.totalDebt > 0
                                    ? Colors.red.shade700
                                    : const Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Action buttons: Share Receipt & Record Repayment
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final receipt = DebtReceiptFormatter.formatCustomerDebtSummary(
                                customer: customer,
                              );
                              showDialog(
                                context: context,
                                builder: (_) => DebtReceiptDialog(receiptText: receipt),
                              );
                            },
                            icon: const Icon(Icons.share, size: 16),
                            label: Text(
                              l10n?.shareReceipt ?? 'Share Receipt',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => RepaymentModal.show(context, customer),
                            icon: const Icon(Icons.payment, size: 16),
                            label: Text(
                              l10n?.recordRepayment ?? 'Record Repayment',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Section Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      l10n?.transactionHistory ?? 'Transaction History',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Timeline List
              Expanded(
                child: historyAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text('Error: $err')),
                  data: (entries) {
                    if (entries.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              l10n?.noTransactionsRecorded ?? 'No transactions recorded yet',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];

                        if (entry is RepaymentLedgerEntry) {
                          return _buildRepaymentCard(
                            context: context,
                            entry: entry,
                            customer: customer,
                            dateFormat: dateFormat,
                            isAmharic: isAmharic,
                            l10n: l10n,
                          );
                        } else if (entry is CreditSaleLedgerEntry) {
                          return _buildCreditSaleCard(
                            context: context,
                            entry: entry,
                            customer: customer,
                            dateFormat: dateFormat,
                            isAmharic: isAmharic,
                            l10n: l10n,
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRepaymentCard({
    required BuildContext context,
    required RepaymentLedgerEntry entry,
    required CustomersTableData customer,
    required DateFormat dateFormat,
    required bool isAmharic,
    required AppLocalizations? l10n,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.green.shade200),
      ),
      color: Colors.green.shade50.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: Color(0xFF2E7D32)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${l10n?.repayment ?? 'REPAYMENT'} • ${dateFormat.format(entry.date)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
                Text(
                  '- ${CurrencyFormatter.format(entry.amount, isAmharic: isAmharic)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${l10n?.paymentMethod ?? 'Method'}: ${entry.paymentMethod}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (entry.note != null && entry.note!.isNotEmpty) ...[
                  Text(
                    ' | ${entry.note}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditSaleCard({
    required BuildContext context,
    required CreditSaleLedgerEntry entry,
    required CustomersTableData customer,
    required DateFormat dateFormat,
    required bool isAmharic,
    required AppLocalizations? l10n,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.red.shade200),
      ),
      color: Colors.red.shade50.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.remove_circle, size: 16, color: Colors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${l10n?.creditSale ?? 'CREDIT SALE'} • ${dateFormat.format(entry.date)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade800,
                    ),
                  ),
                ),
                Text(
                  '+ ${CurrencyFormatter.format(entry.amountDue, isAmharic: isAmharic)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Itemized line items
            if (entry.items.isNotEmpty) ...[
              for (final item in entry.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• ${item.productName} (${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)} x ${CurrencyFormatter.format(item.unitPrice, isAmharic: isAmharic)})',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ),
              const SizedBox(height: 6),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${l10n?.amountPaidNow ?? 'Paid'}: ${CurrencyFormatter.format(entry.amountPaid, isAmharic: isAmharic)} | ${l10n?.amountToCredit ?? 'To Debt'}: ${CurrencyFormatter.format(entry.amountDue, isAmharic: isAmharic)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                InkWell(
                  onTap: () {
                    final receipt = DebtReceiptFormatter.formatCreditSaleReceipt(
                      customer: customer,
                      sale: entry.sale,
                      items: entry.items,
                      previousBalance: (customer.totalDebt - entry.amountDue).clamp(0.0, double.infinity),
                      isAmharic: isAmharic,
                    );
                    showDialog(
                      context: context,
                      builder: (_) => DebtReceiptDialog(receiptText: receipt),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.share, size: 12, color: Colors.blueGrey),
                      const SizedBox(width: 2),
                      Text(
                        l10n?.shareReceipt ?? 'Receipt',
                        style: const TextStyle(fontSize: 11, color: Colors.blueGrey, decoration: TextDecoration.underline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
