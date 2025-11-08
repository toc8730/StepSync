import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class PickedImage {
  final Uint8List bytes;
  final String name;
  const PickedImage({required this.bytes, required this.name});
}

class MediaPicker extends StatefulWidget {
  final void Function(List<PickedImage>) onChanged;
  final String label;
  final int maxImages;

  const MediaPicker({
    super.key,
    required this.onChanged,
    this.label = 'Attach Images',
    this.maxImages = 5,
  });

  @override
  State<MediaPicker> createState() => _MediaPickerState();
}

class _MediaPickerState extends State<MediaPicker> {
  List<PickedImage> _images = [];

  Future<void> _pickImages() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true, // needed on web
    );
    if (res == null) return;

    final picked = res.files
        .where((f) => f.bytes != null)
        .map((f) => PickedImage(bytes: f.bytes!, name: f.name))
        .toList();

    setState(() {
      final room = widget.maxImages - _images.length;
      _images = [..._images, ...picked.take(room)];
    });

    widget.onChanged(_images);
  }

  void _removeAt(int i) {
    setState(() => _images.removeAt(i));
    widget.onChanged(_images);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => _pickImages(),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Add'),
        ),
        const Spacer(),
        Text('${_images.length}/${widget.maxImages}', style: const TextStyle(color: Colors.grey))
      ]),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(_images.length, (i) {
          final it = _images[i];
          return Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(it.bytes, width: 90, height: 90, fit: BoxFit.cover),
            ),
            Positioned(
              top: 3, right: 3,
              child: GestureDetector(
                onTap: () => _removeAt(i),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ]);
        }),
      ),
    ]);
  }
}
