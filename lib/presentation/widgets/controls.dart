import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../core/ble_sensor_service.dart';
import '../../core/ble_telemetry_service.dart';
import '../../exts.dart';
import '../../viewmodels/controls_viewmodel.dart';

class ControlsWidget extends StatefulWidget {
  final Room room;
  final LocalParticipant participant;

  final BleTelemetryService bleService;
  final BleSensorService sensorService;
  final ControlsViewModel controlsViewModel;
  final VoidCallback onBleConnected;
  final VoidCallback onBleDisconnected;
  final bool showMap;
  final VoidCallback onToggleMap;
  final bool showPosePip;
  final VoidCallback onTogglePosePip;

  const ControlsWidget(
    this.room,
    this.participant, {
    required this.bleService,
    required this.sensorService,
    required this.controlsViewModel,
    required this.onBleConnected,
    required this.onBleDisconnected,
    required this.showMap,
    required this.onToggleMap,
    required this.showPosePip,
    required this.onTogglePosePip,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _ControlsWidgetState();
}

class _ControlsWidgetState extends State<ControlsWidget> {
  ControlsViewModel get _vm => widget.controlsViewModel;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openBleSheet() async {
    await _vm.openBleSheet();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _BleSheetContent(
        bleService: widget.bleService,
        onConnect: (deviceId) async {
          await _vm.connectBleDevice(deviceId);
          widget.onBleConnected();
          if (mounted) setState(() {});
        },
        onDisconnect: () async {
          await _vm.disconnectBleDevice();
          widget.onBleDisconnected();
          if (mounted) setState(() {});
        },
        onToggleDisplay: _vm.toggleDisplaySession,
      ),
    );
    await _vm.closeBleSheet();
  }

  Future<void> _openSensorSheet() async {
    await _vm.openSensorSheet();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, _) => _SensorSheetContent(sensorService: widget.sensorService),
      ),
    );
    await _vm.closeSensorSheet();
  }

  void _onTapDisconnect() async {
    final result = await context.showDisconnectDialog();
    if (result == true) await widget.room.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 3,
        runSpacing: 3,
        children: [
          // ── Microphone ──
          if (widget.participant.isMicrophoneEnabled())
            if (lkPlatformIs(PlatformType.android))
              IconButton(
                onPressed: _vm.disableAudio,
                icon: const Icon(Icons.mic),
                iconSize: 24,
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
                      onTap: _vm.toggleMicrophone,
                      child: const ListTile(
                        leading: Icon(Icons.mic_off, color: Colors.white),
                        title: Text('Mute Microphone'),
                      ),
                    ),
                    if (_vm.audioInputs != null)
                      ..._vm.audioInputs!.map((device) {
                        return PopupMenuItem<MediaDevice>(
                          value: device,
                          child: ListTile(
                            leading: device.deviceId ==
                                    widget.room.selectedAudioInputDeviceId
                                ? const Icon(Icons.check_box_outlined, color: Colors.white)
                                : const Icon(Icons.check_box_outline_blank, color: Colors.white),
                            title: Text(device.label),
                          ),
                          onTap: () => _vm.selectAudioInput(device),
                        );
                      }),
                  ];
                },
              )
          else
            IconButton(
              onPressed: _vm.enableAudio,
              icon: const Icon(Icons.mic_off),
              tooltip: 'un-mute audio',
              iconSize: 24,
            ),

          // ── Audio output (desktop) ──
          if (!lkPlatformIsMobile())
            PopupMenuButton<MediaDevice>(
              icon: const Icon(Icons.volume_up),
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem<MediaDevice>(
                    value: null,
                    child: ListTile(
                      leading: Icon(Icons.speaker, color: Colors.white,size: 24,),
                      title: Text('Select Audio Output'),
                    ),
                  ),
                  if (_vm.audioOutputs != null)
                    ..._vm.audioOutputs!.map((device) {
                      return PopupMenuItem<MediaDevice>(
                        value: device,
                        child: ListTile(
                          leading: device.deviceId ==
                                  widget.room.selectedAudioOutputDeviceId
                              ? const Icon(Icons.check_box_outlined, color: Colors.white)
                              : const Icon(Icons.check_box_outline_blank, color: Colors.white),
                          title: Text(device.label),
                        ),
                        onTap: () => _vm.selectAudioOutput(device),
                      );
                    }),
                ];
              },
            ),

          // ── Speakerphone ──
          if (!kIsWeb && lkPlatformIsMobile())
            IconButton(
              disabledColor: Colors.grey,
              onPressed: _vm.toggleSpeakerphone,
              icon: Icon(_vm.speakerphoneOn ? Icons.speaker_phone : Icons.hearing),
              tooltip: 'Switch SpeakerPhone',
              iconSize: 24,
            ),

          // ── Camera ──
          if (widget.participant.isCameraEnabled())
            IconButton(
              onPressed: _vm.disableVideo,
              icon: const Icon(Icons.videocam),
              tooltip: 'disable_video',
              iconSize: 24,
            )
          else
            IconButton(
              onPressed: _vm.enableVideo,
              icon: const Icon(Icons.videocam_off),
              tooltip: 'un-mute video',
              iconSize: 24,
            ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: _vm.switchCamera,
            tooltip: 'toggle camera',
            iconSize: 24,
          ),

          // ── BLE glasses ──
          Stack(
            children: [
              IconButton(
                tooltip: _vm.bleGlassesConnected ? 'BLE connect\u00e9' : 'BLE d\u00e9connect\u00e9',
                onPressed: _openBleSheet,
                icon: Icon(
                  _vm.bleGlassesConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_searching,
                  color: _vm.bleGlassesConnected ? Colors.greenAccent : null,
                  size: 24,
                ),
              ),
              if (_vm.bleBattery != null)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_vm.bleBattery}%',
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

          // ── Sensors (HRM + Cadence) ──
          Stack(
            children: [
              IconButton(
                tooltip: _vm.sensorHrConnected || _vm.sensorCadenceConnected
                    ? 'Capteurs connect\u00e9s'
                    : 'Capteurs sport',
                onPressed: _openSensorSheet,
                icon: Icon(
                  _vm.sensorHrConnected || _vm.sensorCadenceConnected
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: _vm.sensorHrConnected
                      ? Colors.redAccent
                      : _vm.sensorCadenceConnected
                          ? Colors.cyanAccent
                          : null,
                  size: 24,
                ),
              ),
              if (_vm.sensorHrConnected || _vm.sensorCadenceConnected)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),

          // ── Mini-map ──
          IconButton(
            onPressed: widget.onToggleMap,
            icon: Icon(widget.showMap ? Icons.map : Icons.map_outlined),
            tooltip: widget.showMap ? 'Masquer la carte' : 'Afficher la carte',
            iconSize: 24,
          ),

          // ── D�tecteur de posture ──
          IconButton(
            onPressed: widget.onTogglePosePip,
            icon: Icon(
              widget.showPosePip ? Icons.visibility : Icons.visibility_off_outlined,
            ),
            tooltip: widget.showPosePip
                ? 'Masquer le d\u00e9tecteur de posture'
                : 'Afficher le d\u00e9tecteur de posture',
            iconSize: 24,
          ),

          // ── Disconnect ──
          IconButton(
            onPressed: _onTapDisconnect,
            icon: const Icon(Icons.call_end_rounded, color: Colors.red),
            tooltip: 'disconnect',
            iconSize: 24,
          ),
        ],
      ),
    );
  }
}

