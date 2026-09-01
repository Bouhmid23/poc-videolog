import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// ─── Standard BLE Sport Sensor UUIDs (Bluetooth SIG) ─────────────────────────

// Heart Rate Service (0x180D)
final Uuid _hrmServiceUuid = Uuid.parse('0000180D-0000-1000-8000-00805F9B34FB');
final Uuid _hrmCharUuid = Uuid.parse('00002A37-0000-1000-8000-00805F9B34FB');

// Cycling Speed & Cadence Service (0x1816)
final Uuid _cscServiceUuid = Uuid.parse('00001816-0000-1000-8000-00805F9B34FB');
final Uuid _cscCharUuid = Uuid.parse('00002A5B-0000-1000-8000-00805F9B34FB');

// Battery Service (standard, used for battery level of sensors)
final Uuid _batteryServiceUuid = Uuid.parse('0000180F-0000-1000-8000-00805F9B34FB');
final Uuid _batteryCharUuid = Uuid.parse('00002A19-0000-1000-8000-00805F9B34FB');

// ─── Sensor Type ──────────────────────────────────────────────────────────────

enum SensorType { hrm, cadence, unknown }

SensorType _sensorTypeFromDevice(DiscoveredDevice device) {
  final serviceUuids = device.serviceUuids.map((u) => u.toString().toLowerCase()).toList();
  final name = device.name.toLowerCase();

  final hasHrm = serviceUuids.any((u) => u.contains('180d')) ||
      name.contains('hrm') ||
      name.contains('heart');

  final hasCsc = serviceUuids.any((u) => u.contains('1816')) ||
      name.contains('cadence') ||
      name.contains('csc') ||
      name.contains('tilt'); // Common in some cadence sensors

  if (hasHrm && hasCsc) return SensorType.hrm; // combined sensor, prioritize HRM
  if (hasHrm) return SensorType.hrm;
  if (hasCsc) return SensorType.cadence;
  return SensorType.unknown;
}

// ─── Sensor Connection Status ─────────────────────────────────────────────────

enum SensorConnectionState { disconnected, connecting, connected, failed }

class SensorStatus {
  final SensorType type;
  final SensorConnectionState state;
  final String? deviceId;
  final String? deviceName;
  final String? error;
  final int? battery;

  const SensorStatus({
    required this.type,
    required this.state,
    this.deviceId,
    this.deviceName,
    this.error,
    this.battery,
  });

  bool get isConnected => state == SensorConnectionState.connected;
  bool get isBusy => state == SensorConnectionState.connecting;
}

// ─── CSC State (for cadence calculation) ─────────────────────────────────────

class _CscState {
  int? lastCrankRev;
  int? lastCrankTime; // in 1/1024 seconds
}

// ─── BleSensorService ─────────────────────────────────────────────────────────

