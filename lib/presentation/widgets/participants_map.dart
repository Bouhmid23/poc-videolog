import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/map_tile_source.dart';

class ParticipantsMapEntry {
  final String identity;
  final String? label;
  final double? lat;
  final double? lng;
  final bool isLocal;

  const ParticipantsMapEntry({
    required this.identity,
    this.label,
    this.lat,
    this.lng,
    this.isLocal = false,
  });

  bool get hasPosition => lat != null && lng != null;
}

class _MapTile {
  final ui.Image image;
  final Offset offset;
  const _MapTile(this.image, this.offset);
}

class ParticipantsMapWidget extends StatefulWidget {
  final List<ParticipantsMapEntry> participants;
  final MapTileSource tileSource;

  const ParticipantsMapWidget({
    super.key,
    required this.participants,
    this.tileSource = MapTileSource.openStreetMap,
  });

  static const double size = 180;

  @override
  State<ParticipantsMapWidget> createState() => _ParticipantsMapWidgetState();
}

class _ParticipantsMapWidgetState extends State<ParticipantsMapWidget> {
  final Map<String, _MapTile> _tiles = {};
  String _signature = '';

  int _zoom = 15;
  double _left = 0;
  double _top = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant ParticipantsMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tileSource != widget.tileSource ||
        oldWidget.participants != widget.participants) {
      _refresh();
    }
  }

  @override
  void dispose() {
    for (final t in _tiles.values) {
      t.image.dispose();
    }
    _tiles.clear();
    super.dispose();
  }

  Future<void> _refresh() async {
    final pts = widget.participants.where((p) => p.hasPosition).toList();
    if (pts.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat!);
      maxLat = math.max(maxLat, p.lat!);
      minLng = math.min(minLng, p.lng!);
      maxLng = math.max(maxLng, p.lng!);
    }

    final size = ParticipantsMapWidget.size;
    final zoom = _fitZoom(minLat, maxLat, minLng, maxLng, size);

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final cx = _lngToWorldX(centerLng, zoom);
    final cy = _latToWorldY(centerLat, zoom);
    final left = cx - size / 2;
    final top = cy - size / 2;

    final txMin = (left / 256).floor();
    final txMax = ((left + size) / 256).floor();
    final tyMin = (top / 256).floor();
    final tyMax = ((top + size) / 256).floor();

    final sig =
        '${widget.tileSource.urlTemplate}|$zoom|$txMin:$txMax|$tyMin:$tyMax';
    if (sig == _signature) {
      if (mounted) setState(() {});
      return;
    }
    _signature = sig;
    _zoom = zoom;
    _left = left;
    _top = top;

    final base = widget.tileSource.urlTemplate;

    final wanted = <String>[];
    for (var tx = txMin; tx <= txMax; tx++) {
      for (var ty = tyMin; ty <= tyMax; ty++) {
        wanted.add('$zoom/$tx/$ty');
      }
    }

    final newTiles = <String, _MapTile>{};
    for (final key in wanted) {
      final cacheKey = '${widget.tileSource.urlTemplate}|$key';
      final existing = _tiles[cacheKey];
      if (existing != null) {
        newTiles[cacheKey] = existing;
        continue;
      }
      try {
        final url = base
            .replaceAll('{z}', '$zoom')
            .replaceAll('{x}', key.split('/')[1])
            .replaceAll('{y}', key.split('/')[2]);
        final res = await http.get(
          Uri.parse(url),
          headers: const {'User-Agent': 'livekitapp-hud/1.0'},
        );
        if (res.statusCode != 200) continue;
        final codec = await ui.instantiateImageCodec(res.bodyBytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        final img = frame.image;
        final tx = int.parse(key.split('/')[1]);
        final ty = int.parse(key.split('/')[2]);
        newTiles[cacheKey] = _MapTile(
          img,
          Offset(tx * 256 - left, ty * 256 - top),
        );
      } catch (_) {
        // fallback: painted tiles remain visible
      }
    }

    for (final entry in _tiles.entries) {
      if (!newTiles.containsKey(entry.key)) {
        entry.value.image.dispose();
      }
    }
    _tiles
      ..clear()
      ..addAll(newTiles);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = ParticipantsMapWidget.size;
    final hasPositions = widget.participants.any((p) => p.hasPosition);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1B2620),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      clipBehavior: Clip.antiAlias,
      child: !hasPositions
          ? const Center(
              child: Text(
                'Aucune position GPS',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            )
          : CustomPaint(
              painter: _ParticipantsMapPainter(
                participants: widget.participants,
                zoom: _zoom,
                left: _left,
                top: _top,
                tiles: _tiles,
                source: widget.tileSource,
              ),
              size: Size(size, size),
            ),
    );
  }
}

// ─── Projections Web Mercator ───────────────────────────────────────────────
double _lngToWorldX(double lng, int z) =>
    (lng + 180.0) / 360.0 * (256.0 * math.pow(2, z).toDouble());