// ─── BLE Glasses Bottom Sheet (unchanged) ───────────────────────────────────
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
        return 'Pr\u00eat';
      case BleConnectionPhase.connecting:
        return 'Connexion en cours...';
      case BleConnectionPhase.connected:
        return 'Connexion \u00e9tablie';
      case BleConnectionPhase.initializing:
        return 'Initialisation...';
      case BleConnectionPhase.ready:
        return 'Connect\u00e9 \u2713';
      case BleConnectionPhase.disconnecting:
        return 'D\u00e9connexion...';
      case BleConnectionPhase.disconnected:
        return 'D\u00e9connect\u00e9';
      case BleConnectionPhase.failed:
        return '\u00c9chec de connexion';
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
            const Text('Devices BLE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Connecte un capteur BLE pour envoyer la t\u00e9l\u00e9m\u00e9trie r\u00e9elle.',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            if (hasActiveStatus) _buildStatusCard(status),
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
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_phaseColor(phase)),
                    ),
                  )
                : Icon(_phaseIcon(phase), size: 18, color: _phaseColor(phase)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_statusLabel(phase),
                    style: TextStyle(color: _phaseColor(phase), fontWeight: FontWeight.w600, fontSize: 13)),
                if (sessionMsg != null) ...[
                  const SizedBox(height: 2),
                  Text(sessionMsg, style: TextStyle(color: _phaseColor(phase).withValues(alpha: 0.8), fontSize: 12)),
                ],
                if (status.message.isNotEmpty && phase != BleConnectionPhase.ready && !isProgress) ...[
                  const SizedBox(height: 2),
                  Text(status.message, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ],
                if (status.error != null && status.error!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(status.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(BleConnectionStatus status) {
    if (_devices.isEmpty) return const Center(child: Text('Scan BLE en cours...'));

    return ListView.builder(
      itemCount: _devices.length,
      itemBuilder: (context, i) {
        final device = _devices[i];
        final name = device.name.isEmpty ? 'Unnamed (${device.id})' : device.name;
        final isConnected = _connectedDeviceId == device.id;
        final isConnectingThis = status.deviceId == device.id &&
            (status.phase == BleConnectionPhase.connecting ||
                status.phase == BleConnectionPhase.connected ||
                status.phase == BleConnectionPhase.initializing);

        return ListTile(
          title: Text(name),
          subtitle: Text('RSSI ${device.rssi}'),
          trailing: isConnected
              ? const Text('Connect\u00e9', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.w600))
              : isConnectingThis
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      ),
                      onPressed: _isBusy ? null : () => widget.onConnect(device.id),
                      child: Text('Connecter', style: TextStyle(fontSize: 11, color: _isBusy ? Colors.white24 : null)),
                    ),
        );
      },
    );
  }

  Widget _buildSessionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: Icon(_isDisplaySessionActive ? Icons.stop : Icons.play_arrow),
            onPressed: widget.onToggleDisplay,
            label: Text(_isDisplaySessionActive ? 'Arr\u00eater la session' : 'D\u00e9marrer la session'),
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(child: OutlinedButton(onPressed: () => widget.onDisconnect(), child: const Text('D\u00e9connecter'))),
        const SizedBox(width: 12),
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))),
      ],
    );
  }
}

