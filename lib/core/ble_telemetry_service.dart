import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// ─── UUIDs ────────────────────────────────────────────────────────────────────
const String _kServiceUuid = "0783B03E-8535-B5A0-7140-A304D2495CB7";
const String _kTxUuid      = "0783B03E-8535-B5A0-7140-A304D2495CB8";
const String _kRxUuid      = "0783B03E-8535-B5A0-7140-A304D2495CBA";
const String _kControlUuid = "0783B03E-8535-B5A0-7140-A304D2495CB9";
const String _kGestureUuid = "0783B03E-8535-B5A0-7140-A304D2495CBB";
const String _kTouchUuid   = "0783B03E-8535-B5A0-7140-A304D2495CBC";
const String _kBatteryUuid = "00002A19-0000-1000-8000-00805F9B34FB";

const int _kTargetMtu    = 512;
const int _kMaxChunkSize = 128;

// ─── Commandes ActiveLook §4 ──────────────────────────────────────────────────
const int _cmdDisplayPower = 0x00;
const int _cmdClear        = 0x01;
const int _cmdBattery      = 0x05;
const int _cmdLuminance    = 0x10;
const int _cmdAlsOnly      = 0x22;
const int _cmdLine         = 0x32;
const int _cmdTxtDisplay   = 0x37;
const int _cmdHoldFlush    = 0x39;

const int _actionHold       = 0x00;
const int _actionFlush      = 0x01;
const int _actionResetFlush = 0xFF;

// ─── Résolution ───────────────────────────────────────────────────────────────
// Origine (0,0) = haut-gauche. X → droite. Y → bas (standard écran).
const int _kDisplayW = 304;
const int _kDisplayH = 256;

// ─── §5.7 Text — paramètre r (rotation) ──────────────────────────────────────
// Doc §5.7 : "u8 r" = angle de rotation du texte en degrés (0 / 90 / 180 / 270).
// Pour les lunettes Engo, le système optique crée un effet miroir horizontal.
// r = 0x04 compense ce miroir (valeur validée expérimentalement sur hardware).
// r = 0x00 → texte à l'envers dans les lunettes.
const int _kTextRotation = 0x04; // miroir horizontal Engo

// ─── §5.7 Text — couleur ─────────────────────────────────────────────────────
// Doc §5.1 Color : niveaux de gris 0–15. 0 = noir (invisible), 15 = blanc max.
const int _kColorWhite = 0x0F; // blanc maximum
const int _kColorGray  = 0x09; // gris moyen pour les labels

// ─── §4.8 Font — fonts prédéfinies ───────────────────────────────────────────
// Seules les fonts 1, 2, 3 sont définies par défaut dans le firmware.
// Font 4 n'existe PAS par défaut → plante silencieusement.
const int _kFontSmall = 1; // ~16 px — labels (DIST, BPM, KCAL)
const int _kFontValue = 3; // ~32 px — valeurs numériques
const int _kFontBig   = 2; // ~24 px — countdown

// Largeur approx par caractère (Big Endian, mesurée empiriquement sur Engo)
const Map<int, int> _kFontCharW = {1: 10, 2: 14, 3: 20};

// Hauteur approx par font (pour calcul des gaps verticaux)
const Map<int, int> _kFontCharH = {1: 16, 2: 24, 3: 32};

// ─── §3.5 Contrôle de flux ────────────────────────────────────────────────────
const int _flowCanSend = 0x01;
const int _flowStop    = 0x02;

