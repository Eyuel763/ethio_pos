import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/providers/database_providers.dart';
import 'core/sync/sync_manager.dart';
import 'core/sync/sync_providers.dart';
import 'core/utils/formatters.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: EthioPosTestApp()));
}

class EthioPosTestApp extends StatelessWidget {
  const EthioPosTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EthioPOS - Phase 3 Verification',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B)),
        useMaterial3: true,
      ),
      home: const Phase3VerificationScreen(),
    );
  }
}

class Phase3VerificationScreen extends ConsumerStatefulWidget {
  const Phase3VerificationScreen({super.key});

  @override
  ConsumerState<Phase3VerificationScreen> createState() => _Phase3VerificationScreenState();
}

class _Phase3VerificationScreenState extends ConsumerState<Phase3VerificationScreen> {
  final TextEditingController _serverIpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Default to the computer's LAN IP for physical device connection
    _serverIpController.text = AppConfig.defaultBaseUrl;
  }

  @override
  void dispose() {
    _serverIpController.dispose();
    super.dispose();
  }

  void _updateServerUrl() {
    final newUrl = _serverIpController.text.trim();
    final dio = ref.read(dioProvider);
    dio.options.baseUrl = newUrl;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated Backend URL to: $newUrl')),
    );
  }

  Future<void> _seedLocalSampleData() async {
    final db = ref.read(databaseProvider);
    final prodId = UuidUtil.generate();
    final custId = UuidUtil.generate();

    // 1. Seed Product
    await db.upsertProduct(
      ProductsTableCompanion.insert(
        id: prodId,
        shopId: ref.read(shopIdProvider),
        nameAm: 'ዘይት 5L',
        nameEn: '5L Cooking Oil',
        sellingPrice: 450.0,
        costPrice: const drift.Value(380.0),
        stockQuantity: const drift.Value(20.0),
        minStockLevel: const drift.Value(5.0),
        category: const drift.Value('Groceries'),
      ),
    );

    // 2. Seed Customer
    await db.upsertCustomer(
      CustomersTableCompanion.insert(
        id: custId,
        shopId: ref.read(shopIdProvider),
        fullName: 'Kebede Tadesse',
        phoneNumber: const drift.Value('0911223344'),
        totalDebt: const drift.Value(0.0),
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seeded local Product (20 pcs) & Customer!')),
      );
    }
  }

  Future<void> _testAtomicCashSale() async {
    final db = ref.read(databaseProvider);
    final products = await db.select(db.productsTable).get();
    if (products.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please seed local data first!')),
      );
      return;
    }

    final product = products.first;
    final saleId = UuidUtil.generate();
    final saleItemId = UuidUtil.generate();

    // Record atomic sale: sell 2 units for cash
    await db.recordSaleAtomic(
      sale: SalesTableCompanion.insert(
        id: saleId,
        shopId: ref.read(shopIdProvider),
        paymentType: 'cash',
        subtotal: product.sellingPrice * 2,
        grandTotal: product.sellingPrice * 2,
        amountPaid: product.sellingPrice * 2,
        amountDue: 0.0,
      ),
      items: [
        SaleItemsTableCompanion.insert(
          id: saleItemId,
          saleId: saleId,
          productId: product.id,
          productName: product.nameEn,
          unitPrice: product.sellingPrice,
          quantity: 2.0,
          totalPrice: product.sellingPrice * 2,
        ),
      ],
      syncPayloadJson: '{"id":"$saleId","payment_type":"cash","subtotal":${product.sellingPrice * 2},"discount":0,"grand_total":${product.sellingPrice * 2},"amount_paid":${product.sellingPrice * 2},"amount_due":0,"items":[{"id":"$saleItemId","product_id":"${product.id}","product_name":"${product.nameEn}","unit_price":${product.sellingPrice},"quantity":2.0,"total_price":${product.sellingPrice * 2}}]}',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recorded Sale: Stock decremented by 2 & queued to Outbox!')),
    );
  }

  Future<void> _testAtomicCreditSale() async {
    final db = ref.read(databaseProvider);
    final products = await db.select(db.productsTable).get();
    final customers = await db.select(db.customersTable).get();
    if (products.isEmpty || customers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please seed local data first!')),
      );
      return;
    }

    final product = products.first;
    final customer = customers.first;
    final saleId = UuidUtil.generate();
    final saleItemId = UuidUtil.generate();

    // Record atomic credit sale: 1 unit, paid 100, due 350
    await db.recordSaleAtomic(
      sale: SalesTableCompanion.insert(
        id: saleId,
        shopId: ref.read(shopIdProvider),
        customerId: drift.Value(customer.id),
        paymentType: 'credit',
        subtotal: product.sellingPrice,
        grandTotal: product.sellingPrice,
        amountPaid: 100.0,
        amountDue: product.sellingPrice - 100.0,
      ),
      items: [
        SaleItemsTableCompanion.insert(
          id: saleItemId,
          saleId: saleId,
          productId: product.id,
          productName: product.nameEn,
          unitPrice: product.sellingPrice,
          quantity: 1.0,
          totalPrice: product.sellingPrice,
        ),
      ],
      syncPayloadJson: '{"id":"$saleId","customer_id":"${customer.id}","payment_type":"credit","subtotal":${product.sellingPrice},"discount":0,"grand_total":${product.sellingPrice},"amount_paid":100.0,"amount_due":${product.sellingPrice - 100.0},"items":[{"id":"$saleItemId","product_id":"${product.id}","product_name":"${product.nameEn}","unit_price":${product.sellingPrice},"quantity":1.0,"total_price":${product.sellingPrice}}]}',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Credit Sale: Customer debt updated to +${CurrencyFormatter.format(product.sellingPrice - 100)}!')),
    );
  }

  Future<void> _triggerManualSync() async {
    final syncManager = ref.read(syncManagerProvider);
    await syncManager.triggerSync();
  }

  @override
  Widget build(BuildContext context) {
    final syncStateAsync = ref.watch(syncStateStreamProvider);
    final productsAsync = ref.watch(productsStreamProvider);
    final customersAsync = ref.watch(customersStreamProvider);

    final syncState = syncStateAsync.value ?? ref.read(syncManagerProvider).currentState;

    Color statusColor;
    String statusText;
    switch (syncState.status) {
      case SyncStatus.synced:
        statusColor = Colors.green;
        statusText = '● Synced';
        break;
      case SyncStatus.syncing:
        statusColor = Colors.orange;
        statusText = '● Syncing...';
        break;
      case SyncStatus.offline:
        statusColor = Colors.grey;
        statusText = '○ Offline';
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('EthioPOS Phase 3 Lab'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Icon(Icons.circle, size: 14, color: statusColor),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(fontWeight: FontWeight.bold, color: statusColor),
                ),
              ],
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Backend URL Configuration Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Backend API URL (NestJS)', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _serverIpController,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              hintText: 'http://192.168.1.9:3001',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _updateServerUrl,
                          child: const Text('Set URL'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Outbox Queue: ${syncState.pendingCount} pending mutations',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. Action Test Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_box),
                    label: const Text('Seed Local Data'),
                    onPressed: _seedLocalSampleData,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.sync),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    label: const Text('Trigger Sync'),
                    onPressed: _triggerManualSync,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.point_of_sale),
                    label: const Text('Cash Sale (-2 Stock)'),
                    onPressed: _testAtomicCashSale,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Credit Sale (+ Debt)'),
                    onPressed: _testAtomicCreditSale,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 3. Local SQLite Products List
            const Text('Local SQLite Products (Drift):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No local products yet. Tap "Seed Local Data".')));
                }
                return Column(
                  children: products.map((p) => Card(
                    child: ListTile(
                      title: Text('${p.nameEn} (${p.nameAm})'),
                      subtitle: Text('Price: ${CurrencyFormatter.format(p.sellingPrice)}'),
                      trailing: Text(
                        'Stock: ${p.stockQuantity.toStringAsFixed(1)} pcs',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: p.stockQuantity <= p.minStockLevel ? Colors.red : Colors.green,
                        ),
                      ),
                    ),
                  )).toList(),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (err, _) => Text('Error loading products: $err'),
            ),

            const SizedBox(height: 16),

            // 4. Local SQLite Customers List
            const Text('Local SQLite Customers / Ledger (ዕዳ):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            customersAsync.when(
              data: (customers) {
                if (customers.isEmpty) {
                  return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No local customers yet. Tap "Seed Local Data".')));
                }
                return Column(
                  children: customers.map((c) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(c.fullName),
                      subtitle: Text('Phone: ${c.phoneNumber ?? "N/A"}'),
                      trailing: Text(
                        'Debt: ${CurrencyFormatter.format(c.totalDebt)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: c.totalDebt > 0 ? Colors.red : Colors.grey,
                        ),
                      ),
                    ),
                  )).toList(),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (err, _) => Text('Error loading customers: $err'),
            ),
          ],
        ),
      ),
    );
  }
}
