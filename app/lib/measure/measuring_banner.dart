import 'package:flutter/material.dart';

import '../utils/geo.dart';

/// Baner postępu uśredniania pomiaru — wspólny dla tyczenia i zbierania
/// punktów uzbrojenia. Pokazuje licznik próbek, bieżący RMS i przyciski.
class MeasuringBanner extends StatelessWidget {
  const MeasuringBanner({
    super.key,
    required this.count,
    required this.targetSamples,
    required this.rms,
    required this.onSave,
    required this.onCancel,
    this.title = 'Uśrednianie…',
  });

  final int count;
  final int targetSamples;
  final double rms;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String title;

  @override
  Widget build(BuildContext context) {
    final canSave = count >= 3;
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$title  $count/$targetSamples · RMS ${formatDistance(rms)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onCancel, child: const Text('Anuluj')),
                FilledButton(
                  onPressed: canSave ? onSave : null,
                  child: const Text('Zapisz'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
