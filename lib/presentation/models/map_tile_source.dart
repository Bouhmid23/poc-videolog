import 'package:flutter/material.dart';

enum MapTileSource {
  openStreetMap(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    nextIcon: Icons.satellite_alt_outlined,
    nextTooltip: 'Vue satellite',
    markerIconColor: Color(0xFF2F3542),
    markerBorderColor: Color(0xFF2F3542),
    markerBackgroundColor: Colors.black12,
  ),
  googleSatellite(
    urlTemplate:
        'https://www.google.cn/maps/vt?lyrs=s@189&gl=cn&x={x}&y={y}&z={z}',
    nextIcon: Icons.map_outlined,
    nextTooltip: 'Vue plan',
    markerIconColor: Colors.white,
    markerBorderColor: Color(0xFFF5A623),
    markerBackgroundColor: Colors.black45,
  );

  const MapTileSource({
    required this.urlTemplate,
    required this.nextIcon,
    required this.nextTooltip,
    required this.markerIconColor,
    required this.markerBorderColor,
    required this.markerBackgroundColor,
  });

  final String urlTemplate;

  final IconData nextIcon;
  final String nextTooltip;

  final Color markerIconColor;
  final Color markerBorderColor;
  final Color markerBackgroundColor;

  MapTileSource get next => values[(index + 1) % values.length];
}