import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Central place to read Google OAuth client IDs that we pass via `--dart-define`.
///
/// The backend validates ID tokens against the same IDs (see README).
class GoogleOAuthConfig {
  static const String _rawWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const String _rawAndroidClientId = String.fromEnvironment('GOOGLE_ANDROID_CLIENT_ID');
  static const String _rawIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static final String _webClientId = _normalize(_rawWebClientId);
  static final String _androidClientId = _normalize(_rawAndroidClientId);
  static final String _iosClientId = _normalize(_rawIosClientId);

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
      if (_rawWebClientId.trim().isEmpty) {
        return 'Set GOOGLE_WEB_CLIENT_ID via --dart-define so we can request ID tokens.';
      }
      if (_looksPlaceholder(_rawWebClientId)) {
        return 'Replace the placeholder GOOGLE_WEB_CLIENT_ID with your real OAuth client ID.';
      }
      return 'Verify GOOGLE_WEB_CLIENT_ID is valid.';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      if (_iosClientId.isEmpty) {
        if (_rawIosClientId.trim().isEmpty) {
          return 'Set GOOGLE_IOS_CLIENT_ID via --dart-define when running on Apple platforms.';
        }
        if (_looksPlaceholder(_rawIosClientId)) {
          return 'Replace the placeholder GOOGLE_IOS_CLIENT_ID with the value from Google Cloud.';
        }
        return 'Verify GOOGLE_IOS_CLIENT_ID is valid.';
      }
    }
    return null;
  }

  static bool _looksPlaceholder(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return true;
    return trimmed.startsWith('your-') || trimmed.contains('example') || trimmed.contains('placeholder');
  }

  static String _normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (_looksPlaceholder(trimmed)) return '';
    return trimmed;
  }
}
