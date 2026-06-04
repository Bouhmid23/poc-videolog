import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'pose_animation.dart';

/// Widget que expose le painter avec animations fluides
class SmoothedPoseAvatarWidget extends StatefulWidget {
  final Pose? pose;
  final Size frameSize;
  final bool mirrorX;
  final bool isMiniature;
  final Duration animationDuration;
  final bool enableColorByConfidence;
  final bool enableBoneThickness;

  const SmoothedPoseAvatarWidget({
    required this.pose,
    required this.frameSize,
    required this.mirrorX,
    this.isMiniature = false,
    this.animationDuration = const Duration(milliseconds: 100),
    this.enableColorByConfidence = true,
    this.enableBoneThickness = true,
    super.key,
  });

  @override
  State<SmoothedPoseAvatarWidget> createState() => _SmoothedPoseAvatarWidgetState();
}

class _SmoothedPoseAvatarWidgetState extends State<SmoothedPoseAvatarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  InterpolatedPose? _currentPose;
  InterpolatedPose? _targetPose;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _animationController.addListener(_onAnimationUpdate);

    if (widget.pose != null) {
      _initializePose(widget.pose!);
    }
  }

  void _initializePose(Pose pose) {
    final interpolated = InterpolatedPose.fromPose(
      pose,
      widget.frameSize,
      Size.infinite, // Sera recalculé lors du paint
      mirrorX: widget.mirrorX,
    );

    if (_currentPose == null) {
      _currentPose = interpolated;
    } else {
      _targetPose = interpolated;
      _animationController.forward(from: 0.0);
    }
  }

  void _onAnimationUpdate() {
    if (_currentPose != null && _targetPose != null) {
      setState(() {
        _currentPose = InterpolatedPose.lerp(
          _currentPose!,
          _targetPose!,
          _animationController.value,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant SmoothedPoseAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.pose != null && widget.pose != oldWidget.pose) {
      _initializePose(widget.pose!);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPose == null) {
      return const SizedBox.expand(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return CustomPaint(
      painter: _SmoothedPoseAvatarPainter(
        pose: _currentPose!,
        mirrorX: widget.mirrorX,
        isMiniature: widget.isMiniature,
        enableColorByConfidence: widget.enableColorByConfidence,
        enableBoneThickness: widget.enableBoneThickness,
      ),
      child: Container(),
    );
  }
}

/// Painter pour le widget avec animation fluide
class _SmoothedPoseAvatarPainter extends CustomPainter {
  final InterpolatedPose pose;
  final bool mirrorX;
  final bool isMiniature;
  final bool enableColorByConfidence;
  final bool enableBoneThickness;

  _SmoothedPoseAvatarPainter({
    required this.pose,
    required this.mirrorX,
    this.isMiniature = false,
    this.enableColorByConfidence = true,
    this.enableBoneThickness = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final points = pose.points;
    final confidence = pose.confidence;

    // Dessiner les os du squelette
    for (final bone in HumanSkeletonBones.standardBones) {
      _drawBone(
        canvas,
        points,
        confidence,
        bone.from,
        bone.to,
      );
    }

    // Dessiner les articulations avec effet de profondeur
    _drawJoints(canvas, points, confidence);

    // Optionnel : Afficher les lignes de confiance faible comme pointillées
    if (!isMiniature) {
      _drawConfidenceIndicators(canvas, points, confidence);
    }
  }

  void _drawBone(
    Canvas canvas,
    Map<LandmarkType, Offset> points,
    Map<LandmarkType, double> confidence,
    LandmarkType from,
    LandmarkType to,
  ) {
    if (!points.containsKey(from) || !points.containsKey(to)) return;

    final fromPoint = points[from]!;
    final toPoint = points[to]!;
    final fromConf = confidence[from] ?? 0.0;
    final toConf = confidence[to] ?? 0.0;
    final avgConf = (fromConf + toConf) / 2;

    // Couleur basée sur la confiance
    final color = enableColorByConfidence
        ? ConfidenceColorPalette.getColor(avgConf)
        : Colors.cyanAccent;

    // Épaisseur basée sur la confiance
    double strokeWidth;
    if (enableBoneThickness) {
      strokeWidth = isMiniature ? 1 + (avgConf * 1.5) : 2 + (avgConf * 3);
    } else {
      strokeWidth = isMiniature ? 2 : 4;
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Dessiner le trait principal
    canvas.drawLine(fromPoint, toPoint, paint);

    // Ajouter un effet de lueur pour les high-confidence bones
    if (avgConf > 0.7 && !isMiniature) {
      paint
        ..color = color.withValues(alpha: 0.3)
        ..strokeWidth = strokeWidth * 2;
      canvas.drawLine(fromPoint, toPoint, paint);
    }
  }

  void _drawJoints(
    Canvas canvas,
    Map<LandmarkType, Offset> points,
    Map<LandmarkType, double> confidence,
  ) {
    for (final entry in points.entries) {
      final point = entry.value;
      final conf = confidence[entry.key] ?? 0.0;

      // Taille de l'articulation basée sur la confiance
      final baseRadius = isMiniature ? 2.0 : 4.0;
      final radius = baseRadius + (conf * baseRadius);

      // Couleur de l'articulation
      final color = enableColorByConfidence
          ? ConfidenceColorPalette.getJointColor(conf)
          : Colors.white;

      // Articulation principale
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = color,
      );

      // Halo de profondeur pour les articulations confiant
      if (conf > 0.6) {
        canvas.drawCircle(
          point,
          radius * 1.3,
          Paint()
            ..color = color.withValues(alpha: 0.2)
            ..strokeWidth = 0.5
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  void _drawConfidenceIndicators(
    Canvas canvas,
    Map<LandmarkType, Offset> points,
    Map<LandmarkType, double> confidence,
  ) {
    for (final bone in HumanSkeletonBones.standardBones) {
      if (!points.containsKey(bone.from) || !points.containsKey(bone.to)) continue;

      final fromConf = confidence[bone.from] ?? 0.0;
      final toConf = confidence[bone.to] ?? 0.0;
      final avgConf = (fromConf + toConf) / 2;

      // Pour les basses confiances, utiliser un style pointillé
      if (avgConf < 0.5) {
        _drawDashedLine(
          canvas,
          points[bone.from]!,
          points[bone.to]!,
          Paint()
            ..color = Colors.red.withValues(alpha: 0.5)
            ..strokeWidth = isMiniature ? 1 : 2
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 3.0;
    final distance = (p2 - p1).distance;
    final steps = (distance / (dashWidth + dashSpace)).ceil();

    for (int i = 0; i < steps; i++) {
      final t1 = (i * (dashWidth + dashSpace)) / distance;
      final t2 = (i * (dashWidth + dashSpace) + dashWidth) / distance;

      if (t2 <= 1.0) {
        canvas.drawLine(
          Offset.lerp(p1, p2, t1)!,
          Offset.lerp(p1, p2, t2.clamp(0, 1))!,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SmoothedPoseAvatarPainter oldDelegate) => true;
}