// ─── Layout HUD 3 zones ───────────────────────────────────────────────────────
//
//  §5.7 : (x, y) = coin supérieur-gauche du premier caractère (top-left).
//  §6.4 : zone utile recommandée : x∈[8, 295], y∈[8, 247] (marge 8px).
//
//  ┌────────────────────────────────────┐ y=0
//  │  DIST          ← font 1, couleur gris, x=10
//  │  0.00 km       ← font 3, couleur blanc, x=10
//  ├────────────────────────────────────┤ sep y=72
//  │  BPM
//  │  145
//  ├────────────────────────────────────┤ sep y=144
//  │  KCAL
//  │  320
//  └────────────────────────────────────┘ y=255
//
//  Calcul :
//    Zone 1  label y=10         (h=16 → bas à y=26)
//            value y=34         (h=32 → bas à y=66)
//            sep   y=72
//    Zone 2  label y=80         (h=16 → bas à y=96)
//            value y=104        (h=32 → bas à y=136)
//            sep   y=142
//    Zone 3  label y=150        (h=16 → bas à y=166)
//            value y=174        (h=32 → bas à y=206)
//
const int _xLeft      = 10;   // marge gauche standard
const int _yDistLabel = 10;
const int _yDistValue = 34;
const int _ySep1      = 72;
const int _yBpmLabel  = 80;
const int _yBpmValue  = 104;
const int _ySep2      = 142;
const int _yKcalLabel = 150;
const int _yKcalValue = 174;
const int _kSafeMarginX = 16;

// ─── Modèle ───────────────────────────────────────────────────────────────────
enum BleConnectionPhase {
  idle, connecting, connected, initializing, ready, disconnecting, disconnected, failed,
}

class BleConnectionStatus {
  final String? deviceId;
  final BleConnectionPhase phase;
  final String message;
  final String? error;
  final DateTime updatedAt;

  const BleConnectionStatus({
    required this.phase, this.deviceId, required this.message,
    this.error, required this.updatedAt,
  });

  BleConnectionStatus.idle() : this(
    phase: BleConnectionPhase.idle,
    message: 'Prêt pour une connexion BLE',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  bool get isBusy =>
      phase == BleConnectionPhase.connecting  ||
          phase == BleConnectionPhase.connected   ||
          phase == BleConnectionPhase.initializing ||
          phase == BleConnectionPhase.disconnecting;
}

class SportMetrics {
  final double distanceMiles;
  final int bpm;
  final int kcal;
  final int? battery;
  final bool? gestureDetected;
  final bool? touchDetected;

  const SportMetrics({
    this.distanceMiles = 0, this.bpm = 0, this.kcal = 0,
    this.battery, this.gestureDetected, this.touchDetected,
  });

  static int estimateKcal({
    required int bpm, required double weightKg, required int ageYears,
    required bool isMale, required int durationSeconds,
  }) {
    final min = durationSeconds / 60.0;
    if (isMale) {
      return ((-55.0969 + 0.6309*bpm + 0.1988*weightKg + 0.2017*ageYears) / 4.184 * min).round();
    } else {
      return ((-20.4022 + 0.4472*bpm - 0.1263*weightKg + 0.074*ageYears) / 4.184 * min).round();
    }
  }

