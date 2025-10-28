// lib/data/images_repo.dart
import 'dart:typed_data';
import '../models/task.dart';

class ImagesRepo {
  ImagesRepo._();
  static final ImagesRepo I = ImagesRepo._();

  final Map<String, List<Uint8List?>> _byKey = {};

  String _key(Task t) =>
      '${t.title}|${t.startTime ?? ""}|${t.endTime ?? ""}|${t.period ?? ""}';

  List<Uint8List?> get(Task t, int stepsLen) {
    final k = _key(t);
    final list = _byKey[k];
    if (list == null || list.length != stepsLen) {
      final fresh = List<Uint8List?>.filled(stepsLen, null, growable: false);
      _byKey[k] = fresh;
      return fresh;
    }
    return list;
  }

  void set(Task t, List<Uint8List?> images) {
    _byKey[_key(t)] = List<Uint8List?>.from(images);
  }

  void setAt(Task t, int index, Uint8List? bytes, int stepsLen) {
    final list = get(t, stepsLen);
    if (index < 0 || index >= list.length) return;
    list[index] = bytes;
  }
}