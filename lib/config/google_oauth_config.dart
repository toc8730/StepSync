import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Central place to read Google OAuth client IDs that we pass via `--dart-define`.
///
/// The backend validates ID tokens against the same IDs (see README).
class GoogleOAuthConfig {
  static const String _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const String _androidClientId = String.fromEnvironment('GOOGLE_ANDROID_CLIENT_ID');
  static const String _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static String? get serverClientId {
    if (kIsWeb) return null; // web plugin rejects serverClientId entirely
    return _webClientId.isEmpty ? null : _webClientId;
  }

  static String? get platformClientId {
    if (kIsWeb && _webClientId.isNotEmpty) return _webClientId;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidClientId.isNotEmpty ? _androidClientId : null;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return _iosClientId.isNotEmpty ? _iosClientId : null;
      default:
        return null;
    }
  }

  static bool get isConfigured {
    if (_webClientId.isEmpty) return false;
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      return _iosClientId.isNotEmpty;
    }
    return true;
  }

  static String? configurationHint() {
    if (_webClientId.isEmpty) {
      return 'Set GOOGLE_WEB_CLIENT_ID via --dart-define so we can request ID tokens.';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      if (_iosClientId.isEmpty) {
        return 'Set GOOGLE_IOS_CLIENT_ID via --dart-define when running on Apple platforms.';
      }
    }
    return null;
  }
}
