class BackendConfig {
  static const String _remoteDefault = 'http://ec2-3-128-90-65.us-east-2.compute.amazonaws.com';
  static const String _localDefault = 'http://127.0.0.1:5000';

  static const bool _useRemote = bool.fromEnvironment('USE_REMOTE_BACKEND', defaultValue: true);

  static const String baseUrl = _useRemote
      ? String.fromEnvironment('REMOTE_BACKEND_URL', defaultValue: _remoteDefault)
      : String.fromEnvironment('LOCAL_BACKEND_URL', defaultValue: _localDefault);

  static Uri uri(String path) => Uri.parse('$baseUrl$path');
}
