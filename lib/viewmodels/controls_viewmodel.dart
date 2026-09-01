import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, VoidCallback, kIsWeb, debugPrint;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble_sensor_service.dart';
import '../core/ble_telemetry_service.dart';

class ControlsViewModel extends ChangeNotifier {
  // ── References (set via init) ──
  BleTelemetryService? _bleService;
  BleSensorService? _sensorService;
  LocalParticipant? _participant;
  Room? _room;

  // ── Subscriptions ──
  StreamSubscription<BleConnectionStatus>? _bleConnectionStatusSub;
  StreamSubscription<SportMetrics>? _bleMetricsSub;
  StreamSubscription<SensorStatus>? _sensorHrmStatusSub;
  StreamSubscription<SensorStatus>? _sensorCscStatusSub;
  StreamSubscription? _deviceChangeSub;

  // ── State exposed to UI ──
  CameraPosition _cameraPosition = CameraPosition.front;
  bool _speakerphoneOn = false;
  bool _sensorHrConnected = false;
  bool _sensorCadenceConnected = false;
  bool _bleGlassesConnected = false;
  int? _bleBattery;
  List<MediaDevice>? _audioInputs;
  List<MediaDevice>? _audioOutputs;

  // ── Getters ──
  CameraPosition get cameraPosition => _cameraPosition;
  bool get speakerphoneOn => _speakerphoneOn;
  bool get sensorHrConnected => _sensorHrConnected;
  bool get sensorCadenceConnected => _sensorCadenceConnected;
  bool get bleGlassesConnected => _bleGlassesConnected;
  int? get bleBattery => _bleBattery;
  List<MediaDevice>? get audioInputs => _audioInputs;
  List<MediaDevice>? get audioOutputs => _audioOutputs;
  bool get isMuted => _participant?.isMuted ?? true;
  bool get isCameraEnabled => _participant?.isCameraEnabled() ?? false;

  // ── Lifecycle ──
  void init({
    required LocalParticipant participant,
    required Room room,
    required BleTelemetryService bleService,
    required BleSensorService sensorService,
    VoidCallback? onBleConnected,
    VoidCallback? onBleDisconnected,
  }) {
    _participant = participant;
    _room = room;
    _bleService = bleService;
    _sensorService = sensorService;
    _speakerphoneOn = Hardware.instance.speakerOn ?? false;

    participant.addListener(_onParticipantChanged);

    _deviceChangeSub = Hardware.instance.onDeviceChange.stream.listen((devices) {
      _loadDevices(devices);
    });
    unawaited(Hardware.instance.enumerateDevices().then(_loadDevices));

    _bleConnectionStatusSub = _bleService!.connectionStatusStream.listen((status) {
      final wasConnected = _bleGlassesConnected;
      _bleGlassesConnected = status.phase == BleConnectionPhase.ready;
      notifyListeners();
      if (_bleGlassesConnected && !wasConnected) {
        onBleConnected?.call();
      } else if (!_bleGlassesConnected && wasConnected) {
        onBleDisconnected?.call();
      }
    });

    _bleMetricsSub = _bleService!.metricsStream.listen((metrics) {
      _bleBattery = metrics.battery;
      notifyListeners();
    });

    _sensorHrmStatusSub = _sensorService!.hrmStatusStream.listen((s) {
      _sensorHrConnected = s.isConnected;
      notifyListeners();
    });

    _sensorCscStatusSub = _sensorService!.cscStatusStream.listen((s) {
      _sensorCadenceConnected = s.isConnected;
      notifyListeners();
    });
  }

  void _onParticipantChanged() => notifyListeners();

  void _loadDevices(List<MediaDevice> devices) {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    notifyListeners();
  }

  // ── Audio/Video actions ──
  void toggleMicrophone() {
    final p = _participant;
    if (p == null) return;
    if (p.isMuted) {
      p.setMicrophoneEnabled(true);
    } else {
      p.setMicrophoneEnabled(false);
    }
  }

  void toggleCamera() {
    final p = _participant;
    if (p == null) return;
    if (p.isCameraEnabled()) {
      p.setCameraEnabled(false);
    } else {
      p.setCameraEnabled(true);
    }
  }

  void enableAudio() => _participant?.setMicrophoneEnabled(true);
  void disableAudio() => _participant?.setMicrophoneEnabled(false);
  void enableVideo() => _participant?.setCameraEnabled(true);
  void disableVideo() => _participant?.setCameraEnabled(false);

  Future<void> switchCamera() async {
    final track = _participant?.videoTrackPublications.firstOrNull?.track;
    if (track == null) return;
    try {
      final newPosition = _cameraPosition.switched();
      await track.setCameraPosition(newPosition);
      _cameraPosition = newPosition;
      notifyListeners();
    } catch (error) {
      debugPrint('Could not restart track: $error');
    }
  }

  Future<void> toggleSpeakerphone() async {
    final room = _room;
    if (room == null) return;
    _speakerphoneOn = !_speakerphoneOn;
    await room.setSpeakerOn(_speakerphoneOn, forceSpeakerOutput: false);
    notifyListeners();
  }

  Future<void> selectAudioInput(MediaDevice device) async {
    final room = _room;
    if (room == null) return;
    await room.setAudioInputDevice(device);
    notifyListeners();
  }

  Future<void> selectAudioOutput(MediaDevice device) async {
    final room = _room;
    if (room == null) return;
    await room.setAudioOutputDevice(device);
    notifyListeners();
  }

  // ── BLE actions ──
  Future<void> toggleDisplaySession() async {
    final service = _bleService;
    if (service == null) return;
    final deviceId = service.connectedDeviceId;
    if (deviceId == null) return;

    if (service.isDisplaySessionActive) {
      await service.stopDisplaySession();
    } else {
      await service.startDisplaySession(deviceId);
    }
    notifyListeners();
  }

  Future<void> openBleSheet() async {
    final service = _bleService;
    if (service == null) return;

    if (!kIsWeb) {
      for (final perm in [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ]) {
        await perm.request();
      }
    }

    await service.startScan();
  }

  Future<void> closeBleSheet() async {
    await _bleService?.stopScan();
  }

  Future<void> connectBleDevice(String deviceId) async {
    await _bleService?.connectAndListen(deviceId);
  }

  Future<void> disconnectBleDevice() async {
    await _bleService?.disconnect();
  }

  Future<void> openSensorSheet() async {
    final service = _sensorService;
    if (service == null) return;

    if (!kIsWeb) {
      for (final perm in [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ]) {
        await perm.request();
      }
    }

    await service.startScan();
  }

  Future<void> closeSensorSheet() async {
    await _sensorService?.stopScan();
  }

  // ── Cleanup ──
  @override
  void dispose() {
    _participant?.removeListener(_onParticipantChanged);
    unawaited(_deviceChangeSub?.cancel());
    unawaited(_bleConnectionStatusSub?.cancel());
    unawaited(_bleMetricsSub?.cancel());
    unawaited(_sensorHrmStatusSub?.cancel());
    unawaited(_sensorCscStatusSub?.cancel());
    super.dispose();
  }
}
