import 'package:intl/intl.dart';
import 'package:client/core/database/app_database.dart';
import 'package:client/core/utils/formatters.dart';

class DebtReceiptFormatter {
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy hh:mm a');

  /// Formats a complete customer debt balance statement for Telegram / SMS sharing
  static String formatCustomerDebtSummary({
    required CustomersTableData customer,
    String shopName = 'EthioPOS Store',
  }) {
    final nowFormatted = _dateFormat.format(DateTime.now());
    final balanceEn = CurrencyFormatter.format(customer.totalDebt, isAmharic: false);
    final balanceAm = CurrencyFormatter.format(customer.totalDebt, isAmharic: true);

    final buffer = StringBuffer();
    buffer.writeln('=================================');
    buffer.writeln('          $shopName');
    buffer.writeln('    የብድር ደረሰኝ (Debt Statement)');
    buffer.writeln('=================================');
    buffer.writeln('ደንበኛ (Customer): ${customer.fullName}');
    if (customer.phoneNumber != null && customer.phoneNumber!.isNotEmpty) {
      buffer.writeln('ስልክ (Phone): ${customer.phoneNumber}');
    }
    buffer.writeln('ቀን (Date): $nowFormatted');
    buffer.writeln('---------------------------------');
    buffer.writeln('አሁን ያለዎት ጠቅላላ ያልተከፈለ ዕዳ:');
    buffer.writeln('👉 $balanceEn ($balanceAm)');
    buffer.writeln('=================================');
    buffer.writeln('እናመሰግናለን! (Thank you!)');

    return buffer.toString();
  }

  /// Formats a specific credit sale receipt with purchased items
  static String formatCreditSaleReceipt({
    required CustomersTableData customer,
    required SalesTableData sale,
    required List<SaleItemsTableData> items,
    required double previousBalance,
    String shopName = 'EthioPOS Store',
    bool isAmharic = true,
  }) {
    final dateFormatted = _dateFormat.format(sale.createdAt);
    final subtotalStr = CurrencyFormatter.format(sale.subtotal, isAmharic: isAmharic);
    final paidStr = CurrencyFormatter.format(sale.amountPaid, isAmharic: isAmharic);
    final addedToDebtStr = CurrencyFormatter.format(sale.amountDue, isAmharic: isAmharic);
    final prevBalanceStr = CurrencyFormatter.format(previousBalance, isAmharic: isAmharic);
    final newBalanceStr = CurrencyFormatter.format(previousBalance + sale.amountDue, isAmharic: isAmharic);

    final buffer = StringBuffer();
    buffer.writeln('=================================');
    buffer.writeln('          $shopName');
    buffer.writeln('    የብድር ደረሰኝ (Debt Receipt)');
    buffer.writeln('=================================');
    buffer.writeln('ደንበኛ (Customer): ${customer.fullName}');
    buffer.writeln('ቀን (Date): $dateFormatted');
    buffer.writeln('');
    buffer.writeln('የተገዙ ዕቃዎች (Items Purchased):');
    for (final item in items) {
      final unitPriceStr = CurrencyFormatter.format(item.unitPrice, isAmharic: isAmharic);
      buffer.writeln('• ${item.productName} (${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)} x $unitPriceStr)');
    }
    buffer.writeln('---------------------------------');
    buffer.writeln('ጠቅላላ (Subtotal): $subtotalStr');
    buffer.writeln('የተከፈለ (Paid Now): $paidStr');
    buffer.writeln('ወደ ዕዳ የተዛወረ (Added to Debt): $addedToDebtStr');
    buffer.writeln('---------------------------------');
    buffer.writeln('የቀደመ ዕዳ (Previous Balance): $prevBalanceStr');
    buffer.writeln('አሁን ያለዎት ጠቅላላ ዕዳ (NEW TOTAL BALANCE): $newBalanceStr');
    buffer.writeln('=================================');
    buffer.writeln('እናመሰግናለን! (Thank you!)');

    return buffer.toString();
  }

  /// Formats a repayment receipt
  static String formatRepaymentReceipt({
    required CustomersTableData customer,
    required DebtRepaymentsTableData repayment,
    required double previousBalance,
    String shopName = 'EthioPOS Store',
    bool isAmharic = true,
  }) {
    final dateFormatted = _dateFormat.format(repayment.createdAt);
    final amountPaidStr = CurrencyFormatter.format(repayment.amount, isAmharic: isAmharic);
    final prevBalanceStr = CurrencyFormatter.format(previousBalance, isAmharic: isAmharic);
    final remainingDebt = (previousBalance - repayment.amount).clamp(0.0, double.infinity);
    final remainingStr = CurrencyFormatter.format(remainingDebt, isAmharic: isAmharic);

    final buffer = StringBuffer();
    buffer.writeln('=================================');
    buffer.writeln('          $shopName');
    buffer.writeln('   የዕዳ ክፍያ ደረሰኝ (Repayment Receipt)');
    buffer.writeln('=================================');
    buffer.writeln('ደንበኛ (Customer): ${customer.fullName}');
    buffer.writeln('ቀን (Date): $dateFormatted');
    buffer.writeln('የክፍያ ዘዴ (Method): ${repayment.paymentMethod}');
    if (repayment.note != null && repayment.note!.isNotEmpty) {
      buffer.writeln('ማስታወሻ (Note): ${repayment.note}');
    }
    buffer.writeln('---------------------------------');
    buffer.writeln('የተከፈለ (Amount Paid): $amountPaidStr');
    buffer.writeln('የቀደመ ዕዳ (Previous Debt): $prevBalanceStr');
    buffer.writeln('የሚቀረው ዕዳ (REMAINING DEBT): $remainingStr');
    buffer.writeln('=================================');
    buffer.writeln('እናመሰግናለን! (Thank you!)');

    return buffer.toString();
  }
}
