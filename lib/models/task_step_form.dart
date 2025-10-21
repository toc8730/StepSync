import 'package:flutter/material.dart';
import '../widgets/media_picker.dart';
import '../models/task_step.dart';

class TaskStepForm extends StatefulWidget {
  const TaskStepForm({super.key});

  @override
  State<TaskStepForm> createState() => _TaskStepFormState();
}

class _TaskStepFormState extends State<TaskStepForm> {
  final _text = TextEditingController();
  List<PickedImage> _images = [];

  void _save() {
    final t = _text.text.trim();
    if (t.isEmpty && _images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a description or at least one image')),
      );
      return;
    }
    Navigator.pop(context, TaskStep(text: t, images: _images));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Step')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _text,
            decoration: const InputDecoration(labelText: 'Step description'),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          MediaPicker(
            maxImages: 6,
            onChanged: (imgs) => _images = imgs,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save Step'),
          ),
        ]),
      ),
    );
  }
}
