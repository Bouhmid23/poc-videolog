import 'dart:async';
import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleTelemetryService {
  BleTelemetryService({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _telemetrySub;

  final _devicesCtrl = StreamController<List<DiscoveredDevice>>.broadcast();
  final _telemetryCtrl = StreamController<Map<String, dynamic>>.broadcast();

  final List<DiscoveredDevice> _devices = [];

  Stream<List<DiscoveredDevice>> get devicesStream => _devicesCtrl.stream;
  Stream<Map<String, dynamic>> get telemetryStream => _telemetryCtrl.stream;

  String? connectedDeviceId;

  // UUID de démo (à adapter à votre device BLE réel)
  static final Uuid telemetryServiceUuid =
  Uuid.parse('0000181A-0000-1000-8000-00805F9B34FB');
  static final Uuid telemetryCharacteristicUuid =
  Uuid.parse('00002A58-0000-1000-8000-00805F9B34FB');

  Future<void> startScan() async {
    await _scanSub?.cancel();
    _devices.clear();
    _devicesCtrl.add(const []);

    _scanSub = _ble
        .scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency)
        .listen((device) {
      final index = _devices.indexWhere((d) => d.id == device.id);
      if (index >= 0) {
        _devices[index] = device;
      } else {
        _devices.add(device);
      }
      _devicesCtrl.add(List.unmodifiable(_devices));
    });
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<void> connectAndListen(String deviceId) async {
    await disconnect();

    _connectionSub = _ble
        .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 12))
        .listen((update) {
      if (update.connectionState == DeviceConnectionState.connected) {
        connectedDeviceId = deviceId;
      }
      if (update.connectionState == DeviceConnectionState.disconnected) {
        connectedDeviceId = null;
      }
    });

    final characteristic = QualifiedCharacteristic(
      serviceId: telemetryServiceUuid,
      characteristicId: telemetryCharacteristicUuid,
      deviceId: deviceId,
    );

    _telemetrySub = _ble.subscribeToCharacteristic(characteristic).listen((bytes) {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isEmpty) return;
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        _telemetryCtrl.add(decoded);
      }
    });
  }

  Future<void> disconnect() async {
    await _telemetrySub?.cancel();
    _telemetrySub = null;

    await _connectionSub?.cancel();
    _connectionSub = null;

    connectedDeviceId = null;
  }

  Future<void> dispose() async {
    await stopScan();
    await disconnect();
    await _devicesCtrl.close();
    await _telemetryCtrl.close();
  }
}
