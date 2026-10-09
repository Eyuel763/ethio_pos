import 'package:client/core/database/app_database.dart';

sealed class LedgerEntry {
  final DateTime date;
  final String id;

  const LedgerEntry({required this.id, required this.date});
}

class CreditSaleLedgerEntry extends LedgerEntry {
  final SalesTableData sale;
  final List<SaleItemsTableData> items;

  const CreditSaleLedgerEntry({
    required super.id,
    required super.date,
    required this.sale,
    required this.items,
  });

  double get amountDue => sale.amountDue;
  double get grandTotal => sale.grandTotal;
  double get amountPaid => sale.amountPaid;
}

class RepaymentLedgerEntry extends LedgerEntry {
  final DebtRepaymentsTableData repayment;

  const RepaymentLedgerEntry({
    required super.id,
    required super.date,
    required this.repayment,
  });

  double get amount => repayment.amount;
  String get paymentMethod => repayment.paymentMethod;
  String? get note => repayment.note;
}
