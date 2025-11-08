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
}

class FamilyMember {
  FamilyMember({required this.username, this.isMaster = false});

  final String username;
  final bool isMaster;
}

class FamilyMembers {
  FamilyMembers({required this.familyId, required this.isMaster, required this.parents, required this.children});

  final String familyId;
  final bool isMaster;
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
      parents: _parseMembers(parentsList, parents: true),
      children: _parseMembers(childrenList),
    );
  }
}