class BleSensorService {
  BleSensorService({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  // ── Scan ──
  StreamSubscription<DiscoveredDevice>? _scanSub;
  final _devicesCtrl = StreamController<List<DiscoveredDevice>>.broadcast();
  final List<DiscoveredDevice> _devices = [];

  // ── HRM ──
  StreamSubscription<ConnectionStateUpdate>? _hrmConnectionSub;
  StreamSubscription<List<int>>? _hrmCharSub;
  StreamSubscription<List<int>>? _hrmBatterySub;
  final _hrmStatusCtrl = StreamController<SensorStatus>.broadcast();
  final _heartRateCtrl = StreamController<int>.broadcast();
  SensorStatus _hrmStatus = const SensorStatus(type: SensorType.hrm, state: SensorConnectionState.disconnected);
  int? _lastHeartRate;
  String? _hrmDeviceId;

  // ── Cadence ──
  StreamSubscription<ConnectionStateUpdate>? _cscConnectionSub;
  StreamSubscription<List<int>>? _cscCharSub;
  StreamSubscription<List<int>>? _cscBatterySub;
  final _cscStatusCtrl = StreamController<SensorStatus>.broadcast();
  final _cadenceCtrl = StreamController<int>.broadcast();
  SensorStatus _cscStatus = const SensorStatus(type: SensorType.cadence, state: SensorConnectionState.disconnected);
  int? _lastCadence;
  String? _cscDeviceId;
  final _cscState = _CscState();

  // ── Public streams ──
  List<DiscoveredDevice> get discoveredDevices => List.unmodifiable(_devices);
  Stream<List<DiscoveredDevice>> get devicesStream => _devicesCtrl.stream;
  Stream<int> get heartRateStream => _heartRateCtrl.stream;
  Stream<int> get cadenceStream => _cadenceCtrl.stream;
  Stream<SensorStatus> get hrmStatusStream => _hrmStatusCtrl.stream;
  Stream<SensorStatus> get cscStatusStream => _cscStatusCtrl.stream;

  // ── Public getters ──
  bool get isHrmConnected => _hrmStatus.isConnected;
  bool get isCadenceConnected => _cscStatus.isConnected;
  int? get lastHeartRate => _lastHeartRate;
  int? get lastCadence => _lastCadence;
  SensorStatus get hrmStatus => _hrmStatus;
  SensorStatus get cscStatus => _cscStatus;
  String? get hrmDeviceId => _hrmDeviceId;
  String? get cscDeviceId => _cscDeviceId;

  // ─── Scan ───────────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    await _scanSub?.cancel();
    // Re-emit currently discovered devices immediately
    _devicesCtrl.add(List.unmodifiable(_devices));

    // Scan without service filter: some devices (e.g. Decathlon) do not
    // advertise service UUIDs in scan responses, so withServices would
    // silently drop them.  Classification happens client-side in
    // _sensorTypeFromDevice() / classifyDevice().
    _scanSub = _ble
        .scanForDevices(
          withServices: [],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
      (d) {
        final i = _devices.indexWhere((e) => e.id == d.id);
        if (i >= 0) {
          _devices[i] = d;
        } else {
          _devices.add(d);
        }
        _devicesCtrl.add(List.unmodifiable(_devices));
      },
      onError: (e) {
        debugPrint('BLE Sensor scan error: $e');
        _devicesCtrl.addError(e);
      },
    );
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
  }

  // ─── Connect HRM ───────────────────────────────────────────────────────────

  Future<void> connectHrm(String deviceId) async {
    if (_hrmDeviceId == deviceId && _hrmStatus.isConnected) return;
    await disconnectHrm();

    _hrmDeviceId = deviceId;
    _hrmStatus = SensorStatus(
      type: SensorType.hrm,
      state: SensorConnectionState.connecting,
      deviceId: deviceId,
    );
    _hrmStatusCtrl.add(_hrmStatus);

    _hrmConnectionSub = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
      (update) async {
        if (update.connectionState == DeviceConnectionState.connected) {
          _hrmStatus = SensorStatus(
            type: SensorType.hrm,
            state: SensorConnectionState.connected,
            deviceId: deviceId,
          );
          _hrmStatusCtrl.add(_hrmStatus);

          // Subscribe to Heart Rate Measurement characteristic
          await _subscribeHrmCharacteristic(deviceId);
          // Subscribe to Battery Level if available
          await _subscribeBatteryLevel(deviceId, isHrm: true);
        }

        if (update.connectionState == DeviceConnectionState.disconnected) {
          _hrmDeviceId = null;
          _lastHeartRate = null;
          _hrmStatus = const SensorStatus(
            type: SensorType.hrm,
            state: SensorConnectionState.disconnected,
          );
          _hrmStatusCtrl.add(_hrmStatus);
          await _cancelHrmSubs();
        }
      },
      onError: (e) {
        debugPrint('HRM connection error: $e');
        _hrmDeviceId = null;
        _hrmStatus = SensorStatus(
          type: SensorType.hrm,
          state: SensorConnectionState.failed,
          error: e.toString(),
        );
        _hrmStatusCtrl.add(_hrmStatus);
      },
    );
  }

