import 'package:flutter/material.dart';

import '../models/map_tile_source.dart';

class TileSourceToggle extends StatelessWidget {
  final MapTileSource current;
  final VoidCallback onToggle;

  const TileSourceToggle({
    super.key,
    required this.current,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 88,
      right: 20,
      child: Material(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(50),
          side: BorderSide(
            color: Theme.of(context).colorScheme.secondary,
            width: 1,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onToggle,
          child: Tooltip(
            message: current.nextTooltip,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                current.nextIcon,
                size: 22,
                color: Theme.of(context).colorScheme.inversePrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}