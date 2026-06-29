import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../rtk/ntrip_client.dart';
import '../utils/geo.dart';

/// Pokazuje wybór mountpointu z sourcetable castera (z filtrem tekstowym).
/// Gdy podano [from] (bieżąca pozycja), liczy odległość do każdej stacji
/// i sortuje od najbliższej — kluczowe dla RTK (baza powinna być < ~30 km).
/// Zwraca nazwę wybranego mountpointu albo null, gdy anulowano.
Future<String?> showMountpointPicker(
  BuildContext context,
  List<SourcetableEntry> entries, {
  LatLng? from,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _MountpointPicker(entries: entries, from: from),
  );
}

class _MountpointPicker extends StatefulWidget {
  const _MountpointPicker({required this.entries, this.from});

  final List<SourcetableEntry> entries;
  final LatLng? from;

  @override
  State<_MountpointPicker> createState() => _MountpointPickerState();
}

class _MountpointPickerState extends State<_MountpointPicker> {
  String _query = '';

  /// Wpisy po filtrze tekstowym; gdy znamy [widget.from] — z odległością i
  /// posortowane rosnąco (stacje bez współrzędnych na końcu).
  List<({SourcetableEntry e, double? dist})> get _items {
    final from = widget.from;
    final q = _query.trim().toLowerCase();
    var list = widget.entries
        .where((e) =>
            q.isEmpty ||
            e.mountpoint.toLowerCase().contains(q) ||
            e.identifier.toLowerCase().contains(q) ||
            e.country.toLowerCase().contains(q) ||
            e.format.toLowerCase().contains(q))
        .map((e) {
      double? d;
      if (from != null && e.lat != null && e.lon != null) {
        d = distanceMeters(from, LatLng(e.lat!, e.lon!));
      }
      return (e: e, dist: d);
    }).toList();
    if (from != null) {
      list.sort((a, b) {
        if (a.dist == null && b.dist == null) return 0;
        if (a.dist == null) return 1;
        if (b.dist == null) return -1;
        return a.dist!.compareTo(b.dist!);
      });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mountpointy castera (${widget.entries.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (widget.from != null)
                    Text(
                      'Posortowane wg odległości od Twojej pozycji '
                      '(do RTK Fixed celuj < 30 km).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Filtruj: nazwa, lokalizacja, kraj, format',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Brak pasujących mountpointów.'),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.only(bottom: bottomSafe + 8),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final e = items[i].e;
                        final dist = items[i].dist;
                        final sub = [
                          if (e.identifier.isNotEmpty) e.identifier,
                          if (e.format.isNotEmpty) e.format,
                          if (e.navSystem.isNotEmpty) e.navSystem,
                          if (e.country.isNotEmpty) e.country,
                        ].join(' · ');
                        // Bliska baza (≤30 km) wyróżniona kolorem — kandydat na RTK.
                        final near = dist != null && dist <= 30000;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            dist == null ? Icons.dns_outlined : Icons.place,
                            color: near
                                ? Colors.green
                                : (dist != null ? Colors.orange : null),
                          ),
                          title: Text(e.mountpoint),
                          subtitle: sub.isEmpty ? null : Text(sub),
                          trailing: dist == null
                              ? null
                              : Text(
                                  formatDistance(dist),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: near ? Colors.green : Colors.orange,
                                  ),
                                ),
                          onTap: () => Navigator.of(context).pop(e.mountpoint),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