  static double haversineDistanceMiles(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 3958.8;
    final dLat = _rad(lat2 - lat1), dLon = _rad(lon2 - lon1);
    final a = sin(dLat/2)*sin(dLat/2) +
        cos(_rad(lat1))*cos(_rad(lat2))*sin(dLon/2)*sin(dLon/2);
    return r * 2 * atan2(sqrt(a), sqrt(1-a));
  }
  static double _rad(double d) => d * pi / 180;
}

// ─── Service ──────────────────────────────────────────────────────────────────
class BleTelemetryService {
  BleTelemetryService({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  StreamSubscription<DiscoveredDevice>?      _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>?             _txSub, _controlSub, _gestureSub, _touchSub, _batterySub;

  final _devicesCtrl          = StreamController<List<DiscoveredDevice>>.broadcast();
  final _metricsCtrl          = StreamController<SportMetrics>.broadcast();
  final _connectionCtrl       = StreamController<DeviceConnectionState>.broadcast();
  final _connectionStatusCtrl = StreamController<BleConnectionStatus>.broadcast();

  Stream<List<DiscoveredDevice>> get devicesStream          => _devicesCtrl.stream;
  Stream<SportMetrics>           get metricsStream          => _metricsCtrl.stream;
  Stream<DeviceConnectionState>  get connectionStream       => _connectionCtrl.stream;
  Stream<BleConnectionStatus>    get connectionStatusStream => _connectionStatusCtrl.stream;

  final List<DiscoveredDevice> _devices = [];
  String? connectedDeviceId;
  bool _canSendData         = true;
  bool _displaySessionActive = false;
  BleConnectionStatus _connectionStatus = BleConnectionStatus.idle();

  bool get isDisplaySessionActive => _displaySessionActive;
  BleConnectionStatus get connectionStatus => _connectionStatus;

  static final _serviceUuid = Uuid.parse(_kServiceUuid);
  static final _txUuid      = Uuid.parse(_kTxUuid);
  static final _rxUuid      = Uuid.parse(_kRxUuid);
  static final _controlUuid = Uuid.parse(_kControlUuid);
  static final _gestureUuid = Uuid.parse(_kGestureUuid);
  static final _touchUuid   = Uuid.parse(_kTouchUuid);
  static final _batteryUuid = Uuid.parse(_kBatteryUuid);

  int _negotiatedMtu = 20;
  final _cmdQueue        = <(String, List<int>)>[];
  bool  _cmdQueueRunning = false;

  // ─── Helpers §5.7 ─────────────────────────────────────────────────────────
  // Centrage horizontal : retourne le x du coin supérieur-gauche du texte.
  // §5.7 : (x,y) = top-left du premier caractère.

  /*int _centerX(String text, int fontId) {
    final textWidth = (_kFontCharW[fontId] ?? 10) * text.length;

    final minX = _kSafeMarginX;
    final maxX = _kDisplayW - textWidth - _kSafeMarginX;

    return ((_kDisplayW - textWidth) / 2)
        .clamp(minX, maxX)
        .toInt();
  }*/



  // ─── Scan ─────────────────────────────────────────────────────────────────
  Future<void> startScan() async {
    await _scanSub?.cancel();
    _devices.clear();
    _devicesCtrl.add(const []);
    _scanSub = _ble
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen((d) {
      final i = _devices.indexWhere((e) => e.id == d.id);
      i >= 0 ? _devices[i] = d : _devices.add(d);
      _devicesCtrl.add(List.unmodifiable(_devices));
    }, onError: _devicesCtrl.addError);
  }

  Future<void> stopScan() async { await _scanSub?.cancel(); _scanSub = null; }

  // ─── Queue ────────────────────────────────────────────────────────────────
  Future<void> enqueueCommand(String deviceId, List<int> cmd) async {
    _cmdQueue.add((deviceId, cmd));
    if (!_cmdQueueRunning) unawaited(_drainCommandQueue());
  }

  Future<void> _drainCommandQueue() async {
    _cmdQueueRunning = true;
    while (_cmdQueue.isNotEmpty) {
      if (!_canSendData) { await Future.delayed(const Duration(milliseconds: 20)); continue; }
      final (id, cmd) = _cmdQueue.removeAt(0);
      try { await sendCommand(id, cmd); } catch (e) { debugPrint('⚠️ BLE cmd failed: $e'); }
      await Future.delayed(const Duration(milliseconds: 8));
    }
    _cmdQueueRunning = false;
  }

  // ─── Écrans de session ────────────────────────────────────────────────────
  Future<void> _showReadyScreen(String deviceId) async {
    await enqueueCommand(deviceId, _buildFrame(_cmdHoldFlush, [_actionHold]));
    await enqueueCommand(deviceId, _buildFrame(_cmdClear, []));

    const text = 'READY';
    // Centre vertical : y = (H - fontH) / 2
    final yText = (_kDisplayH - (_kFontCharH[_kFontValue] ?? 32)) ~/ 2;
    await enqueueCommand(deviceId, _buildTextCommand(
      x: 250, y: yText,
      fontId: _kFontValue, color: _kColorWhite, text: text,
    ));

    const sub = 'Session en cours...';
    await enqueueCommand(deviceId, _buildTextCommand(
      x: 250, y: yText + (_kFontCharH[_kFontValue] ?? 32) + 8,
      fontId: _kFontSmall, color: _kColorGray, text: sub,
    ));

    await enqueueCommand(deviceId, _buildFrame(_cmdHoldFlush, [_actionFlush]));
    await Future.delayed(const Duration(milliseconds: 1500));
  }

  Future<void> _showCountdown(String deviceId) async {
    for (final step in ['3', '2', '1', 'GO!']) {
      await enqueueCommand(deviceId, _buildFrame(_cmdHoldFlush, [_actionHold]));
      await enqueueCommand(deviceId, _buildFrame(_cmdClear, []));
      final h = _kFontCharH[_kFontBig] ?? 24;
      await enqueueCommand(deviceId, _buildTextCommand(
        x: 250, y: (_kDisplayH - h) ~/ 2,
        fontId: _kFontBig, color: _kColorWhite, text: step,
      ));
      await enqueueCommand(deviceId, _buildFrame(_cmdHoldFlush, [_actionFlush]));
      await Future.delayed(step == 'GO!' ? const Duration(milliseconds: 800) : const Duration(seconds: 1));
    }
  }

  // ─── Connexion ────────────────────────────────────────────────────────────
  Future<void> connectAndListen(String deviceId) async {
    await disconnect();
    _emitStatus(BleConnectionPhase.connecting, deviceId: deviceId, message: 'Connexion BLE...');

    _connectionSub = _ble
        .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 12))
        .listen((update) async {
      _connectionCtrl.add(update.connectionState);

      if (update.connectionState == DeviceConnectionState.connected) {
        connectedDeviceId = deviceId;
        _emitStatus(BleConnectionPhase.connected, deviceId: deviceId, message: 'Connexion établie');
        _emitStatus(BleConnectionPhase.initializing, deviceId: deviceId, message: 'Initialisation...');
        try {
          _negotiatedMtu = (await _ble.requestMtu(deviceId: deviceId, mtu: _kTargetMtu)) - 3;
          debugPrint('✅ MTU: $_negotiatedMtu B');
        } catch (e) { _negotiatedMtu = 20; debugPrint('⚠️ MTU fallback 20B: $e'); }

        await _subscribeAll(deviceId);
        _displaySessionActive = false;
        await Future.delayed(const Duration(milliseconds: 200));
        await enqueueCommand(deviceId, _buildFrame(_cmdBattery, []));
        _emitStatus(BleConnectionPhase.ready, deviceId: deviceId, message: 'Lunettes prêtes');
      }

      if (update.connectionState == DeviceConnectionState.disconnected) {
        connectedDeviceId = null;
        _displaySessionActive = false;
        _emitStatus(BleConnectionPhase.disconnected, deviceId: deviceId, message: 'Déconnecté');
        await _cancelCharSubs();
      }
    }, onError: (e) {
      _emitStatus(BleConnectionPhase.failed, deviceId: deviceId, message: 'Connexion échouée', error: e.toString());
      _connectionCtrl.addError(e);
    });
  }

