// // lib/firebase_background.dart
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'notifications.dart'; // your existing notifications helper to display local notifications

// /// Must be a top-level function
// Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   // Ensure Firebase is initialized
//   await Firebase.initializeApp();
//   // Optionally show a notification locally (if you want to convert data messages)
//   try {
//     final notif = message.notification;
//     final title = notif?.title ?? 'Background message';
//     final body = notif?.body ?? message.data['body'] ?? '';
//     // Show via your local notifications helper (keeps UX consistent)
//     await NotificationsHelper.showNotification(id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
//       title: title,
//       body: body,
//     );
//   } catch (e) {
//     // ignore errors in background handler
//   }
// }
