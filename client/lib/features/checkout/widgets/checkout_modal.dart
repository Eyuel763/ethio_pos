import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/utils/formatters.dart';
import '../providers/cart_provider.dart';
import 'package:client/l10n/app_localizations.dart';

class CheckoutModal extends ConsumerStatefulWidget {
  const CheckoutModal({super.key});

  @override
  ConsumerState<CheckoutModal> createState() => _CheckoutModalState();
}

class _CheckoutModalState extends ConsumerState<CheckoutModal> {
  String _paymentType = 'cash'; // 'cash', 'mobile_transfer', 'credit'
  String? _selectedCustomerId;
  final TextEditingController _amountPaidController = TextEditingController();
  final TextEditingController _newCustomerNameController = TextEditingController();
  final TextEditingController _newCustomerPhoneController = TextEditingController();
  bool _isCreatingCustomer = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final grandTotal = ref.read(cartProvider).grandTotal;
    _amountPaidController.text = grandTotal.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountPaidController.dispose();
    _newCustomerNameController.dispose();
    _newCustomerPhoneController.dispose();
    super.dispose();
  }

  void _onPaymentTypeChanged(String type) {
    setState(() {
      _paymentType = type;
      final grandTotal = ref.read(cartProvider).grandTotal;
      if (type == 'credit') {
        _amountPaidController.text = '0.00';
      } else {
        _amountPaidController.text = grandTotal.toStringAsFixed(2);
      }
    });
  }

  Future<void> _handleConfirmSale() async {
    final cart = ref.read(cartProvider);
    if (cart.items.isEmpty) return;

    final db = ref.read(databaseProvider);
    final shopId = ref.read(shopIdProvider);
    final grandTotal = cart.grandTotal;
    final isAmharic = ref.read(localeProvider.notifier).isAmharic;

    double amountPaid = double.tryParse(_amountPaidController.text) ?? 0.0;
    if (_paymentType != 'credit') {
      amountPaid = grandTotal;
    }
    final amountDue = (grandTotal - amountPaid).clamp(0.0, double.infinity);

    // If credit tab selected, customer is mandatory
    if (_paymentType == 'credit' && _selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAmharic ? 'እባክዎ ደንበኛ ይምረጡ ወይም ይመዝግቡ' : 'Please select or add a customer for credit'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final saleId = UuidUtil.generate();
      final saleItemsCompanions = <SaleItemsTableCompanion>[];
      final syncItemsPayload = <Map<String, dynamic>>[];

      for (final item in cart.itemList) {
        final itemId = UuidUtil.generate();
        saleItemsCompanions.add(
          SaleItemsTableCompanion.insert(
            id: itemId,
            saleId: saleId,
            productId: item.product.id,
            productName: isAmharic ? item.product.nameAm : item.product.nameEn,
            unitPrice: item.customUnitPrice,
            quantity: item.quantity,
            totalPrice: item.totalPrice,
          ),
        );

        syncItemsPayload.add({
          'id': itemId,
          'product_id': item.product.id,
          'product_name': isAmharic ? item.product.nameAm : item.product.nameEn,
          'unit_price': item.customUnitPrice,
          'quantity': item.quantity,
          'total_price': item.totalPrice,
        });
      }

      final saleCompanion = SalesTableCompanion.insert(
        id: saleId,
        shopId: shopId,
        customerId: drift.Value(_selectedCustomerId),
        paymentType: _paymentType,
        subtotal: cart.subtotal,
        discount: drift.Value(cart.discount),
        grandTotal: grandTotal,
        amountPaid: amountPaid,
        amountDue: amountDue,
        createdAt: drift.Value(DateTime.now()),
      );

      final syncPayloadMap = {
        'id': saleId,
        'customer_id': _selectedCustomerId,
        'payment_type': _paymentType,
        'subtotal': cart.subtotal,
        'discount': cart.discount,
        'grand_total': grandTotal,
        'amount_paid': amountPaid,
        'amount_due': amountDue,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'items': syncItemsPayload,
      };

      // Atomic SQLite write: Sale + Items + Stock decrement + Debt update + SyncQueue
      await db.recordSaleAtomic(
        sale: saleCompanion,
        items: saleItemsCompanions,
        syncPayloadJson: jsonEncode(syncPayloadMap),
      );

      // Trigger background sync asynchronously (non-blocking)
      ref.read(syncManagerProvider).triggerSync();

      // Clear cart
      ref.read(cartProvider.notifier).clearCart();

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAmharic
                ? 'ሽያጭ በተሳካ ሁኔታ ተጠናቋል!'
                : 'Sale completed successfully!',
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error recording sale: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleCreateCustomer() async {
    final name = _newCustomerNameController.text.trim();
    if (name.isEmpty) return;

    final db = ref.read(databaseProvider);
    final shopId = ref.read(shopIdProvider);
    final newId = UuidUtil.generate();
    final phone = _newCustomerPhoneController.text.trim().isNotEmpty
        ? _newCustomerPhoneController.text.trim()
        : null;

    await db.upsertCustomer(
      CustomersTableCompanion.insert(
        id: newId,
        shopId: shopId,
        fullName: name,
        phoneNumber: drift.Value(phone),
        totalDebt: const drift.Value(0.0),
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
        }),
      ),
    );

    setState(() {
      _selectedCustomerId = newId;
      _isCreatingCustomer = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final customersAsync = ref.watch(customersStreamProvider);
    final isAmharic = ref.watch(localeProvider.notifier).isAmharic;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final grandTotal = cart.grandTotal;
    final paidAmount = double.tryParse(_amountPaidController.text) ?? 0.0;
    final amountDue = (grandTotal - paidAmount).clamp(0.0, double.infinity);

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Title & Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n?.paymentMethod ?? 'Payment Method',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  CurrencyFormatter.format(grandTotal, isAmharic: isAmharic),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Payment Types Selector
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    avatar: const Icon(Icons.money, size: 18),
                    label: Text(l10n?.cash ?? 'Cash'),
                    selected: _paymentType == 'cash',
                    onSelected: (_) => _onPaymentTypeChanged('cash'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    avatar: const Icon(Icons.phone_android, size: 18),
                    label: Text(isAmharic ? 'ሞባይል' : 'Mobile'),
                    selected: _paymentType == 'mobile_transfer',
                    onSelected: (_) => _onPaymentTypeChanged('mobile_transfer'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    avatar: const Icon(Icons.assignment, size: 18),
                    label: Text(isAmharic ? 'ዕዳ' : 'Credit'),
                    selected: _paymentType == 'credit',
                    onSelected: (_) => _onPaymentTypeChanged('credit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Credit Options Section
            if (_paymentType == 'credit') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n?.selectCustomer ?? 'Select Customer',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          icon: Icon(_isCreatingCustomer ? Icons.close : Icons.person_add, size: 16),
                          label: Text(_isCreatingCustomer ? (isAmharic ? 'ሰርዝ' : 'Cancel') : (isAmharic ? 'አዲስ' : 'New')),
                          onPressed: () {
                            setState(() => _isCreatingCustomer = !_isCreatingCustomer);
                          },
                        ),
                      ],
                    ),
                    if (_isCreatingCustomer) ...[
                      TextField(
                        controller: _newCustomerNameController,
                        decoration: InputDecoration(
                          labelText: isAmharic ? 'የደንበኛ ሙሉ ስም' : 'Customer Full Name',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _newCustomerPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: isAmharic ? 'ስልክ ቁጥር' : 'Phone Number',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _handleCreateCustomer,
                        child: Text(isAmharic ? 'መዝግብ' : 'Add Customer'),
                      ),
                    ] else ...[
                      customersAsync.when(
                        data: (customers) {
                          if (customers.isEmpty) {
                            return Text(isAmharic ? 'ደንበኛ የለም። አዲስ መዝግብ।' : 'No customers yet. Tap New.');
                          }
                          return DropdownButtonFormField<String>(
                            initialValue: _selectedCustomerId,
                            isExpanded: true,
                            hint: Text(isAmharic ? 'ደንበኛ ምረጥ' : 'Select Customer'),
                            items: customers.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text('${c.fullName} (${c.phoneNumber ?? ""}) - ${CurrencyFormatter.format(c.totalDebt, isAmharic: isAmharic)}'),
                            )).toList(),
                            onChanged: (id) => setState(() => _selectedCustomerId = id),
                          );
                        },
                        loading: () => const CircularProgressIndicator(),
                        error: (err, _) => Text('Error: $err'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountPaidController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: l10n?.amountPaidNow ?? 'Amount Paid Now',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n?.amountToCredit ?? 'To Credit:', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              Text(
                                CurrencyFormatter.format(amountDue, isAmharic: isAmharic),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n?.cancel ?? 'Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _isSubmitting ? null : _handleConfirmSale,
                    child: _isSubmitting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(
                            l10n?.confirmSale ?? 'CONFIRM SALE',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
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