  // ─── Session ──────────────────────────────────────────────────────────────
  Future<void> startDisplaySession([String? deviceId]) async {
    final target = deviceId ?? connectedDeviceId;
    if (target == null || _displaySessionActive) return;
    _emitStatus(BleConnectionPhase.initializing, deviceId: target, message: 'Démarrage session...');

    await enqueueCommand(target, _buildFrame(_cmdDisplayPower, [0x01]));
    await Future.delayed(const Duration(milliseconds: 300));

    // Désactive uniquement l'ALS (auto-brightness), garde le geste (§4.5)
    await enqueueCommand(target, _buildFrame(_cmdAlsOnly, [0x00]));

    // §4.4 Luminosité : 0x0F = niveau 15 = maximum (sport extérieur)
    await enqueueCommand(target, _buildFrame(_cmdLuminance, [0x0F]));
    await Future.delayed(const Duration(milliseconds: 100));

    // ResetFlush : remet holdFlush à zéro (état inconnu après connexion)
    await enqueueCommand(target, _buildFrame(_cmdHoldFlush, [_actionResetFlush]));
    await Future.delayed(const Duration(milliseconds: 100));

    // Efface "Connection successful" affiché par le firmware
    await enqueueCommand(target, _buildFrame(_cmdClear, []));
    await Future.delayed(const Duration(milliseconds: 300));

    await _showReadyScreen(target);
    await _showCountdown(target);

    await enqueueCommand(target, _buildFrame(_cmdHoldFlush, [_actionResetFlush]));
    await enqueueCommand(target, _buildFrame(_cmdClear, []));
    await Future.delayed(const Duration(milliseconds: 100));

    _displaySessionActive = true;
    _emitStatus(BleConnectionPhase.ready, deviceId: target, message: 'Session ActiveLook active');
  }

