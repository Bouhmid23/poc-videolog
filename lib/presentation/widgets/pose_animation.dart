import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

/// Structure pour interpoler entre deux poses
class InterpolatedPose {
  final Map<LandmarkType, Offset> points;
  final Map<LandmarkType, double> confidence;

  InterpolatedPose({
    required this.points,
    required this.confidence,
  });

  factory InterpolatedPose.fromPose(
    Pose pose,
    Size frameSize,
    Size displaySize, {
    required bool mirrorX,
  }) {
    final points = <LandmarkType, Offset>{};
    final confidence = <LandmarkType, double>{};

    // Calculer l'ajustement de la boîte englobante
    final fitted = applyBoxFit(BoxFit.contain, frameSize, displaySize);
    final sourceRect = Alignment.center.inscribe(fitted.source, Offset.zero & frameSize);
    final destinationRect = Alignment.center.inscribe(fitted.destination, Offset.zero & displaySize);

    for (final _landmark in pose.landmarks) {
      final landmark = _landmark;
      if (landmark.visibility < 0.2) continue;

      confidence[landmark.type] = landmark.visibility;

      // Some detectors return normalized coordinates (0..1), others return pixel coords.
      // Detect and convert normalized coords to pixel space when needed.
      double lx = landmark.x;
      double ly = landmark.y;
      final maybeNormalized = (lx.abs() <= 1.01 && ly.abs() <= 1.01);
      if (maybeNormalized) {
        lx = lx * frameSize.width;
        ly = ly * frameSize.height;
      }

      final x = mirrorX ? frameSize.width - lx : lx;
      final y = ly;

      final srcW = sourceRect.width == 0 ? 1.0 : sourceRect.width;
      final srcH = sourceRect.height == 0 ? 1.0 : sourceRect.height;
      final normalizedX = (x - sourceRect.left) / srcW;
      final normalizedY = (y - sourceRect.top) / srcH;

      points[landmark.type] = Offset(
        destinationRect.left + normalizedX * destinationRect.width,
        destinationRect.top + normalizedY * destinationRect.height,
      );
    }

    return InterpolatedPose(points: points, confidence: confidence);
  }

  /// Interpole entre deux poses avec un facteur (0.0 = première pose, 1.0 = deuxième pose)
  static InterpolatedPose lerp(
    InterpolatedPose a,
    InterpolatedPose b,
    double t,
  ) {
    final interpolatedPoints = <LandmarkType, Offset>{};
    final interpolatedConfidence = <LandmarkType, double>{};

    // Fusionner les clés de points existant dans les deux poses
    final allKeys = {...a.points.keys, ...b.points.keys};

    for (final key in allKeys) {
      final pointA = a.points[key];
      final pointB = b.points[key];
      final confA = a.confidence[key] ?? 0.0;
      final confB = b.confidence[key] ?? 0.0;

      if (pointA != null && pointB != null) {
        // Interpoler le point
        interpolatedPoints[key] = Offset.lerp(pointA, pointB, t)!;
        // Interpoler la confiance
        interpolatedConfidence[key] = (confA * (1 - t)) + (confB * t);
      } else if (pointA != null) {
        interpolatedPoints[key] = pointA;
        interpolatedConfidence[key] = confA * (1 - t);
      } else if (pointB != null) {
        interpolatedPoints[key] = pointB;
        interpolatedConfidence[key] = confB * t;
      }
    }

    return InterpolatedPose(
      points: interpolatedPoints,
      confidence: interpolatedConfidence,
    );
  }
}

/// Contrôleur d'animation pour les poses
class PoseAnimationController extends ChangeNotifier {
  InterpolatedPose? _currentPose;
  InterpolatedPose? _targetPose;
  late AnimationController _controller;
  final Duration transitionDuration;

  InterpolatedPose? get currentPose => _currentPose;

  PoseAnimationController({
    this.transitionDuration = const Duration(milliseconds: 100),
  }) {
    _controller = AnimationController(
        duration: transitionDuration,
        vsync: AnimatedGridState()
    );
    _controller.addListener(_onAnimationUpdate);
  }

  void _onAnimationUpdate() {
    if (_currentPose != null && _targetPose != null) {
      _currentPose = InterpolatedPose.lerp(
        _currentPose!,
        _targetPose!,
        _controller.value,
      );
      notifyListeners();
    }
  }

  void updatePose(InterpolatedPose newPose) {
    _currentPose ??= newPose;
    _targetPose = newPose;

    _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Palette de couleurs basée sur la confiance
class ConfidenceColorPalette {
  static Color getColor(double confidence) {
    if (confidence > 0.8) {
      return Colors.cyan; // Très confiant
    } else if (confidence > 0.6) {
      return Colors.lightGreen; // Confiant
    } else if (confidence > 0.4) {
      return Colors.yellow; // Modéré
    } else {
      return Colors.orange; // Faible confiance
    }
  }

  static Color getJointColor(double confidence) {
    if (confidence > 0.8) {
      return Colors.cyanAccent;
    } else if (confidence > 0.6) {
      return Colors.lightGreenAccent;
    } else if (confidence > 0.4) {
      return Colors.yellowAccent;
    } else {
      return Colors.orangeAccent;
    }
  }
}

/// Structure définissant les connexions du squelette humain
class SkeletonBone {
  final LandmarkType from;
  final LandmarkType to;
  final String name;

  const SkeletonBone({
    required this.from,
    required this.to,
    required this.name,
  });
}

/// Ensemble standard de connexions squelettiques humaines
class HumanSkeletonBones {
  static const List<SkeletonBone> standardBones = [
    // Colonne vertébrale
    SkeletonBone(from: LandmarkType.leftShoulder, to: LandmarkType.rightShoulder, name: 'Shoulders'),
    SkeletonBone(from: LandmarkType.leftShoulder, to: LandmarkType.leftHip, name: 'Left Torso'),
    SkeletonBone(from: LandmarkType.rightShoulder, to: LandmarkType.rightHip, name: 'Right Torso'),
    SkeletonBone(from: LandmarkType.leftHip, to: LandmarkType.rightHip, name: 'Hips'),

    // Bras gauche
    SkeletonBone(from: LandmarkType.leftShoulder, to: LandmarkType.leftElbow, name: 'Left Upper Arm'),
    SkeletonBone(from: LandmarkType.leftElbow, to: LandmarkType.leftWrist, name: 'Left Forearm'),

    // Bras droit
    SkeletonBone(from: LandmarkType.rightShoulder, to: LandmarkType.rightElbow, name: 'Right Upper Arm'),
    SkeletonBone(from: LandmarkType.rightElbow, to: LandmarkType.rightWrist, name: 'Right Forearm'),

    // Jambe gauche
    SkeletonBone(from: LandmarkType.leftHip, to: LandmarkType.leftKnee, name: 'Left Thigh'),
    SkeletonBone(from: LandmarkType.leftKnee, to: LandmarkType.leftAnkle, name: 'Left Calf'),

    // Jambe droite
    SkeletonBone(from: LandmarkType.rightHip, to: LandmarkType.rightKnee, name: 'Right Thigh'),
    SkeletonBone(from: LandmarkType.rightKnee, to: LandmarkType.rightAnkle, name: 'Right Ankle'),
  ];
}
