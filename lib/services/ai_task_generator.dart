import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/task.dart';

/// Calls the Firebase Callable Function `generateTasksFromPrompt`
/// (deployed in us-central1 by default) and converts the response
/// into a list of `Task` objects used by the app.
///
/// This client signs the user in **anonymously** if not already
/// authenticated so the callable receives `ctx.auth` and passes
/// your server's auth check.
class AiTaskGenerator {
  /// Change this if you deployed the function in a different region.
  static const String _region = 'us-central1';

  /// The exported callable name in your Cloud Functions code.
  static const String _fnName = 'generateTasksFromPrompt';

  /// Build the exact HTTPS endpoint for the callable.
  static String _callableUrl() {
    final projectId = Firebase.app().options.projectId;
    return 'https://$_region-$projectId.cloudfunctions.net/$_fnName';
  }

  /// Ensures there is a Firebase user (anonymous is fine).
  static Future<void> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }

  /// Ask the backend to generate tasks for a natural-language [prompt].
  ///
  /// Throws [FirebaseFunctionsException] with a helpful message if the
  /// server reports an error (e.g., INTERNAL, unauthenticated, etc.).
  static Future<List<Task>> fromPrompt(String prompt) async {
    await _ensureSignedIn();

    if (prompt.trim().isEmpty) {
      throw FirebaseFunctionsException(
        code: 'invalid-argument',
        message: 'Prompt cannot be empty.',
      );
    }

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallableFromUrl(_callableUrl());

      final res = await callable.call(<String, dynamic>{'prompt': prompt});
      final data = (res.data ?? <String, dynamic>{});

      return _decodeTasks(data);
    } on FirebaseFunctionsException catch (e) {
      // Surface the most useful message/details to the UI.
      final msg = e.message ??
          (e.details is Map
              ? ((e.details as Map)['error']?.toString() ??
                  (e.details as Map)['message']?.toString())
              : null) ??
          e.code;

      debugPrint(
          'Functions error: code=${e.code}, message=$msg, details=${e.details}');
      throw FirebaseFunctionsException(code: e.code, message: msg, details: e.details);
    } catch (e) {
      debugPrint('Unknown error calling $_fnName: $e');
      throw FirebaseFunctionsException(code: 'internal', message: e.toString());
    }
  }

  /// Convert the raw callable payload into a list of `Task`s.
  static List<Task> _decodeTasks(dynamic raw) {
    if (raw is! Map) return const <Task>[];
    final list = raw['tasks'];

    if (list is! List) return const <Task>[];

    return list.map<Task>((dynamic item) {
      final m = (item is Map) ? item : const <String, dynamic>{};

      final title = (m['title'] ?? '').toString();

      final steps = (m['steps'] is List
              ? (m['steps'] as List).map((s) => s.toString().trim())
              : const Iterable<String>.empty())
          .where((s) => s.isNotEmpty)
          .toList();

      // Optional fields from the backend
      final String? startTime =
          (m['startTime'] == null) ? null : m['startTime'].toString();
      final String? endTime =
          (m['endTime'] == null) ? null : m['endTime'].toString();

      // Normalize period to "AM" or "PM" (default AM if missing/invalid)
      final String periodRaw = (m['period'] ?? 'AM').toString().toUpperCase();
      final String period = (periodRaw == 'PM') ? 'PM' : 'AM';

      return Task(
        title: title,
        steps: steps,
        startTime: startTime,
        endTime: endTime,
        period: period,
        completed: false,
        hidden: false,
      );
    }).toList();
  }
}