double _latToWorldY(double lat, int z) {
  final rad = lat * math.pi / 180.0;
  final merc = math.log(math.tan(rad) + 1.0 / math.cos(rad));
  return (1.0 - merc / math.pi) / 2.0 * (256.0 * math.pow(2, z).toDouble());
}

int _fitZoom(
  double minLat,
  double maxLat,
  double minLng,
  double maxLng,
  double size,
) {
  for (var z = 18; z >= 3; z--) {
    final w = (_lngToWorldX(maxLng, z) - _lngToWorldX(minLng, z)).abs();
    final h = (_latToWorldY(maxLat, z) - _latToWorldY(minLat, z)).abs();
    if (w <= size * 0.85 && h <= size * 0.85) return z;
  }
  return 3;
}

class _ParticipantsMapPainter extends CustomPainter {
  final List<ParticipantsMapEntry> participants;
  final int zoom;
  final double left;
  final double top;
  final Map<String, _MapTile> tiles;
  final MapTileSource source;

  _ParticipantsMapPainter({
    required this.participants,
    required this.zoom,
    required this.left,
    required this.top,
    required this.tiles,
    required this.source,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawFallbackTiles(canvas, size);

    for (final tile in tiles.values) {
      canvas.drawImage(tile.image, tile.offset, Paint());
    }

    _drawNorth(canvas, size);

    for (final p in participants.where((e) => e.hasPosition)) {
      final px = _lngToWorldX(p.lng!, zoom) - left;
      final py = _latToWorldY(p.lat!, zoom) - top;
      _drawMarker(canvas, Offset(px, py), p, size);
    }
  }

  void _drawFallbackTiles(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1B2620));

    final rnd = math.Random(7);
    const blockColor = Color(0xFF223226);
    const roadColor = Color(0xFF111A16);
    const centerLine = Color(0xFF3D5142);

    final blockPaint = Paint()..color = blockColor;
    final roadPaint = Paint()..color = roadColor;
    final centerPaint = Paint()..color = centerLine;
    const roadH = 7.0;

    var x = rnd.nextInt(30) + 8.0;
    while (x < size.width) {
      canvas.drawRect(Rect.fromLTWH(x, 0, roadH, size.height), roadPaint);
      canvas.drawLine(
        Offset(x + roadH / 2, 0),
        Offset(x + roadH / 2, size.height),
        centerPaint,
      );
      x += 40 + rnd.nextInt(34);
    }

    var y = rnd.nextInt(30) + 8.0;
    while (y < size.height) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, roadH), roadPaint);
      canvas.drawLine(
        Offset(0, y + roadH / 2),
        Offset(size.width, y + roadH / 2),
        centerPaint,
      );
      y += 42 + rnd.nextInt(30);
    }
  }

  void _drawNorth(Canvas canvas, Size size) {
    final northPaint = Paint()..color = Colors.white70;
    final northArrow = Path()
      ..moveTo(size.width / 2, 4)
      ..lineTo(size.width / 2 - 4, 12)
      ..lineTo(size.width / 2 + 4, 12)
      ..close();
    canvas.drawPath(northArrow, northPaint..style = PaintingStyle.fill);

    final northText = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(color: Colors.white70, fontSize: 8),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    northText.paint(canvas, Offset(size.width / 2 - northText.width / 2, 12));
  }

  void _drawMarker(
    Canvas canvas,
    Offset center,
    ParticipantsMapEntry p,
    Size size,
  ) {
    final borderColor = p.isLocal ? Colors.blueAccent : source.markerBorderColor;

    final halo = Paint()
      ..color = borderColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 10, halo);

    final fill = Paint()
      ..color = p.isLocal
          ? Colors.blueAccent
          : source.markerBackgroundColor;
    canvas.drawCircle(center, 5, fill);

    final ring = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, 5, ring);

    if (p.isLocal) {
      canvas.drawCircle(
        center,
        1.8,
        Paint()..color = Colors.white,
      );
    }

    final name = p.label ?? p.identity;
    final finalLabel = name.length > 8 ? '${name.substring(0, 8)}…' : name;
    final painter = TextPainter(
      text: TextSpan(
        text: finalLabel,
        style: TextStyle(
          color: source.markerIconColor,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelLeft = (center.dx - painter.width / 2 - 3)
        .clamp(0.0, size.width - painter.width - 6);
    final bgRect = Rect.fromLTWH(
      labelLeft,
      center.dy + 11,
      painter.width + 6,
      painter.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    painter.paint(canvas, Offset(bgRect.left + 3, bgRect.top));
  }

  @override
  bool shouldRepaint(covariant _ParticipantsMapPainter oldDelegate) {
    return oldDelegate.participants != participants ||
        oldDelegate.zoom != zoom ||
        oldDelegate.left != left ||
        oldDelegate.top != top ||
        oldDelegate.tiles != tiles ||
        oldDelegate.source != source;
  }
}