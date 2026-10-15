import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class CurrencyFormatter {
  static final NumberFormat _etbFormat = NumberFormat('#,##0.00', 'en_US');

  /// Formats amount in ETB.
  /// Example: format(1450.5, isAmharic: false) -> "1,450.50 ETB"
  /// Example: format(1450.5, isAmharic: true) -> "1,450.50 ብር"
  static String format(double amount, {bool isAmharic = false}) {
    final formattedNumber = _etbFormat.format(amount);
    return isAmharic ? '$formattedNumber ብር' : '$formattedNumber ETB';
  }
}

class UuidUtil {
  static const Uuid _uuid = Uuid();

  /// Generates a standardized v4 UUID string.
  static String generate() => _uuid.v4();
}

/// Helper class to localize standard product categories into Amharic and English.
class CategoryLocalizer {
  static String getLocalizedName(String category, {required bool isAmharic}) {
    switch (category.toLowerCase()) {
      case 'general':
        return isAmharic ? 'አጠቃላይ' : 'General';
      case 'groceries':
      case 'grocery':
        return isAmharic ? 'የሸቀጣ ሸቀጥ' : 'Groceries';
      case 'bakery':
        return isAmharic ? 'ዳቦና መጋገሪያ' : 'Bakery';
      case 'dairy':
        return isAmharic ? 'የወተት ተዋጽኦ' : 'Dairy';
      case 'beverages':
      case 'drinks':
        return isAmharic ? 'መጠጦች' : 'Beverages';
      case 'spices':
      case 'spice':
        return isAmharic ? 'ቅመማ ቅመም' : 'Spices';
      case 'fresh':
      case 'produce':
        return isAmharic ? 'አትክልትና ፍራፍሬ' : 'Fresh / Produce';
      case 'household':
        return isAmharic ? 'የቤት ውስጥ ዕቃዎች' : 'Household';
      default:
        return category;
    }
  }
}

