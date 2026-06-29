import 'package:flutter/material.dart';

import '../models/measured_point.dart';
import '../services/export_service.dart';
import '../utils/geo.dart';

/// Wysokości i spadki między zmierzonymi punktami. Działa na punktach, które
/// mają wysokość (z GGA). Wybierasz reper („Od") i cel („Do") — apka liczy
/// różnicę wysokości, spadek %/‰, stosunek 1:n i kąt. Lista pokazuje wszystkie
/// punkty z wysokością i Δh względem repera. Uwaga: do *różnic* wysokości na
/// małym terenie model geoidy nie jest potrzebny.
class HeightsScreen extends StatefulWidget {
  const HeightsScreen({super.key, required this.points});

  final List<MeasuredPoint> points;

  @override
  State<HeightsScreen> createState() => _HeightsScreenState();
}

class _HeightsScreenState extends State<HeightsScreen> {
  late final List<MeasuredPoint> _pts =
      widget.points.where((p) => p.altitude != null).toList();
  String? _fromId;
  String? _toId;

  @override
  void initState() {
    super.initState();
    if (_pts.isNotEmpty) _fromId = _pts.first.id;
    if (_pts.length > 1) _toId = _pts[1].id;
  }

  MeasuredPoint? _byId(String? id) {
    for (final p in _pts) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _name(MeasuredPoint p) => p.label ?? p.id;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  String _csvCell(String v) {
    final s = v.replaceAll('"', '""');
    return s.contains(RegExp(r'[;\n"]')) ? '"$s"' : s;
  }

  Future<void> _export() async {
    final from = _byId(_fromId);
    final b = StringBuffer()
      ..writeln('label;wys_m;dh_od_repera_m;spadek_proc;dystans_m');
    for (final p in _pts) {
      final s = (from != null && from.id != p.id)
          ? slopeBetween(from.latLng, from.altitude!, p.latLng, p.altitude!)
          : null;
      final isRef = from != null && from.id == p.id;
      b.writeln([
        _csvCell(_name(p)),
        p.altitude!.toStringAsFixed(3),
        isRef ? '0.000' : (s?.deltaH.toStringAsFixed(3) ?? ''),
        s?.percent.toStringAsFixed(2) ?? '',
        s?.horizontal.toStringAsFixed(2) ?? '',
      ].join(';'));
    }
    try {
      await ExportService.shareTextFile(b.toString(), 'wysokosci.csv',
          subject: 'Wysokości i spadki');
    } catch (e) {
      _snack('Eksport nieudany: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = _byId(_fromId);
    final to = _byId(_toId);
    final pair = (from != null && to != null && from.id != to.id)
        ? slopeBetween(from.latLng, from.altitude!, to.latLng, to.altitude!)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wysokości i spadki'),
        actions: [
          IconButton(
            tooltip: 'Eksport (CSV)',
            onPressed: _pts.isEmpty ? null : _export,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: _pts.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Brak punktów z wysokością.\n\nZmierz punkty w terenie — '
                  'wysokość pobierana jest automatycznie z odbiornika (GGA). '
                  'Do różnic wysokości na działce nie jest potrzebny model '
                  'geoidy; do rzędnej n.p.m. — tak.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.only(
                  bottom: 16 + MediaQuery.viewPaddingOf(context).bottom),
              children: [
                _selector('Od (reper)', _fromId,
                    (v) => setState(() => _fromId = v)),
                _selector('Do', _toId, (v) => setState(() => _toId = v)),
                if (pair != null) _slopeCard(pair),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    from == null
                        ? 'Punkty z wysokością'
                        : 'Wysokość i Δh względem repera „${_name(from)}"',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                for (final p in _pts) _pointTile(p, from),
              ],
            ),
    );
  }

  Widget _selector(
      String label, String? value, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            items: [
              for (final p in _pts)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    '${_name(p)}  ·  ${p.altitude!.toStringAsFixed(3)} m',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _slopeCard(
      ({
        double horizontal,
        double deltaH,
        double percent,
        double permille,
        double angleDeg
      }) s) {
    final up = s.deltaH >= 0;
    final color = up ? Colors.teal : Colors.deepOrange;
    final ratio = slopeRatio(s.horizontal, s.deltaH);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(up ? Icons.trending_up : Icons.trending_down,
                    color: color),
                const SizedBox(width: 8),
                Text(
                  'Spadek ${formatSlope(s.percent)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
                if (ratio.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text('($ratio)',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 4,
              children: [
                _metric('Δ wysokości',
                    '${up ? '+' : '−'}${s.deltaH.abs().toStringAsFixed(3)} m'),
                _metric('Odległość pozioma', formatDistance(s.horizontal)),
                _metric('Spadek', '${s.permille.toStringAsFixed(1)} ‰'),
                _metric('Kąt', '${s.angleDeg.toStringAsFixed(2)}°'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      );

  Widget _pointTile(MeasuredPoint p, MeasuredPoint? from) {
    final isRef = from != null && from.id == p.id;
    final s = (from != null && !isRef)
        ? slopeBetween(from.latLng, from.altitude!, p.latLng, p.altitude!)
        : null;
    final up = s != null && s.deltaH >= 0;
    return ListTile(
      dense: true,
      leading: Icon(
        isRef
            ? Icons.adjust
            : (s == null
                ? Icons.height
                : (up ? Icons.north_east : Icons.south_east)),
        color: isRef
            ? Theme.of(context).colorScheme.primary
            : (s == null
                ? null
                : (up ? Colors.teal : Colors.deepOrange)),
      ),
      title: Text(_name(p)),
      subtitle: Text(
        isRef
            ? 'reper · ${p.altitude!.toStringAsFixed(3)} m'
            : (s == null
                ? '${p.altitude!.toStringAsFixed(3)} m'
                : '${p.altitude!.toStringAsFixed(3)} m   ·   '
                    'Δh ${up ? '+' : '−'}${s.deltaH.abs().toStringAsFixed(3)} m'
                    '   ·   ${formatSlope(s.percent)}'),
      ),
      trailing: isRef
          ? null
          : TextButton(
              onPressed: () => setState(() => _toId = p.id),
              child: const Text('Do'),
            ),
      onTap: () => setState(() => _fromId = p.id),
    );
  }
}
