class BackendConfig {
  static const String _remoteDefault = 'https://stepsync.xyz';
  static const String _localDefault = 'http://127.0.0.1:5000';

  static const bool _useRemote = bool.fromEnvironment('USE_REMOTE_BACKEND', defaultValue: true);

  static const String baseUrl = _useRemote
      ? String.fromEnvironment('REMOTE_BACKEND_URL', defaultValue: _remoteDefault)
      : String.fromEnvironment('LOCAL_BACKEND_URL', defaultValue: _localDefault);

  static Uri uri(String path) => Uri.parse('$baseUrl$path');
}
