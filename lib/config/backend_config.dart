class BackendConfig {
  static const String baseUrl = 'http://ec2-3-128-90-65.us-east-2.compute.amazonaws.com';

  static Uri uri(String path) => Uri.parse('$baseUrl$path');
}
