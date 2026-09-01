import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint, VoidCallback;
import 'package:geolocator/geolocator.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/ble_sensor_service.dart';
import '../core/ble_telemetry_service.dart';
import '../data/remote_posture.dart';
import '../data/remote_telemetry.dart';
import '../presentation/widgets/participant_info.dart';
import 'controls_viewmodel.dart';
import 'pose_detection_viewmodel.dart';

class RoomViewModel extends ChangeNotifier {
  // ── Services ──
  final BleTelemetryService bleService = BleTelemetryService();
  final BleSensorService sensorService = BleSensorService();
  final PoseDetectionViewModel poseViewModel = PoseDetectionViewModel();
  late final ControlsViewModel controlsViewModel;

  // ── Callbacks ──
  VoidCallback? _onDisconnected;

  // ── Room references ──
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  // ── Telemetry ──
  Timer? _telemetryTimer;
  double _simT = 0.0;
  DateTime? _lastGlassesDisplayTime;

  // ── GPS ──
  StreamSubscription<Position>? _gpsSub;
  double _totalDistanceMiles = 0.0;
  Position? _lastPosition;

  // ── Sensors ──
  StreamSubscription<int>? _hrmSub;
  StreamSubscription<int>? _cadenceSub;
  StreamSubscription<SensorStatus>? _hrmStatusSub;
  StreamSubscription<SensorStatus>? _cscStatusSub;
  int? _sensorHeartRate;
  int? _sensorCadence;

  // ── BLE glasses ──
  StreamSubscription<SportMetrics>? _bleMetricsSub;
  SportMetrics? _bleMetrics;

  // ── Participants ──
  List<ParticipantTrack> _participantTracks = [];
  final Map<String, RemotePosture> _remotePostures = {};
  final Map<String, RemoteTelemetry> _remoteTelemetry = {};

  // ── Posture PIP ──
  bool _showPosePip = true;

  // ── Getters ──
  Room? get room => _room;
  EventsListener<RoomEvent>? get listener => _listener;
  List<ParticipantTrack> get participantTracks => _participantTracks;
  int? get sensorHeartRate => _sensorHeartRate;
  int? get sensorCadence => _sensorCadence;
  SportMetrics? get bleMetrics => _bleMetrics;
  double get totalDistanceMiles => _totalDistanceMiles;
  bool get showPosePip => _showPosePip;

  void togglePosePip() {
    _showPosePip = !_showPosePip;
    notifyListeners();
  }

  RemotePosture? posturesForParticipant(Participant participant) {
    return _remotePostures[participant.identity];
  }

  RemoteTelemetry? telemetryForParticipant(Participant participant) {
    return _remoteTelemetry[participant.identity];
  }

  RemoteTelemetry get localTelemetry => RemoteTelemetry(
    heartRate: sensorService.isHrmConnected ? _sensorHeartRate : null,
    cadence: sensorService.isCadenceConnected ? _sensorCadence?.toDouble() : null,
    speed: _lastPosition != null
        ? double.parse((_lastPosition!.speed * 3.6).toStringAsFixed(1))
        : null,
    lat: _lastPosition?.latitude,
    lng: _lastPosition?.longitude,
    role: 'trainee',
    receivedAt: DateTime.now(),
  );

  ParticipantTrack? get primaryTrack {
    for (final track in _participantTracks) {
      if (track.participant is LocalParticipant &&
          track.type == ParticipantTrackType.kUserMedia) {
        return track;
      }
    }
    return _participantTracks.isNotEmpty ? _participantTracks.first : null;
  }

  List<ParticipantTrack> get secondaryTracks {
    final primary = primaryTrack;
    if (primary == null) return _participantTracks;
    return _participantTracks.where((t) => t != primary).toList();
  }

  // ── Init ──
  Future<void> init(Room room, EventsListener<RoomEvent> listener, {VoidCallback? onDisconnected}) async {
    _room = room;
    _listener = listener;
    _onDisconnected = onDisconnected;

    // Keep screen on during call
    unawaited(WakelockPlus.enable());

    controlsViewModel = ControlsViewModel();
    controlsViewModel.init(
      participant: room.localParticipant!,
      room: room,
      bleService: bleService,
      sensorService: sensorService,
      onBleConnected: onBleConnected,
      onBleDisconnected: onBleDisconnected,
    );

    room.addListener(_onRoomDidUpdate);
    _setUpListeners();
    _sortParticipants();

    await poseViewModel.init();

    _startTelemetry();
    poseViewModel.start(room);
    _startGps();
    _startSensorListeners();
  }