  Future<void> stopDisplaySession() async {
    final target = connectedDeviceId;
    if (!_displaySessionActive) return;
    _emitStatus(BleConnectionPhase.disconnecting, deviceId: target, message: 'Arrêt session...');

    if (target != null) {
      await enqueueCommand(target, _buildFrame(_cmdHoldFlush, [_actionHold]));
      await enqueueCommand(target, _buildFrame(_cmdClear, []));
      const msg = 'Session terminee';
      await enqueueCommand(target, _buildTextCommand(
        x: 250, y: (_kDisplayH - 16) ~/ 2,
        fontId: _kFontSmall, color: _kColorWhite, text: msg,
      ));
      await enqueueCommand(target, _buildFrame(_cmdHoldFlush, [_actionFlush]));
      await Future.delayed(const Duration(seconds: 1));
      await enqueueCommand(target, _buildFrame(_cmdDisplayPower, [0x00]));
    }

    _displaySessionActive = false;
    _emitStatus(BleConnectionPhase.ready, deviceId: target, message: 'Session arrêtée');
  }

  // ─── Abonnements ──────────────────────────────────────────────────────────
  Future<void> _subscribeAll(String deviceId) async {
    QualifiedCharacteristic char(Uuid uuid) => QualifiedCharacteristic(
      deviceId: deviceId, serviceId: _serviceUuid, characteristicId: uuid,
    );

    _txSub      = _ble.subscribeToCharacteristic(char(_txUuid)).listen(_parseTxFrame, onError: _metricsCtrl.addError);
    _controlSub = _ble.subscribeToCharacteristic(char(_controlUuid)).listen((b) {
      if (b.isEmpty) return;
      final v = b[0];
      _canSendData = (v == _flowCanSend);
      if (v == _flowStop) {
        debugPrint('⚠️ ActiveLook buffer 75%: pause');
      } else if (v >= 0x03) {
        debugPrint('⚠️ ActiveLook erreur: 0x${v.toRadixString(16)}');
      }
    });
    _gestureSub = _ble.subscribeToCharacteristic(char(_gestureUuid)).listen((b) {
      if (b.isNotEmpty && b[0] == 0x01) _metricsCtrl.add(const SportMetrics(gestureDetected: true));
    });
    _touchSub   = _ble.subscribeToCharacteristic(char(_touchUuid)).listen((b) {
      if (b.isNotEmpty && b[0] == 0x01) _metricsCtrl.add(const SportMetrics(touchDetected: true));
    });
    _batterySub = _ble.subscribeToCharacteristic(QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse("0000180F-0000-1000-8000-00805F9B34FB"),
      characteristicId: _batteryUuid,
    )).listen((b) {
      if (b.isNotEmpty) _metricsCtrl.add(SportMetrics(battery: b[0].clamp(0, 100)));
    });
  }

