import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/measured_point.dart';
import '../models/rtk_position.dart';
import '../services/measured_point_store.dart';
import '../services/photo_service.dart';
import '../utils/geo.dart';

/// Arkusz szczegółów zmierzonego punktu: edycja notatki/kodu i zdjęcie
/// (aparat / galeria). Wspólny dla listy uzbrojenia i listy punktów tyczenia.
/// Zapisuje zmiany do [store] i zgłasza zaktualizowany punkt przez [onUpdated].
Future<void> showPointDetailSheet(
  BuildContext context,
  MeasuredPoint point,
  MeasuredPointStore store, {
  required void Function(MeasuredPoint) onUpdated,
}) async {
  final controller = TextEditingController(text: point.note ?? '');
  var current = point;

  Future<void> pick(StateSetter setLocal, ImageSource source) async {
    final path = await PhotoService.capture(current.id, source: source);
    if (path == null) return;
    current = current.copyWith(photoPath: path);
    await store.update(current);
    onUpdated(current);
    setLocal(() {});
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(current.label ?? current.id,
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${current.latitude.toStringAsFixed(7)}, '
              '${current.longitude.toStringAsFixed(7)} · '
              'RMS ${formatDistance(current.rms)} · ${fixLabel(current.worstFix)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Notatka / kod',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            if (current.photoPath != null &&
                File(current.photoPath!).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(current.photoPath!),
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => pick(setLocal, ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Aparat'),
                ),
                TextButton.icon(
                  onPressed: () => pick(setLocal, ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galeria'),
                ),
                if (current.photoPath != null)
                  IconButton(
                    tooltip: 'Usuń zdjęcie',
                    onPressed: () async {
                      current = current.copyWith(removePhoto: true);
                      await store.update(current);
                      onUpdated(current);
                      setLocal(() {});
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () async {
                  current = current.copyWith(note: controller.text.trim());
                  await store.update(current);
                  onUpdated(current);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Zapisz'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
