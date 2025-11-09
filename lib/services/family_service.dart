import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../data/globals.dart';

class FamilyService {
  static const String _baseUrl = BackendConfig.baseUrl;

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AppGlobals.token}',
      };

  static Future<FamilyMembers?> fetchMembers() async {
    final res = await http.get(Uri.parse('$_baseUrl/family/members'), headers: _headers());
    if (res.statusCode != 200) return null;
    final body = json.decode(res.body);
    return FamilyMembers.fromJson(body as Map<String, dynamic>);
  }

  static Future<bool> removeMember(String username) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/family/member/remove'),
      headers: _headers(),
      body: json.encode({'username': username}),
    );
    return res.statusCode == 200;
  }

  static Future<bool> transferMaster(String username) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/family/master/transfer'),
      headers: _headers(),
      body: json.encode({'username': username}),
    );
    return res.statusCode == 200;
  }

  static Future<String> leaveFamily() async {
    final res = await http.post(Uri.parse('$_baseUrl/family/leave'), headers: _headers());
    final body = _decodeBody(res.body);
    if (res.statusCode == 200) {
      return (body['message'] ?? 'Request submitted.').toString();
    }
    throw Exception(body['error'] ?? 'Unable to leave the family.');
  }

  static Future<List<LeaveRequestInfo>> fetchLeaveRequests() async {
    final res = await http.get(Uri.parse('$_baseUrl/family/leave/requests'), headers: _headers());
    if (res.statusCode != 200) {
      final body = _decodeBody(res.body);
      throw Exception(body['error'] ?? 'Unable to load leave requests.');
    }
    final body = _decodeBody(res.body);
    final list = body['requests'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((item) => LeaveRequestInfo.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    return const [];
  }

  static Future<String> handleLeaveRequest(String username, bool approve) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/family/leave/requests/handle'),
      headers: _headers(),
      body: json.encode({
        'child_username': username,
        'action': approve ? 'approve' : 'reject',
      }),
    );
    final body = _decodeBody(res.body);
    if (res.statusCode == 200) {
      return (body['message'] ?? 'Request updated.').toString();
    }
    throw Exception(body['error'] ?? 'Unable to update leave request.');
  }

  static Future<String> updateFamily({
    String? newName,
    String? newPassword,
    required String currentPassword,
  }) async {
    final payload = <String, String>{
      'current_password': currentPassword,
      if (newName != null && newName.trim().isNotEmpty) 'name': newName.trim(),
      if (newPassword != null && newPassword.isNotEmpty) 'new_password': newPassword,
    };

    final res = await http.post(
      Uri.parse('$_baseUrl/family/update'),
      headers: _headers(),
      body: json.encode(payload),
    );
    final body = _decodeBody(res.body);
    if (res.statusCode == 200) {
      return (body['message'] ?? 'Family updated.').toString();
    }
    throw Exception(body['error'] ?? 'Unable to update family.');
  }

  static Map<String, dynamic> _decodeBody(String body) {
    try {
      final jsonBody = json.decode(body);
      if (jsonBody is Map<String, dynamic>) return jsonBody;
    } catch (_) {}
    return {};
  }

  static Future<bool> sendInvite(String childUsername) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/family/invite'),
      headers: _headers(),
      body: json.encode({'child_username': childUsername}),
    );
    if (res.statusCode == 200) {
      return true;
    }
    final body = _decodeBody(res.body);
    throw Exception(body['error'] ?? 'Unable to send invite.');
  }

  static Future<List<FamilyInviteInfo>> fetchChildInvites() async {
    final res = await http.get(Uri.parse('$_baseUrl/family/invite/my'), headers: _headers());
    if (res.statusCode != 200) {
      final body = _decodeBody(res.body);
      throw Exception(body['error'] ?? 'Unable to load invites.');
    }
    final body = _decodeBody(res.body);
    final list = body['invites'];
    if (list is List) {
      return list
          .where((item) => item is Map)
          .map((item) => FamilyInviteInfo.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    return const [];
  }

  static Future<bool> respondToInvite({
    required String familyId,
    required bool accept,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/family/invite/respond'),
      headers: _headers(),
      body: json.encode({
        'family_id': familyId,
        'action': accept ? 'accept' : 'reject',
      }),
    );
    if (res.statusCode == 200) return true;
    final body = _decodeBody(res.body);
    throw Exception(body['error'] ?? 'Unable to update invite.');
  }
}

class FamilyMember {
  const FamilyMember({required this.username, required this.displayName, this.isMaster = false});

  final String username;
  final String displayName;
  final bool isMaster;
}

class FamilyMembers {
  FamilyMembers({
    required this.familyId,
    required this.isMaster,
    required this.parents,
    required this.children,
    required this.pendingRequests,
  });

  final String familyId;
  final bool isMaster;
  final int pendingRequests;
  final List<FamilyMember> parents;
  final List<FamilyMember> children;

  factory FamilyMembers.fromJson(Map<String, dynamic> json) {
    List<FamilyMember> parseMembers(List list, {bool parents = false}) {
      return list
          .whereType<Map>()
          .map((element) => Map<String, dynamic>.from(element as Map))
          .map((m) => FamilyMember(
                username: (m['username'] ?? '').toString(),
                displayName: FamilyMembers._cleanName(m['display_name'], fallback: m['username']),
                isMaster: parents ? (m['is_master'] == true) : false,
              ))
          .where((m) => m.username.isNotEmpty)
          .toList();
    }

    final parentsList = json['parents'] is List ? json['parents'] as List : const [];
    final childrenList = json['children'] is List ? json['children'] as List : const [];

    return FamilyMembers(
      familyId: (json['family_id'] ?? '').toString(),
      isMaster: json['is_master'] == true,
      pendingRequests: json['pending_leave_requests'] is int ? json['pending_leave_requests'] as int : 0,
      parents: parseMembers(parentsList, parents: true),
      children: parseMembers(childrenList),
    );
  }

  static String _cleanName(Object? raw, {Object? fallback}) {
    final primary = (raw ?? '').toString().trim();
    if (primary.isNotEmpty) return primary;
    final fb = (fallback ?? '').toString().trim();
    return fb.isEmpty ? '—' : fb;
  }
}

class LeaveRequestInfo {
  LeaveRequestInfo({required this.childUsername, required this.displayName, this.requestedAt});

  final String childUsername;
  final String displayName;
  final DateTime? requestedAt;

  factory LeaveRequestInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parsed;
    final raw = json['requested_at'];
    if (raw is String && raw.isNotEmpty) {
      parsed = DateTime.tryParse(raw);
    }
    return LeaveRequestInfo(
      childUsername: (json['child_username'] ?? '').toString(),
      displayName: FamilyMembers._cleanName(json['display_name'], fallback: json['child_username']),
      requestedAt: parsed,
    );
  }
}

class FamilyInviteInfo {
  FamilyInviteInfo({required this.familyId, required this.familyName, this.requestedAt});

  final String familyId;
  final String familyName;
  final DateTime? requestedAt;

  factory FamilyInviteInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parsed;
    final raw = json['created_at'];
    if (raw is String && raw.isNotEmpty) {
      parsed = DateTime.tryParse(raw);
    }
    return FamilyInviteInfo(
      familyId: (json['family_id'] ?? '').toString(),
      familyName: (json['family_name'] ?? '').toString(),
      requestedAt: parsed,
    );
  }
}
