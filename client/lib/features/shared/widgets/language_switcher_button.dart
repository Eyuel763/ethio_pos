import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/locale_provider.dart';

class LanguageSwitcherButton extends ConsumerWidget {
  const LanguageSwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isAmharic = locale.languageCode == 'am';

    return InkWell(
      onTap: () {
        ref.read(localeProvider.notifier).toggleLocale();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'EN',
              style: TextStyle(
                fontSize: 12,
                fontWeight: !isAmharic ? FontWeight.w900 : FontWeight.normal,
                color: !isAmharic
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade600,
              ),
            ),
            const Text(' | ', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(
              'አማ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isAmharic ? FontWeight.w900 : FontWeight.normal,
                color: isAmharic
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