  Future<void> _subscribeHrmCharacteristic(String deviceId) async {
    await _hrmCharSub?.cancel();
    final char = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: _hrmServiceUuid,
      characteristicId: _hrmCharUuid,
    );
    _hrmCharSub = _ble.subscribeToCharacteristic(char).listen(
      (bytes) {
        final hr = _parseHrmMeasurement(bytes);
        if (hr != null) {
          _lastHeartRate = hr;
          _heartRateCtrl.add(hr);
        }
      },
      onError: (e) => debugPrint('HRM char error: $e'),
    );
  }

  /// Parse Heart Rate Measurement (0x2A37) per Bluetooth SIG spec.
  /// Byte 0: Flags
  ///   bit 0: 0 = UINT8 HR, 1 = UINT16 HR
  ///   bit 1: Energy Expended present
  ///   bit 2: RR-Interval present
  /// Byte 1+: HR value (1 or 2 bytes depending on flag)
  int? _parseHrmMeasurement(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final flags = bytes[0];
    final isUint16 = (flags & 0x01) == 1;
    final offset = isUint16 ? 2 : 1;

    if (bytes.length < offset) return null;

    if (isUint16) {
      return bytes[1] | (bytes[2] << 8);
    } else {
      return bytes[1];
    }
  }

  // ─── Connect Cadence ───────────────────────────────────────────────────────

  Future<void> connectCadence(String deviceId) async {
    if (_cscDeviceId == deviceId && _cscStatus.isConnected) return;
    await disconnectCadence();

    _cscDeviceId = deviceId;
    _cscStatus = SensorStatus(
      type: SensorType.cadence,
      state: SensorConnectionState.connecting,
      deviceId: deviceId,
    );
    _cscStatusCtrl.add(_cscStatus);

    _cscConnectionSub = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
      (update) async {
        if (update.connectionState == DeviceConnectionState.connected) {
          _cscStatus = SensorStatus(
            type: SensorType.cadence,
            state: SensorConnectionState.connected,
            deviceId: deviceId,
          );
          _cscStatusCtrl.add(_cscStatus);

          // Subscribe to CSC Measurement characteristic
          await _subscribeCscCharacteristic(deviceId);
          // Subscribe to Battery Level if available
          await _subscribeBatteryLevel(deviceId, isHrm: false);
        }

        if (update.connectionState == DeviceConnectionState.disconnected) {
          _cscDeviceId = null;
          _lastCadence = null;
          _cscState.lastCrankRev = null;
          _cscState.lastCrankTime = null;
          _cscStatus = const SensorStatus(
            type: SensorType.cadence,
            state: SensorConnectionState.disconnected,
          );
          _cscStatusCtrl.add(_cscStatus);
          await _cancelCscSubs();
        }
      },
      onError: (e) {
        debugPrint('CSC connection error: $e');
        _cscDeviceId = null;
        _cscStatus = SensorStatus(
          type: SensorType.cadence,
          state: SensorConnectionState.failed,
          error: e.toString(),
        );
        _cscStatusCtrl.add(_cscStatus);
      },
    );
  }

  Future<void> _subscribeCscCharacteristic(String deviceId) async {
    await _cscCharSub?.cancel();
    final char = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: _cscServiceUuid,
      characteristicId: _cscCharUuid,
    );
    _cscCharSub = _ble.subscribeToCharacteristic(char).listen(
      (bytes) {
        final cadence = _parseCscMeasurement(bytes);
        if (cadence != null) {
          _lastCadence = cadence;
          _cadenceCtrl.add(cadence);
        }
      },
      onError: (e) => debugPrint('CSC char error: $e'),
    );
  }

  /// Parse CSC Measurement (0x2A5B) per Bluetooth SIG spec.
  /// Byte 0: Flags
  ///   bit 0: Wheel Revolution Data present
  ///   bit 1: Crank Revolution Data present
  /// If Crank Revolution present (bit 1):
  ///   Cumulative Crank Revolutions: UINT16 (2 bytes)
  ///   Last Crank Event Time: UINT16 (2 bytes, unit = 1/1024 s)
  /// Cadence RPM = (crankRevDelta / crankTimeDelta) * 60
  int? _parseCscMeasurement(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final flags = bytes[0];
    final hasCrank = (flags & 0x02) != 0;

    if (!hasCrank) return null;
    if (bytes.length < 5) return null; // flags(1) + wheelRev(4) + crankRev(2) + crankTime(2) minimum

    // Find crank data offset based on wheel data presence
    final hasWheel = (flags & 0x01) != 0;
    int offset = 1; // start after flags byte
    if (hasWheel) {
      offset += 6; // wheel: cumulative(4) + lastEventTime(2)
    }

    if (bytes.length < offset + 4) return null; // need crankRev(2) + crankTime(2)

    final crankRev = bytes[offset] | (bytes[offset + 1] << 8);
    final crankTime = bytes[offset + 2] | (bytes[offset + 3] << 8);

    // Calculate cadence from deltas
    final cadence = _calculateCadence(crankRev, crankTime);
    return cadence;
  }

  int? _calculateCadence(int currentRev, int currentTime) {
    final prevRev = _cscState.lastCrankRev;
    final prevTime = _cscState.lastCrankTime;

    // Update state for next calculation
    _cscState.lastCrankRev = currentRev;
    _cscState.lastCrankTime = currentTime;

    if (prevRev == null || prevTime == null) return null;

    // Handle 16-bit overflow
    int revDelta = currentRev - prevRev;
    if (revDelta < 0) revDelta += 65536;

    int timeDelta = currentTime - prevTime;
    if (timeDelta < 0) timeDelta += 65536;

    // timeDelta is in 1/1024 seconds
    if (timeDelta == 0) return null;

    final timeSeconds = timeDelta / 1024.0;
    final rpm = (revDelta / timeSeconds) * 60.0;

    // Clamp to realistic cadence range (0-200 RPM)
    return rpm.round().clamp(0, 200);
  }

  // ─── Battery Level ─────────────────────────────────────────────────────────

  Future<void> _subscribeBatteryLevel(String deviceId, {required bool isHrm}) async {
    final existingSub = isHrm ? _hrmBatterySub : _cscBatterySub;
    await existingSub?.cancel();

    try {
      final char = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: _batteryServiceUuid,
        characteristicId: _batteryCharUuid,
      );
      final sub = _ble.subscribeToCharacteristic(char).listen(
        (bytes) {
          if (bytes.isEmpty) return;
          final battery = bytes[0].clamp(0, 100);
          if (isHrm) {
            _hrmStatus = SensorStatus(
              type: SensorType.hrm,
              state: SensorConnectionState.connected,
              deviceId: _hrmDeviceId,
              battery: battery,
            );
            _hrmStatusCtrl.add(_hrmStatus);
          } else {
            _cscStatus = SensorStatus(
              type: SensorType.cadence,
              state: SensorConnectionState.connected,
              deviceId: _cscDeviceId,
              battery: battery,
            );
            _cscStatusCtrl.add(_cscStatus);
          }
        },
        onError: (e) => debugPrint('Battery char error: $e'),
      );
      if (isHrm) {
        _hrmBatterySub = sub;
      } else {
        _cscBatterySub = sub;
      }
    } catch (_) {
      // Battery characteristic not available on this device — ignore
    }
  }

  // ─── Disconnect ────────────────────────────────────────────────────────────

  Future<void> disconnectHrm() async {
    await _cancelHrmSubs();
    await _hrmConnectionSub?.cancel();
    _hrmConnectionSub = null;
    _hrmDeviceId = null;
    _lastHeartRate = null;
    _hrmStatus = const SensorStatus(
      type: SensorType.hrm,
      state: SensorConnectionState.disconnected,
    );
    _hrmStatusCtrl.add(_hrmStatus);
  }

  Future<void> disconnectCadence() async {
    await _cancelCscSubs();
    await _cscConnectionSub?.cancel();
    _cscConnectionSub = null;
    _cscDeviceId = null;
    _lastCadence = null;
    _cscState.lastCrankRev = null;
    _cscState.lastCrankTime = null;
    _cscStatus = const SensorStatus(
      type: SensorType.cadence,
      state: SensorConnectionState.disconnected,
    );
    _cscStatusCtrl.add(_cscStatus);
  }

  Future<void> _cancelHrmSubs() async {
    for (final s in [_hrmCharSub, _hrmBatterySub]) {
      await s?.cancel();
    }
    _hrmCharSub = null;
    _hrmBatterySub = null;
  }

  Future<void> _cancelCscSubs() async {
    for (final s in [_cscCharSub, _cscBatterySub]) {
      await s?.cancel();
    }
    _cscCharSub = null;
    _cscBatterySub = null;
  }

  // ─── Classify discovered device ────────────────────────────────────────────

  SensorType classifyDevice(DiscoveredDevice device) => _sensorTypeFromDevice(device);

  // ─── Cleanup ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await stopScan();
    await disconnectHrm();
    await disconnectCadence();
    for (final c in [
      _devicesCtrl,
      _heartRateCtrl,
      _cadenceCtrl,
      _hrmStatusCtrl,
      _cscStatusCtrl,
    ]) {
      await c.close();
    }
  }
}