  void _parseTxFrame(List<int> bytes) {
    if (bytes.length < 5 || bytes[0] != 0xFF || bytes.last != 0xAA) return;
    final cmdId = bytes[1];
    final data  = bytes.sublist(4, bytes.length - 1);
    if (cmdId == _cmdBattery && data.isNotEmpty) {
      _metricsCtrl.add(SportMetrics(battery: data[0].clamp(0, 100)));
    }
  }

  // ─── Affichage HUD ────────────────────────────────────────────────────────
  //
  // CORRECTIONS §5.7 appliquées :
  //   1. Hold avant le Clear → rendu atomique (pas de ghosting)
  //   2. Clear obligatoire avant chaque frame → les valeurs précédentes sont
  //      effacées (sinon les anciens chiffres persistent sous les nouveaux)
  //   3. Les labels utilisent _kFontSmall (font 1) et _kColorGray pour
  //      différencier visuellement label / valeur
  //   4. Les valeurs utilisent _kFontValue (font 3, ~32px) pour la lisibilité
  //      en mouvement (sport)
  //   5. _centerX recalculé avec le bon font pour chaque texte
  //   6. Les séparateurs horizontaux sont réactivés (struct visuelle)
  //   7. Flush à la fin → rendu en une seule passe sans flickering
  //
  Future<void> displayMetrics(
      String deviceId, {
        required double distanceMiles,
        required int bpm,
        required int kcal,
      }) async {
    if (!_displaySessionActive || !_canSendData) return;

    final distKm  = distanceMiles * 1.60934;
    final distStr = '${distKm.toStringAsFixed(2)} km';
    final bpmStr  = '$bpm bpm';
    final kcalStr = '$kcal kcal';
    debugPrint("distance $distStr");
    debugPrint("bpm $bpmStr");
    debugPrint("kcal $kcalStr");

    // ── Début rendu atomique ──────────────────────────────────────────────
    await enqueueCommand(deviceId, _buildFrame(_cmdHoldFlush, [_actionHold]));
    await enqueueCommand(deviceId, _buildFrame(_cmdClear, []));

    // ── DIST ─────────────────────────────────────────────────────────────
    /*await enqueueCommand(deviceId, _buildTextCommand(
      x: _centerX('DIST', _kFontSmall), y: _yDistLabel, fontId: _kFontSmall, color: _kColorGray, text: 'DIST',
    ));*/


    await enqueueCommand(deviceId, _buildTextCommand(
      x: 250,
      y: _yDistValue + 20,
      fontId: _kFontValue,
      color: _kColorWhite,
      text: distStr,
    ));

    // ── BPM ──────────────────────────────────────────────────────────────
    /*await enqueueCommand(deviceId, _buildTextCommand(
      x: _centerX('BPM', _kFontSmall), y: _yBpmLabel, fontId: _kFontSmall, color: _kColorGray, text: 'BPM',
    ));*/
    await enqueueCommand(deviceId, _buildTextCommand(
      x: 250,
      y: _yBpmValue + 20,
      fontId: _kFontValue,
      color: _kColorWhite,
      text: bpmStr,
    ));

    // ── KCAL ─────────────────────────────────────────────────────────────
    /*await enqueueCommand(deviceId, _buildTextCommand(
      x: _centerX('KCAL', _kFontSmall), y: _yKcalLabel, fontId: _kFontSmall, color: _kColorGray, text: 'KCAL',
    ));*/
    await enqueueCommand(deviceId, _buildTextCommand(
      x: 250,
      y: _yKcalValue +20 ,
      fontId: _kFontValue,
      color: _kColorWhite,
      text: kcalStr,
    ));

    // ── Fin rendu atomique ────────────────────────────────────────────────
    await enqueueCommand(deviceId, _buildFrame(_cmdHoldFlush, [_actionFlush]));
  }