// ─── Sensor Bottom Sheet (unchanged) ────────────────────────────────────────
class _SensorSheetContent extends StatefulWidget {
  final BleSensorService sensorService;
  const _SensorSheetContent({required this.sensorService});
  @override
  State<_SensorSheetContent> createState() => _SensorSheetContentState();
}

class _SensorSheetContentState extends State<_SensorSheetContent> {
  StreamSubscription<List<DiscoveredDevice>>? _devicesSub;
  StreamSubscription<SensorStatus>? _hrmStatusSub;
  StreamSubscription<SensorStatus>? _cscStatusSub;
  List<DiscoveredDevice> _devices = [];
  SensorStatus _hrmStatus = const SensorStatus(type: SensorType.hrm, state: SensorConnectionState.disconnected);
  SensorStatus _cscStatus = const SensorStatus(type: SensorType.cadence, state: SensorConnectionState.disconnected);

  @override
  void initState() {
    super.initState();
    _hrmStatus = widget.sensorService.hrmStatus;
    _cscStatus = widget.sensorService.cscStatus;
    _devices = widget.sensorService.discoveredDevices;
    _devicesSub = widget.sensorService.devicesStream.listen((d) {
      if (!mounted) return;
      setState(() => _devices = d);
    });
    _hrmStatusSub = widget.sensorService.hrmStatusStream.listen((s) {
      if (!mounted) return;
      setState(() => _hrmStatus = s);
    });
    _cscStatusSub = widget.sensorService.cscStatusStream.listen((s) {
      if (!mounted) return;
      setState(() => _cscStatus = s);
    });
  }

  @override
  void dispose() {
    unawaited(_devicesSub?.cancel());
    unawaited(_hrmStatusSub?.cancel());
    unawaited(_cscStatusSub?.cancel());
    super.dispose();
  }

  List<DiscoveredDevice> _devicesForType(SensorType type) =>
      _devices.where((d) => widget.sensorService.classifyDevice(d) == type).toList();

