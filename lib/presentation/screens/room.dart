import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:geolocator/geolocator.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/ble_telemetry_service.dart';
import '../../core/posture_detection_service.dart';
import '../../data/remote_posture.dart';
import '../../utils.dart';

import '../widgets/controls.dart';
import '../widgets/participant.dart';
import '../widgets/participant_info.dart';

// En dev local : pointe vers le dashboard-api Docker expos� sur :8000
// En prod      : remplacer par l'URL publique de ton API
const String kApiBaseUrl = 'https://api.videolog.app';

Map<String, dynamic> _buildTelemetryPayload({
  required double speed,
  required double heartRate,
  required double cadence,
  required double lat,
  required double lng,
}) {
  return {
    "type": "telemetry",
    "ts": DateTime.now().millisecondsSinceEpoch, // cl� de sync PTS
    "payload": {
      "role": "trainee",
      "speed": speed,
      "heart_rate": heartRate,
      "cadence": cadence,
      "gps": {"lat": lat, "lng": lng},
    },
  };
}

class _LocalPoseAnalysis {
  const _LocalPoseAnalysis({
    required this.pose,
    required this.frameSize,
    required this.posture,
  });

  final Pose pose;
  final Size frameSize;
  final RemotePosture? posture;
}

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
  List<ParticipantTrack> participantTracks = [];
  final Map<String, RemotePosture> _remotePostures = {};
  EventsListener<RoomEvent> get _listener => widget.listener;
  bool get fastConnection => widget.fastConnection;

  Timer? _telemetryTimer;
  Timer? _poseTimer;
  //int _telemetryCount = 0;
  bool _poseDetectionBusy = false;
  final NpuPoseDetector _poseDetector = NpuPoseDetector(
    config: PoseDetectorConfig.realtime(),
  );

  // Instance de lissage temporel
  final PostureSmoothing _postureSmoothing = PostureSmoothing(alpha: 0.35);

  //RemotePosture? _currentLocalPosture;
  Pose? _currentLocalPose;
  Size? _currentLocalPoseFrameSize;

  final _random = math.Random();
  double _simT = 0.0; // compteur de temps pour variation sinuso�dale

  final BleTelemetryService _bleService = BleTelemetryService();
  StreamSubscription<List<DiscoveredDevice>>? _bleScanSub;
  StreamSubscription<SportMetrics>? _bleMetricsSub;
  SportMetrics? _bleMetrics;

  StreamSubscription<Position>? _gpsSub;
  double _totalDistanceMiles = 0.0;
  Position? _lastPosition;
  DateTime? _lastGlassesDisplayTime;

  @override
  void initState() {
    super.initState();
    widget.room.addListener(_onRoomDidUpdate);
    _setUpListeners();
    _sortParticipants();

    WidgetsBindingCompatible.instance?.addPostFrameCallback((_) async {
      await _onConnectedSetup();
    });

    if (lkPlatformIs(PlatformType.android)) {
      unawaited(Hardware.instance.setSpeakerphoneOn(true));
    }

    if (lkPlatformIsDesktop()) {
      onWindowShouldClose = () async {
        unawaited(widget.room.disconnect());
        await _listener.waitFor<RoomDisconnectedEvent>(
          duration: const Duration(seconds: 5),
        );
      };
    }
  }

  Future<void> _onConnectedSetup() async {
    final participant = widget.room.localParticipant;
    if (participant == null) {
      debugPrint('? Pas de participant local');
      return;
    }
    debugPrint('? Participant pr�t ? init DataTrack');
    await _poseDetector.initialize();
    _startTelemetry();
    _startPoseDetection();
    _startGps();
  }

  void _startGps() {
    _gpsSub?.cancel();
    try {
      _gpsSub =
          Geolocator.getPositionStream(
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
              debugPrint(
                '?? GPS: delta=${delta.toStringAsFixed(4)}mi total=${_totalDistanceMiles.toStringAsFixed(4)}mi',
              );
            }
            _lastPosition = position;
          });
    } catch (e) {
      debugPrint('?? GPS error: $e');
    }
  }

  void _stopGps() {
    _gpsSub?.cancel();
    _gpsSub = null;
  }

  void _onBleConnected() {
    _bleMetricsSub?.cancel();
    _bleMetricsSub = _bleService.metricsStream.listen((data) {
      if (!mounted) return;
      debugPrint(
        '?? BLE metrics: bpm=${data.bpm} kcal=${data.kcal} '
        'distance=${data.distanceMiles}mi battery=${data.battery}% '
        'gesture=${data.gestureDetected} touch=${data.touchDetected}',
      );
      setState(() => _bleMetrics = data);
    });
    setState(() {});
  }

  void _onBleDisconnected() {
    setState(() => _bleMetrics = null);
  }

  void _startTelemetry() {
    _telemetryTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      _sendTelemetryTick,
    );
    debugPrint('?? T�l�m�trie d�marr�e (2 Hz)');
  }

  void _sendTelemetryTick(Timer timer) {
    final connectionState = widget.room.connectionState;
    if (connectionState != ConnectionState.connected) return;

    _simT += 0.5;
    final speed =
        90 + 30 * math.sin(_simT * 0.3) + _random.nextDouble() * 4 - 2;
    final bpmFromGlasses = _bleMetrics?.bpm ?? 0;
    final heartRate = bpmFromGlasses > 0
        ? bpmFromGlasses.toDouble()
        : (145 + _random.nextDouble() * 30);
    final cadence = 150 + _random.nextDouble() * 20;
    final lat = 36.8065 + 0.002 * math.sin(_simT * 0.1);
    final lng = 10.1815 + 0.003 * math.cos(_simT * 0.1);

    final payload = _buildTelemetryPayload(
      speed: double.parse(speed.toStringAsFixed(1)),
      heartRate: heartRate,
      cadence: cadence,
      lat: double.parse(lat.toStringAsFixed(2)),
      lng: double.parse(lng.toStringAsFixed(2)),
    );

    try {
      widget.room.localParticipant?.publishData(
        utf8.encode(jsonEncode(payload)),
        reliable: true,
        topic: 'telemetry',
      );
      //_telemetryCount++;
    } catch (e) {
      debugPrint('? Erreur envoi DataTrack: ');
    }

    final deviceId = _bleService.connectedDeviceId;
    if (deviceId != null && _bleService.isDisplaySessionActive) {
      final now = DateTime.now();
      if (_lastGlassesDisplayTime == null ||
          now.difference(_lastGlassesDisplayTime!) >=
              const Duration(seconds: 2)) {
        _lastGlassesDisplayTime = now;
        unawaited(
          _bleService.displayMetrics(
            deviceId,
            distanceMiles: _totalDistanceMiles > 0
                ? _totalDistanceMiles
                : _simT * 0.02 +
                      0.1 *
                          math.sin(
                            _simT * 0.05,
                          ), // fallback simulé avant les premiers points GPS
            bpm: heartRate.round().clamp(30, 220),
            kcal: (heartRate * 0.05 * _simT / 60)
                .round()
                .clamp(0, 9999),
          ),
        );
      }
    } else if (deviceId != null && !_bleService.isDisplaySessionActive) {
      debugPrint('?? Glasses display skipped: session not started');
    }
  }

  void _stopTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }

  void _startPoseDetection() {
    _poseTimer ??= Timer.periodic(
      const Duration(
        milliseconds: 100,
      ), // Augment� pour plus de r�activit� avec lissage
      (_) => unawaited(_detectPoseTick()),
    );
    debugPrint('?? D�tection de posture ML Kit d�marr�e');
  }

  void _stopPoseDetection() {
    _poseTimer?.cancel();
    _poseTimer = null;
    _poseDetectionBusy = false;
    //_currentLocalPosture = null;
    _currentLocalPose = null;
    _currentLocalPoseFrameSize = null;
  }

  Future<void> _detectPoseTick() async {
    if (!mounted || _poseDetectionBusy || kIsWeb) return;

    final localParticipant = widget.room.localParticipant;
    if (localParticipant == null) return;

    LocalVideoTrack? cameraTrack;
    for (final publication in localParticipant.videoTrackPublications) {
      final track = publication.track;
      if (track != null && track.source == TrackSource.camera) {
        cameraTrack = track;
        break;
      }
    }
    if (cameraTrack == null) return;

    _poseDetectionBusy = true;
    try {
      final analysis = await _detectPoseFromTrack(cameraTrack);
      if (analysis == null) {
        //_currentLocalPosture = null;
        _currentLocalPose = null;
        _currentLocalPoseFrameSize = null;
        _remotePostures.remove(localParticipant.identity);
        _sortParticipants();
        return;
      }

      // Application du lissage temporel
      final rawPose = analysis.pose;
      _currentLocalPose = _postureSmoothing.smooth(rawPose);
      _currentLocalPoseFrameSize = analysis.frameSize;
      //_currentLocalPosture = analysis.posture;

      if (analysis.posture == null) {
        _remotePostures.remove(localParticipant.identity);
      } else {
        _remotePostures[localParticipant.identity] = analysis.posture!;
      }
      _sortParticipants();

      final posture = analysis.posture;
      if (posture != null) {
        final payload = {
          'type': 'posture',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': {
            'posture': posture.label,
            'label': posture.label,
            if (posture.confidence != null) 'confidence': posture.confidence,
            'source': 'mlkit',
          },
        };

        try {
          await localParticipant.publishData(
            utf8.encode(jsonEncode(payload)),
            reliable: true,
            topic: 'posture',
          );
        } catch (error) {
          debugPrint('?? Impossible de publier la posture locale: ');
        }
      }
    } catch (error) {
      debugPrint('?? Erreur d�tection posture ML Kit: ');
    } finally {
      _poseDetectionBusy = false;
    }
  }

  Future<_LocalPoseAnalysis?> _detectPoseFromTrack(
    LocalVideoTrack track,
  ) async {
    try {
      final buffer = await track.mediaStreamTrack.captureFrame();
      final bytes = Uint8List.view(buffer);
      debugPrint('?? captureFrame returned ${bytes.length} bytes');

      // Plus besoin de décoder en RGBA ni de InputImage
      final result = await _poseDetector.detectPose(bytes);
      debugPrint(
        '?? flutter_pose_detection.detectPose.hasPoses=${result.hasPoses}',
      );
      if (!result.hasPoses) return null;

      // Récupérer la taille du frame via décodage minimal
      debugPrint('?? decoding frame for size...');
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frameInfo = await codec.getNextFrame();
        final frameSize = Size(
          frameInfo.image.width.toDouble(),
          frameInfo.image.height.toDouble(),
        );
        debugPrint(
          '?? decoded frame size: ${frameSize.width}x${frameSize.height}',
        );
        frameInfo.image.dispose();

        final pose = result.firstPose!;
        debugPrint(
          '?? detected pose landmarks count: ${pose.landmarks.length}',
        );
        return _LocalPoseAnalysis(
          pose: pose,
          frameSize: frameSize,
          posture: _classifyPosture(pose),
        );
      } finally {
        codec.dispose();
      }
    } catch (error) {
      debugPrint('?? captureFrame/flutter_pose_detection a échoué: $error');
      return null;
    }
  }

  RemotePosture? _classifyPosture(Pose pose) {
    PoseLandmark? landmark(LandmarkType type) => pose.getLandmark(type);
    double averageLikelihood(List<PoseLandmark?> landmarks) {
      final values = landmarks
          .whereType<PoseLandmark>()
          .map((item) => item.visibility)
          .toList();
      if (values.isEmpty) return 0.0;
      return values.reduce((a, b) => a + b) / values.length;
    }

    Offset? midpoint(LandmarkType a, LandmarkType b) {
      final left = landmark(a);
      final right = landmark(b);
      if (left == null || right == null) return null;
      return Offset((left.x + right.x) / 2, (left.y + right.y) / 2);
    }

    final shoulderMid = midpoint(
      LandmarkType.leftShoulder,
      LandmarkType.rightShoulder,
    );
    final hipMid = midpoint(LandmarkType.leftHip, LandmarkType.rightHip);
    if (shoulderMid == null || hipMid == null) return null;

    final kneeMid = midpoint(LandmarkType.leftKnee, LandmarkType.rightKnee);
    final ankleMid = midpoint(LandmarkType.leftAnkle, LandmarkType.rightAnkle);

    final torsoDx = shoulderMid.dx - hipMid.dx;
    final torsoDy = hipMid.dy - shoulderMid.dy;
    final torsoAngleDeg =
        math.atan2(
          torsoDx.abs(),
          torsoDy.abs().clamp(1e-6, double.infinity).toDouble(),
        ) *
        180 /
        math.pi;

    final torsoLength = math.max((hipMid.dy - shoulderMid.dy).abs(), 1.0);
    final kneeDrop = kneeMid == null
        ? 0.0
        : (kneeMid.dy - hipMid.dy) / torsoLength;
    final ankleDrop = ankleMid == null
        ? 0.0
        : (ankleMid.dy - hipMid.dy) / torsoLength;

    final confidence = averageLikelihood([
      landmark(LandmarkType.leftShoulder),
      landmark(LandmarkType.rightShoulder),
      landmark(LandmarkType.leftHip),
      landmark(LandmarkType.rightHip),
    ]);

    final label = torsoAngleDeg > 48
        ? 'allong�'
        : (kneeDrop < 0.35 && ankleDrop < 0.7 ? 'assis' : 'debout');

    return RemotePosture(
      label: label,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      receivedAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _stopTelemetry();
    _stopGps();
    unawaited(_bleScanSub?.cancel());
    unawaited(_bleMetricsSub?.cancel());
    unawaited(_bleService.dispose());
    _stopPoseDetection();
    _poseDetector.dispose();
    widget.room.removeListener(_onRoomDidUpdate);
    unawaited(_disposeRoomAsync());
    onWindowShouldClose = null;
    super.dispose();
  }

  Future<void> _disposeRoomAsync() async {
    await _listener.dispose();
    await widget.room.dispose();
  }

  void _setUpListeners() => _listener
    ..on<RoomDisconnectedEvent>((event) async {
      _stopTelemetry();
      _stopPoseDetection();
      WidgetsBindingCompatible.instance?.addPostFrameCallback(
        (timeStamp) => Navigator.popUntil(context, (route) => route.isFirst),
      );
    })
    ..on<ParticipantEvent>((event) => _sortParticipants())
    ..on<LocalTrackPublishedEvent>((_) => _sortParticipants())
    ..on<LocalTrackUnpublishedEvent>((_) => _sortParticipants())
    ..on<TrackSubscribedEvent>((_) => _sortParticipants())
    ..on<TrackUnsubscribedEvent>((_) => _sortParticipants())
    ..on<ParticipantConnectedEvent>((event) => _sortParticipants())
    ..on<ParticipantDisconnectedEvent>((event) {
      _remotePostures.remove(event.participant.identity);
      _sortParticipants();
    })
    ..on<DataReceivedEvent>((event) {
      try {
        final decoded = utf8.decode(event.data);
        _updatePostureFromData(event.participant, decoded, event.topic);
      } catch (err) {
        debugPrint('Failed to decode posture data: ');
      }
    });

  void _onRoomDidUpdate() => _sortParticipants();

  void _updatePostureFromData(
    Participant? participant,
    String decoded,
    String? topic,
  ) {
    if (participant == null) return;
    try {
      final data = jsonDecode(decoded);
      if (data is! Map) return;
      final posture = RemotePosture.tryParse(Map<String, dynamic>.from(data));
      if (posture == null) return;
      _remotePostures[participant.identity] = posture;
      _sortParticipants();
    } catch (error) {
      debugPrint('?? Donn�e posture illisible: ');
    }
  }

  RemotePosture? _postureForParticipant(Participant participant) {
    return _remotePostures[participant.identity];
  }

  /*void _onE2EEStateEvent(TrackE2EEStateEvent e2eeState) {
    debugPrint('e2ee state: ');
  }*/

  void _sortParticipants() {
    final activeIdentities = <String>{
      if (widget.room.localParticipant != null)
        widget.room.localParticipant!.identity,
      ...widget.room.remoteParticipants.values.map((p) => p.identity),
    };
    _remotePostures.removeWhere(
      (identity, _) => !activeIdentities.contains(identity),
    );

    final userMediaTracks = <ParticipantTrack>[];
    final screenTracks = <ParticipantTrack>[];

    for (var participant in widget.room.remoteParticipants.values) {
      for (var t in participant.videoTrackPublications) {
        if (t.isScreenShare) {
          screenTracks.add(
            ParticipantTrack(
              participant: participant,
              type: ParticipantTrackType.kScreenShare,
            ),
          );
        } else {
          userMediaTracks.add(
            ParticipantTrack(
              participant: participant,
              posture: _postureForParticipant(participant),
            ),
          );
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

    final localTracks = widget.room.localParticipant?.videoTrackPublications;
    if (localTracks != null) {
      for (var t in localTracks) {
        if (t.isScreenShare) {
          screenTracks.add(
            ParticipantTrack(
              participant: widget.room.localParticipant!,
              type: ParticipantTrackType.kScreenShare,
            ),
          );
        } else {
          debugPrint(
            '?? _sortParticipants: adding local avatarOnly track with pose=${_currentLocalPose != null} frameSize=$_currentLocalPoseFrameSize',
          );
          userMediaTracks.add(
            ParticipantTrack(
              participant: widget.room.localParticipant!,
              posture: _postureForParticipant(widget.room.localParticipant!),
              pose: _currentLocalPose,
              poseFrameSize: _currentLocalPoseFrameSize,
              avatarOnly: true, // HIDE LOCAL VIDEO
            ),
          );
        }
      }
    }
    setState(() {
      participantTracks = [...screenTracks, ...userMediaTracks];
    });
  }

  ParticipantTrack? _primaryParticipantTrack() {
    for (final track in participantTracks) {
      if (track.participant is LocalParticipant &&
          track.type == ParticipantTrackType.kUserMedia) {
        return track;
      }
    }
    return participantTracks.isNotEmpty ? participantTracks.first : null;
  }

  List<ParticipantTrack> _secondaryParticipantTracks(
    ParticipantTrack? primaryTrack,
  ) {
    if (primaryTrack == null) return participantTracks;
    return participantTracks.where((track) => track != primaryTrack).toList();
  }

  @override
  Widget build(BuildContext context) {
    final primaryTrack = _primaryParticipantTrack();
    final secondaryTracks = _secondaryParticipantTracks(primaryTrack);

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
                      ) : Container(),
              ),
              if (widget.room.localParticipant != null)
                SafeArea(
                  top: false,
                  child: ControlsWidget(
                    widget.room,
                    widget.room.localParticipant!,
                    bleService: _bleService,
                    onBleConnected: _onBleConnected,
                    onBleDisconnected: _onBleDisconnected,
                  ),
                ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 150,
            child: SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: secondaryTracks.length,
                itemBuilder: (BuildContext context, int index) => SizedBox(
                  width: 200,
                  height: 200,
                  child: ParticipantWidget.widgetFor(secondaryTracks[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
