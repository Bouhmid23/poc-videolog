import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../core/ble_telemetry_service.dart';
import '../../exts.dart';
import 'package:permission_handler/permission_handler.dart';

class ControlsWidget extends StatefulWidget {
  final Room room;
  final LocalParticipant participant;

  final BleTelemetryService bleService;
  final VoidCallback onBleConnected;
  final VoidCallback onBleDisconnected;

  const ControlsWidget(
    this.room,
    this.participant, {
    required this.bleService,
    required this.onBleConnected,
    required this.onBleDisconnected,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _ControlsWidgetState();
}

// ─── Reactive bottom sheet content ─────────────────────────────────────────
class _BleSheetContent extends StatefulWidget {
  final BleTelemetryService bleService;
  final Future<void> Function(String deviceId) onConnect;
  final Future<void> Function() onDisconnect;
  final Future<void> Function() onToggleDisplay;

  const _BleSheetContent({
    required this.bleService,
    required this.onConnect,
    required this.onDisconnect,
    required this.onToggleDisplay,
  });

  @override
  State<_BleSheetContent> createState() => _BleSheetContentState();
}

class _BleSheetContentState extends State<_BleSheetContent> {
  StreamSubscription<BleConnectionStatus>? _statusSub;
  StreamSubscription<List<DiscoveredDevice>>? _devicesSub;
  BleConnectionStatus _status = BleConnectionStatus.idle();
  List<DiscoveredDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    _status = widget.bleService.connectionStatus;
    _statusSub = widget.bleService.connectionStatusStream.listen((s) {
      if (!mounted) return;
      setState(() => _status = s);
    });
    _devicesSub = widget.bleService.devicesStream.listen((d) {
      if (!mounted) return;
      setState(() => _devices = d);
    });
  }

  @override
  void dispose() {
    unawaited(_statusSub?.cancel());
    unawaited(_devicesSub?.cancel());
    super.dispose();
  }

  String? get _connectedDeviceId => widget.bleService.connectedDeviceId;
  bool get _isDisplaySessionActive => widget.bleService.isDisplaySessionActive;

  bool get _isBusy => _status.isBusy || _status.phase == BleConnectionPhase.ready;

  IconData _phaseIcon(BleConnectionPhase phase) {
    switch (phase) {
      case BleConnectionPhase.ready:
        return Icons.check_circle;
      case BleConnectionPhase.failed:
        return Icons.error;
      case BleConnectionPhase.disconnected:
        return Icons.bluetooth_disabled;
      default:
        return Icons.bluetooth_searching;
    }
  }

  Color _phaseColor(BleConnectionPhase phase) {
    switch (phase) {
      case BleConnectionPhase.ready:
        return Colors.greenAccent;
      case BleConnectionPhase.failed:
        return Colors.redAccent;
      case BleConnectionPhase.disconnected:
        return Colors.white38;
      default:
        return Colors.amber;
    }
  }

  String _statusLabel(BleConnectionPhase phase) {
    switch (phase) {
      case BleConnectionPhase.idle:
        return 'Prêt';
      case BleConnectionPhase.connecting:
        return 'Connexion en cours...';
      case BleConnectionPhase.connected:
        return 'Connexion établie';
      case BleConnectionPhase.initializing:
        return 'Initialisation...';
      case BleConnectionPhase.ready:
        return 'Connecté ✓';
      case BleConnectionPhase.disconnecting:
        return 'Déconnexion...';
      case BleConnectionPhase.disconnected:
        return 'Déconnecté';
      case BleConnectionPhase.failed:
        return 'Échec de connexion';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final hasActiveStatus = status.phase != BleConnectionPhase.idle &&
        status.phase != BleConnectionPhase.disconnected;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Devices BLE',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Connecte un capteur BLE pour envoyer la télémétrie réelle.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (hasActiveStatus)
              _buildStatusCard(status),
            if (hasActiveStatus) const SizedBox(height: 12),
            Expanded(child: _buildDeviceList(status)),
            if (_connectedDeviceId != null) ...[
              const SizedBox(height: 8),
              _buildSessionSection(),
            ],
            const SizedBox(height: 8),
            _buildActionRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BleConnectionStatus status) {
    final phase = status.phase;
    final isProgress = phase == BleConnectionPhase.connecting ||
        phase == BleConnectionPhase.initializing ||
        phase == BleConnectionPhase.disconnecting;

    // Show session state sub-message when in ready phase
    final sessionMsg = phase == BleConnectionPhase.ready && status.message.isNotEmpty
        ? status.message
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _phaseColor(phase).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _phaseColor(phase).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: isProgress
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_phaseColor(phase)),
                    ),
                  )
                : Icon(_phaseIcon(phase), size: 18, color: _phaseColor(phase)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusLabel(phase),
                  style: TextStyle(
                    color: _phaseColor(phase),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (sessionMsg != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sessionMsg,
                    style: TextStyle(
                      color: _phaseColor(phase).withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (status.message.isNotEmpty &&
                    phase != BleConnectionPhase.ready &&
                    !isProgress) ...[
                  const SizedBox(height: 2),
                  Text(
                    status.message,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
                if (status.error != null && status.error!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    status.error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(BleConnectionStatus status) {
    final devices = _devices;
    if (devices.isEmpty) {
      return const Center(child: Text('Scan BLE en cours...'));
    }

    return ListView.builder(
      itemCount: devices.length,
      itemBuilder: (context, i) {
        final device = devices[i];
        final name =
            device.name.isEmpty ? 'Unnamed (${device.id})' : device.name;
        final isConnected = _connectedDeviceId == device.id;
        final isConnectingThis = status.deviceId == device.id &&
            (status.phase == BleConnectionPhase.connecting ||
                status.phase == BleConnectionPhase.connected ||
                status.phase == BleConnectionPhase.initializing);
        final isBusy = _isBusy || status.phase == BleConnectionPhase.disconnecting;

        return ListTile(
          title: Text(name),
          subtitle: Text('RSSI ${device.rssi}'),
          trailing: isConnected
              ? const Text(
                  'Connecté',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : isConnectingThis
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                      ),
                      onPressed: isBusy
                          ? null
                          : () => widget.onConnect(device.id),
                      child: Text(
                        'Connecter',
                        style: TextStyle(
                          fontSize: 11,
                          color: isBusy ? Colors.white24 : null,
                        ),
                      ),
                    ),
        );
      },
    );
  }

  Widget _buildSessionSection() {
    final isActive = _isDisplaySessionActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: Icon(isActive ? Icons.stop : Icons.play_arrow),
            onPressed: widget.onToggleDisplay,
            label: Text(
              isActive ? 'Arrêter la session' : 'Démarrer la session',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () async {
              await widget.onDisconnect();
            },
            child: const Text('Déconnecter'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ),
      ],
    );
  }
}

class _ControlsWidgetState extends State<ControlsWidget> {
  CameraPosition position = CameraPosition.front;

  List<MediaDevice>? _audioInputs;
  List<MediaDevice>? _audioOutputs;

  StreamSubscription? _subscription;

  bool _speakerphoneOn = Hardware.instance.speakerOn ?? false;

  // ── BLE scan state (local to controls sheet UI only) ──
  StreamSubscription<BleConnectionStatus>? _bleConnectionStatusSub;
  StreamSubscription<SportMetrics>? _bleMetricsSub;
  int? _bleBattery;
  // Convenience getter — service lives in RoomPage
  BleTelemetryService get _bleService => widget.bleService;

  @override
  void initState() {
    super.initState();
    participant.addListener(_onChange);
    _subscription = Hardware.instance.onDeviceChange.stream.listen((
      List<MediaDevice> devices,
    ) {
      _loadDevices(devices);
    });
    unawaited(Hardware.instance.enumerateDevices().then(_loadDevices));
    _bleConnectionStatusSub = _bleService.connectionStatusStream.listen((
      status,
    ) {
      if (!mounted) return;
      setState(() {});
      if (status.phase == BleConnectionPhase.ready) {
        widget.onBleConnected();
      } else if (status.phase == BleConnectionPhase.disconnected ||
          status.phase == BleConnectionPhase.failed) {
        widget.onBleDisconnected();
      }
    });
    _bleMetricsSub = _bleService.metricsStream.listen((metrics) {
      if (!mounted) return;
      setState(() => _bleBattery = metrics.battery);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_bleConnectionStatusSub?.cancel());
    unawaited(_bleMetricsSub?.cancel());
    // Do NOT dispose _bleService here — it is owned by RoomPage
    participant.removeListener(_onChange);
    super.dispose();
  }

  LocalParticipant get participant => widget.participant;

  void _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    setState(() {});
  }

  void _onChange() => setState(() {});

  bool get isMuted => participant.isMuted;

  void _disableAudio() async => participant.setMicrophoneEnabled(false);
  Future<void> _enableAudio() async => participant.setMicrophoneEnabled(true);
  void _disableVideo() async => participant.setCameraEnabled(false);
  void _enableVideo() async => participant.setCameraEnabled(true);

  void _selectAudioOutput(MediaDevice device) async {
    await widget.room.setAudioOutputDevice(device);
    setState(() {});
  }

  void _selectAudioInput(MediaDevice device) async {
    await widget.room.setAudioInputDevice(device);
    setState(() {});
  }

  void _setSpeakerphoneOn() async {
    _speakerphoneOn = !_speakerphoneOn;
    await widget.room.setSpeakerOn(_speakerphoneOn, forceSpeakerOutput: false);
    setState(() {});
  }

  void _toggleCamera() async {
    final track = participant.videoTrackPublications.firstOrNull?.track;
    if (track == null) return;
    try {
      final newPosition = position.switched();
      await track.setCameraPosition(newPosition);
      setState(() => position = newPosition);
    } catch (error) {
      debugPrint('could not restart track: $error');
    }
  }



  void _onTapDisconnect() async {
    final result = await context.showDisconnectDialog();
    if (result == true) await widget.room.disconnect();
  }

  Future<void> _toggleDisplaySession() async {
    final deviceId = _bleService.connectedDeviceId;
    if (deviceId == null) return;

    if (_bleService.isDisplaySessionActive) {
      await _bleService.stopDisplaySession();
    } else {
      await _bleService.startDisplaySession(deviceId);
    }

    if (mounted) setState(() {});
  }

  Future<void> _openBleSheet() async {
    if (!kIsWeb) {
      for (final perm in [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ]) {
        final status = await perm.request();
        if (status.isDenied) {
          debugPrint('Permission $perm refusée pour le scan BLE');
        }
      }
    }

    await _bleService.startScan();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return _BleSheetContent(
          bleService: _bleService,
          onConnect: (deviceId) async {
            await _bleService.connectAndListen(deviceId);
            widget.onBleConnected();
            if (mounted) setState(() {});
          },
          onDisconnect: () async {
            await _bleService.disconnect();
            widget.onBleDisconnected();
            if (mounted) setState(() {});
          },
          onToggleDisplay: _toggleDisplaySession,
        );
      },
    );
    await _bleService.stopScan();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 5,
        runSpacing: 5,
        children: [
          if (participant.isMicrophoneEnabled())
            if (lkPlatformIs(PlatformType.android))
              IconButton(
                onPressed: _disableAudio,
                icon: const Icon(Icons.mic),
                iconSize: 30,
                tooltip: 'mute audio',
              )
            else
              PopupMenuButton<MediaDevice>(
                icon: const Icon(Icons.settings_voice),
                offset: const Offset(0, -90),
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem<MediaDevice>(
                      value: null,
                      onTap: isMuted ? _enableAudio : _disableAudio,
                      child: const ListTile(
                        leading: Icon(Icons.mic_off, color: Colors.white),
                        title: Text('Mute Microphone'),
                      ),
                    ),
                    if (_audioInputs != null)
                      ..._audioInputs!.map((device) {
                        return PopupMenuItem<MediaDevice>(
                          value: device,
                          child: ListTile(
                            leading:
                                (device.deviceId ==
                                    widget.room.selectedAudioInputDeviceId)
                                ? const Icon(
                                    Icons.check_box_outlined,
                                    color: Colors.white,
                                  )
                                : const Icon(
                                    Icons.check_box_outline_blank,
                                    color: Colors.white,
                                  ),
                            title: Text(device.label),
                          ),
                          onTap: () => _selectAudioInput(device),
                        );
                      }),
                  ];
                },
              )
          else
            IconButton(
              onPressed: _enableAudio,
              icon: const Icon(Icons.mic_off),
              tooltip: 'un-mute audio',
              iconSize: 30,
            ),
          if (!lkPlatformIsMobile())
            PopupMenuButton<MediaDevice>(
              icon: const Icon(Icons.volume_up),
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem<MediaDevice>(
                    value: null,
                    child: ListTile(
                      leading: Icon(Icons.speaker, color: Colors.white),
                      title: Text('Select Audio Output'),
                    ),
                  ),
                  if (_audioOutputs != null)
                    ..._audioOutputs!.map((device) {
                      return PopupMenuItem<MediaDevice>(
                        value: device,
                        child: ListTile(
                          leading:
                              (device.deviceId ==
                                  widget.room.selectedAudioOutputDeviceId)
                              ? const Icon(
                                  Icons.check_box_outlined,
                                  color: Colors.white,
                                )
                              : const Icon(
                                  Icons.check_box_outline_blank,
                                  color: Colors.white,
                                ),
                          title: Text(device.label),
                        ),
                        onTap: () => _selectAudioOutput(device),
                      );
                    }),
                ];
              },
            ),
          if (!kIsWeb && lkPlatformIsMobile())
            IconButton(
              disabledColor: Colors.grey,
              onPressed: _setSpeakerphoneOn,
              icon: Icon(_speakerphoneOn ? Icons.speaker_phone : Icons.hearing),
              tooltip: 'Switch SpeakerPhone',
              iconSize: 30,
            ),
          if (participant.isCameraEnabled())
            IconButton(
              onPressed: _disableVideo,
              icon: const Icon(Icons.videocam),
              tooltip: 'disable_video',
              iconSize: 30,
            )
          else
            IconButton(
              onPressed: _enableVideo,
              icon: const Icon(Icons.videocam_off),
              tooltip: 'un-mute video',
              iconSize: 30,
            ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: _toggleCamera,
            tooltip: 'toggle camera',
            iconSize: 30,
          ),
          Stack(
            children: [
              IconButton(
                tooltip: _bleService.connectedDeviceId != null
                    ? 'BLE connecté'
                    : 'BLE déconnecté',
                onPressed: _openBleSheet,
                icon: Icon(
                  _bleService.connectedDeviceId != null
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_searching,
                  color: _bleService.connectedDeviceId != null
                      ? Colors.greenAccent
                      : null,
                ),
              ),
              if (_bleBattery != null)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$_bleBattery%',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: _onTapDisconnect,
            icon: const Icon(Icons.call_end_rounded, color: Colors.red),
            tooltip: 'disconnect',
            iconSize: 30,
          ),
        ],
      ),
    );
  }
}
