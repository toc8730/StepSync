import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/globals.dart';

class FamilyService {
  static const String _baseUrl = 'http://127.0.0.1:5000';

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
          .where((item) => item is Map)
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

  static Map<String, dynamic> _decodeBody(String body) {
    try {
      final jsonBody = json.decode(body);
      if (jsonBody is Map<String, dynamic>) return jsonBody;
    } catch (_) {}
    return {};
  }
}

class FamilyMember {
  FamilyMember({required this.username, this.isMaster = false});

  final String username;
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
    List<FamilyMember> _parseMembers(List list, {bool parents = false}) {
      return list
          .where((element) => element is Map)
          .map((element) => Map<String, dynamic>.from(element as Map))
          .map((m) => FamilyMember(
                username: (m['username'] ?? '').toString(),
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
      parents: _parseMembers(parentsList, parents: true),
      children: _parseMembers(childrenList),
    );
  }
}

class LeaveRequestInfo {
  LeaveRequestInfo({required this.childUsername, this.requestedAt});

  final String childUsername;
  final DateTime? requestedAt;

  factory LeaveRequestInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parsed;
    final raw = json['requested_at'];
    if (raw is String && raw.isNotEmpty) {
      parsed = DateTime.tryParse(raw);
    }
    return LeaveRequestInfo(
      childUsername: (json['child_username'] ?? '').toString(),
      requestedAt: parsed,
    );
  }
}
