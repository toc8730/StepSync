// globals.dart
import 'package:flutter/foundation.dart';

class AppGlobals {
  static String token = "";
  static final ValueNotifier<int> scheduleVersion = ValueNotifier<int>(0);

  static void notifyScheduleRefresh() {
    scheduleVersion.value++;
  }
}
