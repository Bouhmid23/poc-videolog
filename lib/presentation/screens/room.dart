import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../utils.dart';
import '../models/map_tile_source.dart';
import '../widgets/controls.dart';
import '../widgets/participant.dart';
import '../widgets/participants_map.dart';
import '../widgets/tile_source_toggle.dart';
import '../../viewmodels/room_viewmodel.dart';

class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final bool fastConnection;

  const RoomPage(
    this.room,
    this.listener, {
    this.fastConnection = false,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  late final RoomViewModel _vm;
  bool _showMap = true;
  MapTileSource _tileSource = MapTileSource.openStreetMap;

  static const double _mapSize = ParticipantsMapWidget.size;
  static const double _galleryHeight = 140;

  List<ParticipantsMapEntry> _mapEntries() {
    final entries = <ParticipantsMapEntry>[];

    final local = _vm.room?.localParticipant;
    if (local != null) {
      final localShape = local.name.isNotEmpty ? local.name : local.identity;
      entries.add(ParticipantsMapEntry(
        identity: local.identity,
        label: 'Moi ($localShape)',
        lat: _vm.localTelemetry.lat,
        lng: _vm.localTelemetry.lng,
        isLocal: true,
      ));
    }

    final room = _vm.room;
    if (room != null) {
      for (final p in room.remoteParticipants.values) {
        final telemetry = _vm.telemetryForParticipant(p);
        entries.add(ParticipantsMapEntry(
          identity: p.identity,
          label: p.name.isNotEmpty ? p.name : p.identity,
          lat: telemetry?.lat,
          lng: telemetry?.lng,
        ));
      }
    }

    return entries;
  }

  // Insets de la galerie pour ne chevaucher ni la cart (haut-droit) ni le PIP posture (bas-droit).
  double _galleryRightInset() {
    final poseInset = _vm.showPosePip ? 16.0 + 135.0 : 16.0;
    final mapInset = _showMap ? 16.0 + _mapSize + 12.0 : 16.0;
    return math.max(poseInset, mapInset);
  }

  @override
  void initState() {
    super.initState();
    _vm = RoomViewModel();
    _vm.addListener(_onStateChanged);

    WidgetsBindingCompatible.instance?.addPostFrameCallback((_) async {
      await _vm.init(widget.room, widget.listener, onDisconnected: () {
        if (mounted) {
          context.pop(); // Returns to previous screen (Rooms or Home)
        }
      });
      if (mounted) setState(() {});
    });

    if (lkPlatformIs(PlatformType.android)) {
      unawaited(Hardware.instance.setSpeakerphoneOn(true));
    }

    if (lkPlatformIsDesktop()) {
      onWindowShouldClose = () async {
        unawaited(widget.room.disconnect());
        await widget.listener.waitFor<RoomDisconnectedEvent>(
          duration: const Duration(seconds: 5),
        );
      };
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onStateChanged);
    _vm.dispose();
    onWindowShouldClose = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryTrack = _vm.primaryTrack;
    final secondaryTracks = _vm.secondaryTracks;

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: primaryTrack != null
                    ? ParticipantWidget.widgetFor(
                        primaryTrack,
                        showStatsLayer: true,
                      )
                    : Container(),
              ),
              if (_vm.room?.localParticipant != null)
                SafeArea(
                  top: false,
                  child: ControlsWidget(
                    _vm.room!,
                    _vm.room!.localParticipant!,
                    bleService: _vm.bleService,
                    sensorService: _vm.sensorService,
                    controlsViewModel: _vm.controlsViewModel,
                    onBleConnected: _vm.onBleConnected,
                    onBleDisconnected: _vm.onBleDisconnected,
                    showMap: _showMap,
                    onToggleMap: () => setState(() => _showMap = !_showMap),
                    showPosePip: _vm.showPosePip,
                    onTogglePosePip: _vm.togglePosePip,
                  ),
                ),
            ],
          ),

          // ── Galerie des peers : fond transparent, superpos�e au flux vid�o principal ──
          if (secondaryTracks.isNotEmpty)
            Positioned(
              left: 12,
              right: _galleryRightInset(),
              bottom: 160,
              child: SizedBox(
                height: _galleryHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: secondaryTracks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (BuildContext context, int index) => SizedBox(
                    width: 140,
                    height: _galleryHeight,
                    child: ParticipantWidget.widgetFor(
                      secondaryTracks[index],
                    ),
                  ),
                ),
              ),
            ),

          // ── Mini-map (coin sup�rieur droit) + toggle tuiles ──
          if (_showMap)
            Positioned(
              top: 30,
              right: 16,
              child: SizedBox(
                width: _mapSize,
                height: _mapSize,
                child: Stack(
                  children: [
                    ParticipantsMapWidget(
                      participants: _mapEntries(),
                      tileSource: _tileSource,
                    ),
                    TileSourceToggle(
                      current: _tileSource,
                      onToggle: () => setState(
                        () => _tileSource = _tileSource.next,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}