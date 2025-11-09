import 'dart:typed_data';

import '../data/images_repo.dart';
import '../models/task.dart';
import '../models/task_step.dart';
import '../widgets/media_picker.dart';

List<TaskStep> resolveTaskSteps(Task task, {List<TaskStep>? provided}) {
  if (provided != null && provided.isNotEmpty) {
    return provided;
  }
  final steps = <TaskStep>[];
  final storedImages = ImagesRepo.I.get(task, task.steps.length);
  for (int i = 0; i < task.steps.length; i++) {
    final text = task.steps[i];
    final List<PickedImage> images = [];
    if (i < storedImages.length) {
      final Uint8List? bytes = storedImages[i];
      if (bytes != null) {
        images.add(PickedImage(bytes: bytes, name: 'step-${i + 1}.png'));
      }
    }
    steps.add(TaskStep(text: text, images: images));
  }
  return steps;
}
