import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier to toggle and manage active language across the app without restart.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    // Default to Amharic as primary target locale for local Ethiopian shopkeepers
    return const Locale('am');
  }

  void setLocale(Locale locale) {
    state = locale;
  }

  void toggleLocale() {
    state = state.languageCode == 'am' ? const Locale('en') : const Locale('am');
  }

  bool get isAmharic => state.languageCode == 'am';
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