  List<DiscoveredDevice> _unknownDevices() =>
      _devices.where((d) => widget.sensorService.classifyDevice(d) == SensorType.unknown).toList();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Capteurs Sport', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Connecte un capteur cardiaque et/ou cadence.',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHrmSection(),
                    const SizedBox(height: 16),
                    _buildCscSection(),
                    if (_unknownDevices().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildUnknownSection(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHrmSection() {
    final devices = _devicesForType(SensorType.hrm);
    return _SensorCard(
      title: 'Fr\u00e9quence Cardiaque',
      icon: Icons.favorite,
      iconColor: Colors.redAccent,
      status: _hrmStatus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hrmStatus.isConnected)
            _buildConnectedBanner(deviceId: _hrmStatus.deviceId, battery: _hrmStatus.battery,
                onDisconnect: () => widget.sensorService.disconnectHrm())
          else if (_hrmStatus.isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Connexion...', style: TextStyle(fontSize: 12)),
              ]),
            )
          else if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucun capteur HRM trouv\u00e9', style: TextStyle(color: Colors.white54, fontSize: 12)),
            )
          else
            ...devices.map((d) => _buildDeviceTile(
                device: d, sensorType: SensorType.hrm,
                onConnect: () => widget.sensorService.connectHrm(d.id))),
        ],
      ),
    );
  }

  Widget _buildCscSection() {
    final devices = _devicesForType(SensorType.cadence);
    return _SensorCard(
      title: 'Cadence',
      icon: Icons.speed,
      iconColor: Colors.cyanAccent,
      status: _cscStatus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_cscStatus.isConnected)
            _buildConnectedBanner(deviceId: _cscStatus.deviceId, battery: _cscStatus.battery,
                onDisconnect: () => widget.sensorService.disconnectCadence())
          else if (_cscStatus.isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Connexion...', style: TextStyle(fontSize: 12)),
              ]),
            )
          else if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucun capteur cadence trouv\u00e9', style: TextStyle(color: Colors.white54, fontSize: 12)),
            )
          else
            ...devices.map((d) => _buildDeviceTile(
                device: d, sensorType: SensorType.cadence,
                onConnect: () => widget.sensorService.connectCadence(d.id))),
        ],
      ),
    );
  }

  Widget _buildUnknownSection() {
    return _SensorCard(
      title: 'Autres appareils',
      icon: Icons.devices_other,
      iconColor: Colors.white38,
      status: const SensorStatus(type: SensorType.unknown, state: SensorConnectionState.disconnected),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _unknownDevices()
            .map((d) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.name.isEmpty ? 'Inconnu (${d.id})' : d.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text('RSSI ${d.rssi}', style: const TextStyle(fontSize: 11)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () => widget.sensorService.connectHrm(d.id),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
                        child: const Text('Cardio', style: TextStyle(fontSize: 10)),
                      ),
                      const SizedBox(width: 4),
                      OutlinedButton(
                        onPressed: () => widget.sensorService.connectCadence(d.id),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
                        child: const Text('Cadence', style: TextStyle(fontSize: 10)),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildConnectedBanner({String? deviceId, int? battery, required VoidCallback onDisconnect}) {
    final displayId = deviceId != null && deviceId.length > 8
        ? deviceId.substring(0, 8) : deviceId ?? '\u2014';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected, size: 16, color: Colors.greenAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (battery != null)
                  Text('Batterie: $battery%', style: const TextStyle(fontSize: 10, color: Colors.white54)),
              ],
            ),
          ),
          TextButton(
            onPressed: onDisconnect,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), visualDensity: VisualDensity.compact),
            child: const Text('D\u00e9connecter', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile({required DiscoveredDevice device, required SensorType sensorType, required VoidCallback onConnect}) {
    final name = device.name.isEmpty
        ? 'Inconnu (${device.id.substring(0, math.min(8, device.id.length))})' : device.name;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(sensorType == SensorType.hrm ? Icons.favorite : Icons.speed, size: 18, color: Colors.white54),
      title: Text(name, style: const TextStyle(fontSize: 13)),
      subtitle: Text('RSSI ${device.rssi}', style: const TextStyle(fontSize: 11, color: Colors.white38)),
      trailing: OutlinedButton(
        onPressed: onConnect,
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
        child: const Text('Connecter', style: TextStyle(fontSize: 11)),
      ),
    );
  }
}

// ─── Sensor Card widget ─────────────────────────────────────────────────────
class _SensorCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final SensorStatus status;
  final Widget child;

  const _SensorCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.status,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = status.isConnected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.greenAccent.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isConnected
            ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: isConnected ? Colors.greenAccent : iconColor),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: isConnected ? Colors.greenAccent : Colors.white)),
              const Spacer(),
              if (isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('CONNECT\u00c9',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
