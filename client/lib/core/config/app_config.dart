import 'dart:io';

class AppConfig {
  /// Base URL for the NestJS cloud backend.
  /// Android emulator uses 10.0.2.2 to reach the host machine.
  /// Physical devices should set this to the host machine's LAN IP.
  static String get defaultBaseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3001';
    }
    return 'http://localhost:3001';
  }
}
