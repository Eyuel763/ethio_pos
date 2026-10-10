class AppConfig {
  /// Base URL for the NestJS cloud backend.
  /// - Can be overridden via: flutter run --dart-define=API_URL=http://...
  /// - Defaults to your host PC's Wi-Fi LAN IP (192.168.1.9:3001) so your physical phone can connect directly.
  static String get defaultBaseUrl {
    const envUrl = String.fromEnvironment('API_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }
    return 'http://192.168.1.7:3001';
  }

  /// Default demo shop ID (Bole Supermarket)
  static const String defaultShopId = '2aa60dbb-e38d-4a68-add3-654cd711862f';

  /// Pre-authenticated developer token for Bole Supermarket admin
  static const String defaultDevToken =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI2OWE3ZDMzZC02ZjU1LTQyN2MtYjQyOS1hNDVkZDRkZGI5NmYiLCJ1c2VybmFtZSI6ImJvbGVfYWRtaW4iLCJzaG9wSWQiOiIyYWE2MGRiYi1lMzhkLTRhNjgtYWRkMy02NTRjZDcxMTg2MmYiLCJyb2xlIjoiYWRtaW4iLCJpYXQiOjE3OTE1MjIyNzUsImV4cCI6MTc5NDExNDI3NX0.kSJYxe_sFMIgvGKF9VXoqCtNGPNsyLQSCrYyQOHKD7k';
}
