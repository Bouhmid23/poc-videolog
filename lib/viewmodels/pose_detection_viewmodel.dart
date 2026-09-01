import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/posture_detection_service.dart';
import '../data/remote_posture.dart';

class LocalPoseAnalysis {
  const LocalPoseAnalysis({
    required this.pose,
    required this.frameSize,
    required this.posture,
  });

  final Pose pose;
  final Size frameSize;
  final RemotePosture? posture;
}

class PoseDetectionViewModel extends ChangeNotifier {
  final NpuPoseDetector _poseDetector = NpuPoseDetector(
    config: PoseDetectorConfig.realtime(),
  );
  final PostureSmoothing _postureSmoothing = PostureSmoothing(alpha: 0.35);

  Timer? _poseTimer;
  bool _busy = false;
  Pose? _currentPose;
  Size? _currentFrameSize;
  Room? _room;

  Pose? get currentPose => _currentPose;
  Size? get currentFrameSize => _currentFrameSize;
  bool get isBusy => _busy;

  Future<void> init() async {
    await _poseDetector.initialize();
  }

  void start(Room room) {
    _room = room;
    _poseTimer ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(_detectPoseTick()),
    );
    debugPrint('🏃 Pose detection started (10 Hz)');
  }

  void stop() {
    _poseTimer?.cancel();
    _poseTimer = null;
    _busy = false;
    _currentPose = null;
    _currentFrameSize = null;
  }

  Future<void> _detectPoseTick() async {
    if (_busy || kIsWeb) return;

    final room = _room;
    final localParticipant = room?.localParticipant;
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

    _busy = true;
    try {
      final analysis = await _detectPoseFromTrack(cameraTrack);
      if (analysis == null) {
        _currentPose = null;
        _currentFrameSize = null;
        notifyListeners();
        return;
      }

      _currentPose = _postureSmoothing.smooth(analysis.pose);
      _currentFrameSize = analysis.frameSize;
      notifyListeners();
    } catch (error) {
      debugPrint('⚠️ Pose detection error: $error');
    } finally {
      _busy = false;
    }
  }

  Future<LocalPoseAnalysis?> _detectPoseFromTrack(
    LocalVideoTrack track,
  ) async {
    try {
      final buffer = await track.mediaStreamTrack.captureFrame();
      final bytes = Uint8List.view(buffer);

      final result = await _poseDetector.detectPose(bytes);
      if (!result.hasPoses) return null;

      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frameInfo = await codec.getNextFrame();
        final frameSize = Size(
          frameInfo.image.width.toDouble(),
          frameInfo.image.height.toDouble(),
        );
        frameInfo.image.dispose();

        final pose = result.firstPose!;
        return LocalPoseAnalysis(
          pose: pose,
          frameSize: frameSize,
          posture: classifyPosture(pose),
        );
      } finally {
        codec.dispose();
      }
    } catch (error) {
      debugPrint('⚠️ Pose capture/detect failed: $error');
      return null;
    }
  }

  RemotePosture? classifyPosture(Pose pose) {
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
    final kneeDrop =
        kneeMid == null ? 0.0 : (kneeMid.dy - hipMid.dy) / torsoLength;
    final ankleDrop =
        ankleMid == null ? 0.0 : (ankleMid.dy - hipMid.dy) / torsoLength;

    final confidence = averageLikelihood([
      landmark(LandmarkType.leftShoulder),
      landmark(LandmarkType.rightShoulder),
      landmark(LandmarkType.leftHip),
      landmark(LandmarkType.rightHip),
    ]);

    final label = torsoAngleDeg > 48
        ? 'allong\u00e9'
        : (kneeDrop < 0.35 && ankleDrop < 0.7 ? 'assis' : 'debout');

    return RemotePosture(
      label: label,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      receivedAt: DateTime.now(),
    );
  }

  static Map<String, dynamic> buildPosturePayload(RemotePosture posture) {
    return {
      'type': 'posture',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'payload': {
        'posture': posture.label,
        'label': posture.label,
        if (posture.confidence != null) 'confidence': posture.confidence,
        'source': 'mlkit',
      },
    };
  }

  Future<void> publishPosture(
    LocalParticipant participant,
    RemotePosture posture,
  ) async {
    final payload = buildPosturePayload(posture);
    try {
      await participant.publishData(
        utf8.encode(jsonEncode(payload)),
        reliable: true,
        topic: 'posture',
      );
    } catch (error) {
      debugPrint('⚠️ Failed to publish posture: $error');
    }
  }

  @override
  Future<void> dispose() async {
    stop();
    _poseDetector.dispose();
    super.dispose();
  }
}