  // ── Room event listeners ──
  void _setUpListeners() {
    final listener = _listener;
    if (listener == null) return;

    listener
      ..on<RoomDisconnectedEvent>((event) {
        _stopTelemetry();
        poseViewModel.stop();
        _onDisconnected?.call();
      })
      ..on<ParticipantEvent>((event) => _sortParticipants())
      ..on<LocalTrackPublishedEvent>((_) => _sortParticipants())
      ..on<LocalTrackUnpublishedEvent>((_) => _sortParticipants())
      ..on<TrackSubscribedEvent>((_) => _sortParticipants())
      ..on<TrackUnsubscribedEvent>((_) => _sortParticipants())
      ..on<ParticipantConnectedEvent>((event) => _sortParticipants())
      ..on<ParticipantDisconnectedEvent>((event) {
        _remotePostures.remove(event.participant.identity);
        _remoteTelemetry.remove(event.participant.identity);
        _sortParticipants();
      })
      ..on<DataReceivedEvent>((event) {
        try {
          final decoded = utf8.decode(event.data);
          _handleIncomingData(event.participant, decoded, event.topic);
        } catch (err) {
          debugPrint('Failed to decode data: $err');
        }
      });
  }

  void _onRoomDidUpdate() => _sortParticipants();

  // ── Telemetry ──
  void _startTelemetry() {
    _telemetryTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      _sendTelemetryTick,
    );
    debugPrint('📡 Telemetry started (2 Hz)');
  }

  void _stopTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }

  void _sendTelemetryTick(Timer timer) {
    final room = _room;
    if (room == null || room.connectionState != ConnectionState.connected) return;

    _simT += 0.5;
    
    // Use actual sensor data, null if not connected
    final heartRate = sensorService.isHrmConnected ? _sensorHeartRate?.toDouble() : null;
    final cadence = sensorService.isCadenceConnected ? _sensorCadence?.toDouble() : null;

    // Use real GPS data, null if not available (removed simulation)
    final position = _lastPosition;
    double? speed;
    double? lat;
    double? lng;
    
    if (position != null) {
      speed = double.parse((position.speed * 3.6).toStringAsFixed(1));
      lat = double.parse(position.latitude.toStringAsFixed(6));
      lng = double.parse(position.longitude.toStringAsFixed(6));
    }

    final payload = {
      "type": "telemetry",
      "ts": DateTime.now().millisecondsSinceEpoch,
      "payload": {
        "role": "trainee",
        "speed": speed,
        "heart_rate": heartRate,
        "cadence": cadence,
        "gps": lat != null && lng != null ? {"lat": lat, "lng": lng} : null,
      },
    };

    try {
      room.localParticipant?.publishData(
        utf8.encode(jsonEncode(payload)),
        reliable: true,
        topic: 'telemetry',
      );
    } catch (e) {
      debugPrint('⚠️ Telemetry publish error: $e');
    }

    if (heartRate != null) {
      _pushGlassesDisplay(heartRate);
    }
  }

  void _pushGlassesDisplay(double heartRate) {
    final deviceId = bleService.connectedDeviceId;
    if (deviceId == null || !bleService.isDisplaySessionActive) return;

    final now = DateTime.now();
    if (_lastGlassesDisplayTime != null &&
        now.difference(_lastGlassesDisplayTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastGlassesDisplayTime = now;

    // Use actual distance and calories based on HRM
    final dist = _totalDistanceMiles;
    final kcal = (heartRate * 0.05 * _simT / 60).round().clamp(0, 9999);

    unawaited(
      bleService.displayMetrics(
        deviceId,
        distanceMiles: dist,
        bpm: heartRate.round().clamp(30, 220),
        kcal: kcal,
        cadence: _sensorCadence,
      ),
    );
  }

  // ── GPS ──
  Future<void> _startGps() async {
    _gpsSub?.cancel();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('⚠️ GPS: Location services are disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('⚠️ GPS: Location permission denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('⚠️ GPS: Location permission denied forever');
      return;
    }

    try {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((position) {
        if (_lastPosition != null) {
          final delta = SportMetrics.haversineDistanceMiles(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          _totalDistanceMiles += delta;
        }
        _lastPosition = position;
      });
      debugPrint('📍 GPS tracking started');
    } catch (e) {
      debugPrint('⚠️ GPS error: $e');
    }
  }

  void _stopGps() {
    _gpsSub?.cancel();
    _gpsSub = null;
  }

  // ── Sensors ──
  void _startSensorListeners() {
    _hrmSub?.cancel();
    _cadenceSub?.cancel();
    _hrmStatusSub?.cancel();
    _cscStatusSub?.cancel();

    _hrmSub = sensorService.heartRateStream.listen((bpm) {
      _sensorHeartRate = bpm;
      notifyListeners();
    });

    _cadenceSub = sensorService.cadenceStream.listen((rpm) {
      _sensorCadence = rpm;
      notifyListeners();
    });

    _hrmStatusSub = sensorService.hrmStatusStream.listen((status) {
      debugPrint('💓 HRM status: ${status.state}');
    });

    _cscStatusSub = sensorService.cscStatusStream.listen((status) {
      debugPrint('🚴 CSC status: ${status.state}');
    });
  }

  // ── BLE glasses ──
  void onBleConnected() {
    _bleMetricsSub?.cancel();
    _bleMetricsSub = bleService.metricsStream.listen((data) {
      _bleMetrics = data;
      notifyListeners();
    });
    notifyListeners();
  }

  void onBleDisconnected() {
    _bleMetrics = null;
    notifyListeners();
  }

  // ── Participant sorting ──
  void _handleIncomingData(
    Participant? participant,
    String decoded,
    String? topic,
  ) {
    if (participant == null) return;
    try {
      final data = jsonDecode(decoded);
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);

      if (topic == 'telemetry' || map['type'] == 'telemetry') {
        final telemetry = RemoteTelemetry.tryParse(map);
        if (telemetry != null) {
          _remoteTelemetry[participant.identity] = telemetry;
          notifyListeners();
        }
        return;
      }

      final posture = RemotePosture.tryParse(map);
      if (posture != null) {
        _remotePostures[participant.identity] = posture;
        _sortParticipants();
      }
    } catch (error) {
      debugPrint('⚠️ Invalid incoming data: $error');
    }
  }

  void _sortParticipants() {
    final room = _room;
    if (room == null) return;

    final activeIdentities = <String>{
      if (room.localParticipant != null) room.localParticipant!.identity,
      ...room.remoteParticipants.values.map((p) => p.identity),
    };
    _remotePostures.removeWhere(
      (identity, _) => !activeIdentities.contains(identity),
    );

    final userMediaTracks = <ParticipantTrack>[];
    final screenTracks = <ParticipantTrack>[];

    for (var participant in room.remoteParticipants.values) {
      for (var t in participant.videoTrackPublications) {
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
            participant: participant,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          userMediaTracks.add(ParticipantTrack(
            participant: participant,
            posture: _remotePostures[participant.identity],
            telemetry: _remoteTelemetry[participant.identity],
          ));
        }
      }
    }

    userMediaTracks.sort((a, b) {
      if (a.participant.isSpeaking && b.participant.isSpeaking) {
        return a.participant.audioLevel > b.participant.audioLevel ? -1 : 1;
      }
      final aSpokeAt = a.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      final bSpokeAt = b.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      if (aSpokeAt != bSpokeAt) return aSpokeAt > bSpokeAt ? -1 : 1;
      return a.participant.joinedAt.millisecondsSinceEpoch -
          b.participant.joinedAt.millisecondsSinceEpoch;
    });

    final localTracks = room.localParticipant?.videoTrackPublications;
    if (localTracks != null) {
      for (var t in localTracks) {
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
            participant: room.localParticipant!,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          userMediaTracks.add(ParticipantTrack(
            participant: room.localParticipant!,
            posture: _remotePostures[room.localParticipant!.identity],
            telemetry: localTelemetry,
            pose: poseViewModel.currentPose,
            poseFrameSize: poseViewModel.currentFrameSize,
            avatarOnly: true,
            showPosePip: _showPosePip,
          ));
        }
      }
    }

    _participantTracks = [...screenTracks, ...userMediaTracks];
    notifyListeners();
  }

  // ── Cleanup ──
  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    _stopTelemetry();
    _stopGps();
    unawaited(_bleMetricsSub?.cancel());
    unawaited(_hrmSub?.cancel());
    unawaited(_cadenceSub?.cancel());
    unawaited(_hrmStatusSub?.cancel());
    unawaited(_cscStatusSub?.cancel());
    unawaited(bleService.dispose());
    unawaited(sensorService.dispose());
    unawaited(poseViewModel.dispose());
    controlsViewModel.dispose();
    _room?.removeListener(_onRoomDidUpdate);
    unawaited(_listener?.dispose());
    unawaited(_room?.dispose());
    super.dispose();
  }
}