  // ─── §3.1 Construction trames binaires ───────────────────────────────────
  //
  // Format doc §3.1 :
  //   [0xFF][cmdId][CmdFormat=0x00][Length][Data...][0xAA]
  //   Length = total bytes (header 4B + data + footer 1B)
  //
  List<int> _buildFrame(int cmdId, List<int> data) {
    final length = 5 + data.length;
    return [0xFF, cmdId, 0x00, length, ...data, 0xAA];
  }

  // §5.7 Text — format exact du payload :
  //   s16 x  (2B big-endian)
  //   s16 y  (2B big-endian)   → coin supérieur-gauche du premier caractère
  //   u8  r  (1B)              → rotation en degrés (0x04 pour Engo)
  //   u8  f  (1B)              → font id (1, 2 ou 3)
  //   u8  c  (1B)              → couleur 0–15 (0x0F = blanc max)
  //   str    (nB)              → ASCII, PAS de null-terminator nécessaire
  //                               (le firmware lit jusqu'au footer 0xAA)
  List<int> _buildTextCommand({
    required int x, required int y,
    required int fontId, required int color,
    required String text,
  }) {
    return _buildFrame(_cmdTxtDisplay, [
      (x >> 8) & 0xFF, x & 0xFF,    // s16 x big-endian
      (y >> 8) & 0xFF, y & 0xFF,    // s16 y big-endian
      _kTextRotation,                // u8  r = 0x04 (miroir Engo)
      fontId,                        // u8  f
      color,                         // u8  c
      ...text.codeUnits,             // str ASCII
    ]);
  }

  // ─── Envoi BLE → caractéristique RX ──────────────────────────────────────
  Future<void> sendCommand(String deviceId, List<int> commandBytes) async {
    if (!_canSendData) return;
    final rxChar  = QualifiedCharacteristic(deviceId: deviceId, serviceId: _serviceUuid, characteristicId: _rxUuid);
    final chunk   = _negotiatedMtu.clamp(20, _kMaxChunkSize);

    if (commandBytes.length <= chunk) {
      debugPrint('📡 BLE ${commandBytes.length}B cmd=0x${commandBytes[1].toRadixString(16)}');
      await _ble.writeCharacteristicWithResponse(rxChar, value: commandBytes);
    } else {
      debugPrint('📡 BLE fragmenté ${commandBytes.length}B → ${chunk}B/chunk');
      for (var i = 0; i < commandBytes.length; i += chunk) {
        await _ble.writeCharacteristicWithResponse(rxChar, value: commandBytes.sublist(i, (i+chunk).clamp(0, commandBytes.length)));
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────
  Future<void> _cancelCharSubs() async {
    for (final s in [_txSub, _controlSub, _gestureSub, _touchSub, _batterySub]) {
      await s?.cancel();
    }
    _txSub = _controlSub = _gestureSub = _touchSub = _batterySub = null;
  }

  Future<void> disconnect() async {
    _emitStatus(BleConnectionPhase.disconnecting, deviceId: connectedDeviceId, message: 'Déconnexion...');
    await _cancelCharSubs();
    await _connectionSub?.cancel();
    _connectionSub = null;
    connectedDeviceId = null;
    _displaySessionActive = false;
    _emitStatus(BleConnectionPhase.disconnected, message: 'Déconnecté');
  }

  Future<void> dispose() async {
    await stopScan();
    await disconnect();
    for (final c in [_devicesCtrl, _metricsCtrl, _connectionCtrl, _connectionStatusCtrl]) {
      await c.close();
    }
  }

  void _emitStatus(BleConnectionPhase phase, {
    String? deviceId, required String message, String? error,
  }) {
    final s = BleConnectionStatus(
      phase: phase,
      deviceId: deviceId ?? _connectionStatus.deviceId,
      message: message,
      error: error,
      updatedAt: DateTime.now(),
    );
    _connectionStatus = s;
    _connectionStatusCtrl.add(s);
  }
}