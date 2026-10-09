import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/features/shared/widgets/language_switcher_button.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/core/providers/locale_provider.dart';

void main() {
  testWidgets('LanguageSwitcherButton toggles locale state', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
          final locale = ref.watch(localeProvider);
          return MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              appBar: AppBar(
                title: Text(locale.languageCode == 'am' ? 'ኢትዮ ፖስ' : 'EthioPOS'),
                actions: const [
                  LanguageSwitcherButton(),
                ],
              ),
            ),
          );
        },
      ),
    ));

    // Initial language is Amharic
    expect(find.text('ኢትዮ ፖስ'), findsOneWidget);

    // Tap toggle
    await tester.tap(find.byType(LanguageSwitcherButton));
    await tester.pump();

    // Switched to English
    expect(find.text('EthioPOS'), findsOneWidget);
  });
}
