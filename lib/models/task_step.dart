import 'package:flutter/foundation.dart';
import '../widgets/media_picker.dart'; // PickedImage

@immutable
class TaskStep {
  final String text;
  final List<PickedImage> images;
  const TaskStep({required this.text, this.images = const []});

  TaskStep copyWith({String? text, List<PickedImage>? images}) =>
      TaskStep(text: text ?? this.text, images: images ?? this.images);
}
