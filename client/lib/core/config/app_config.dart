class AppConfig {
  /// Base URL for the NestJS cloud backend.
  /// - Can be overridden via: flutter run --dart-define=API_URL=http://...
  /// - Defaults to localhost for emulator / local development.
  static String get defaultBaseUrl {
    const envUrl = String.fromEnvironment('API_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }
    return 'http://192.168.1.7:3001';
  }
}

