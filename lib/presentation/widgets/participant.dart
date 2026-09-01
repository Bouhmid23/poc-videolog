import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:livekit_client/livekit_client.dart';
import 'dart:async';
import '../../data/remote_posture.dart';
import '../../data/remote_telemetry.dart';
import '../../theme.dart';
import 'no_video.dart';
import 'participant_info.dart';
import 'pose_animation.dart';

abstract class ParticipantWidget extends StatefulWidget {
  static ParticipantWidget widgetFor(
    ParticipantTrack participantTrack, {
    bool showStatsLayer = false,
  }) {
    if (participantTrack.participant is LocalParticipant) {
      return LocalParticipantWidget(
        participantTrack.participant as LocalParticipant,
        participantTrack.type,
        showStatsLayer,
        posture: participantTrack.posture,
        telemetry: participantTrack.telemetry,
        pose: participantTrack.pose,
        poseFrameSize: participantTrack.poseFrameSize,
        avatarOnly: participantTrack.avatarOnly,
        showPosePip: participantTrack.showPosePip,
      );
    } else if (participantTrack.participant is RemoteParticipant) {
      return RemoteParticipantWidget(
        participantTrack.participant as RemoteParticipant,
        participantTrack.type,
        showStatsLayer,
        posture: participantTrack.posture,
        telemetry: participantTrack.telemetry,
        pose: participantTrack.pose,
        poseFrameSize: participantTrack.poseFrameSize,
        avatarOnly: participantTrack.avatarOnly,
        showPosePip: participantTrack.showPosePip,
      );
    }
    throw UnimplementedError('Unknown participant type');
  }

  abstract final Participant participant;
  abstract final ParticipantTrackType type;
  abstract final bool showStatsLayer;
  final RemotePosture? posture;
  final RemoteTelemetry? telemetry;
  final Pose? pose;
  final Size? poseFrameSize;
  final bool avatarOnly;
  final bool showPosePip;
  final VideoQuality quality;

  const ParticipantWidget({
    this.posture,
    this.telemetry,
    this.pose,
    this.poseFrameSize,
    this.avatarOnly = false,
    this.showPosePip = true,
    this.quality = VideoQuality.HIGH,
    super.key,
  });
}

class LocalParticipantWidget extends ParticipantWidget {
  @override
  final LocalParticipant participant;
  @override
  final ParticipantTrackType type;
  @override
  final bool showStatsLayer;

  const LocalParticipantWidget(
    this.participant,
    this.type,
    this.showStatsLayer, {
    super.posture,
    super.telemetry,
    super.pose,
    super.poseFrameSize,
    super.avatarOnly,
    super.showPosePip,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _LocalParticipantWidgetState();
}

class RemoteParticipantWidget extends ParticipantWidget {
  @override
  final RemoteParticipant participant;
  @override
  final ParticipantTrackType type;
  @override
  final bool showStatsLayer;

  const RemoteParticipantWidget(
    this.participant,
    this.type,
    this.showStatsLayer, {
    super.posture,
    super.telemetry,
    super.pose,
    super.poseFrameSize,
    super.avatarOnly,
    super.showPosePip,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RemoteParticipantWidgetState();
}

abstract class _ParticipantWidgetState<T extends ParticipantWidget>
    extends State<T> {
  bool _visible = true;
  VideoTrack? get activeVideoTrack;
  AudioTrack? get activeAudioTrack;
  TrackPublication? get videoPublication;
  TrackPublication? get audioPublication;
  bool get isScreenShare => widget.type == ParticipantTrackType.kScreenShare;
  EventsListener<ParticipantEvent>? _listener;

  // Support 3D : On exclut le web pour o3d (ou on d�tecte le support mat�riel)
  //bool get _is3DSupported => !kIsWeb && (lkPlatformIs(PlatformType.android) || lkPlatformIs(PlatformType.iOS));

  @override
  void initState() {
    super.initState();
    _listener = widget.participant.createListener();
    widget.participant.addListener(_onParticipantChanged);
    _onParticipantChanged();
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    unawaited(_listener?.dispose());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    oldWidget.participant.removeListener(_onParticipantChanged);
    widget.participant.addListener(_onParticipantChanged);
    _onParticipantChanged();
    super.didUpdateWidget(oldWidget);
  }

  void _onParticipantChanged() => setState(() {});

  List<Widget> extraWidgets(bool isScreenShare) => [];

  @override
  Widget build(BuildContext ctx) => Container(
    foregroundDecoration: BoxDecoration(
      border: widget.participant.isSpeaking && !isScreenShare
          ? Border.all(width: 3, color: LKColors.lkBlue)
          : null,
      borderRadius: BorderRadius.circular(12),
    ),
    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        // 1. FLUX VIDEO PRINCIPAL (Toujours en fond)
        InkWell(
          onTap: () => setState(() => _visible = !_visible),
          child: activeVideoTrack != null && !activeVideoTrack!.muted
              ? VideoTrackRenderer(
                  renderMode: VideoRenderMode.auto,
                  activeVideoTrack!,
                  fit: VideoViewFit.cover,
                )
              : const NoVideoWidget(),
        ),

        // 2. PIP AVATAR (Bas � Droite, au-dessus de la barre d'infos)
        if (widget.pose != null &&
            widget.poseFrameSize != null &&
            widget.showPosePip &&
            !isScreenShare)
          Positioned(
            bottom: 45,
            right: 15,
            child: Container(
              width: 120,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: /*_is3DSupported
                  ? ThreeDAvatarWidget(
                      modelUrl: 'https://modelviewer.dev/shared-assets/models/Astronaut.glb',
                      pose: widget.pose,
                      label: widget.posture?.label,
                    )
                  : */CustomPaint(
                      painter: _PoseAvatarPainter(
                        pose: widget.pose!,
                        frameSize: widget.poseFrameSize!,
                        mirrorX: widget.participant is LocalParticipant,
                        isMiniature: true,
                      ),
                    ),
              ),
            ),
          ),

        /*// 3. Posture d�tect�e (Badge en haut � gauche)
        if (widget.posture != null && !isScreenShare)
          Positioned(
            top: 10,
            left: 10,
            child: _RemotePostureBadge(posture: widget.posture!),
          ),

        // 4. Barre d'infos (Bas)*/
        // Badge t�l�m�trie (haut gauche) : toutes les infos non null
        if ((widget.telemetry != null || widget.posture != null) && !isScreenShare)
          Positioned(
            top: 30,
            left: 10,
            child: TelemetryBadge(
              telemetry: widget.telemetry,
              posture: widget.posture,
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              //...extraWidgets(isScreenShare),
              ParticipantInfoWidget(
                title: widget.participant.name.isNotEmpty
                    ? widget.participant.name
                    : widget.participant.identity,
                audioAvailable: audioPublication?.muted == false && audioPublication?.subscribed == true,
                connectionQuality: widget.participant.connectionQuality,
                isScreenShare: isScreenShare,
                enabledE2EE: widget.participant.isEncrypted,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PoseAvatarPainter extends CustomPainter {
  final Pose pose;
  final Size frameSize;
  final bool mirrorX;
  final bool isMiniature;
  final bool enableSmoothing;
  final bool enableColorByConfidence;
  final bool enableBoneThickness;

  _PoseAvatarPainter({
    required this.pose,
    required this.frameSize,
    required this.mirrorX,
    this.isMiniature = false,
  }) : enableBoneThickness = true, enableColorByConfidence = true, enableSmoothing = true;

  @override
  void paint(Canvas canvas, Size size) {
    final interpolated = InterpolatedPose.fromPose(pose, frameSize, size, mirrorX: mirrorX);
    final points = interpolated.points;
    final confidence = interpolated.confidence;

    _drawTorso(canvas, points, confidence);   // 1. fond d'abord
    for (final bone in HumanSkeletonBones.standardBones) {
      _drawBone(canvas, points, confidence, bone.from, bone.to);
    }
    _drawHead(canvas, points, confidence);    // 2. par-dessus les os
    _drawJoints(canvas, points, confidence);  // 3. joints au premier plan
    if (!isMiniature) {
      _drawConfidenceIndicators(canvas, points, confidence);
    }
  }

  void _drawHead(Canvas canvas, Map<LandmarkType, Offset> points,
      Map<LandmarkType, double> confidence) {
    final nose = points[LandmarkType.nose];
    final leftEar = points[LandmarkType.leftEar];
    final rightEar = points[LandmarkType.rightEar];
    if (nose == null) return;

    final conf = confidence[LandmarkType.nose] ?? 0.5;
    final radius = isMiniature ? 10.0 : 20.0;

    // Cercle de tête basé sur le nez + largeur des oreilles
    double headRadius = radius;
    if (leftEar != null && rightEar != null) {
      headRadius = (leftEar - rightEar).distance / 2.0;
      headRadius = headRadius.clamp(radius * 0.7, radius * 1.5);
    }
    final headCenter = Offset(nose.dx, nose.dy - headRadius * 0.6);

    canvas.drawCircle(headCenter, headRadius,
        Paint()
          ..color = ConfidenceColorPalette.getColor(conf).withValues(alpha: 0.25)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(headCenter, headRadius,
        Paint()
          ..color = ConfidenceColorPalette.getColor(conf)
          ..strokeWidth = isMiniature ? 1.5 : 2.5
          ..style = PaintingStyle.stroke);
  }

  void _drawTorso(Canvas canvas, Map<LandmarkType, Offset> points,
      Map<LandmarkType, double> confidence) {
    final ls = points[LandmarkType.leftShoulder];
    final rs = points[LandmarkType.rightShoulder];
    final lh = points[LandmarkType.leftHip];
    final rh = points[LandmarkType.rightHip];
    if (ls == null || rs == null || lh == null || rh == null) return;

    final avgConf = [ls, rs, lh, rh].map((p) {
      final type = points.entries.firstWhere((e) => e.value == p).key;
      return confidence[type] ?? 0.0;
    }).reduce((a, b) => a + b) / 4;

    final path = Path()
      ..moveTo(ls.dx, ls.dy)
      ..lineTo(rs.dx, rs.dy)
      ..lineTo(rh.dx, rh.dy)
      ..lineTo(lh.dx, lh.dy)
      ..close();

    canvas.drawPath(path, Paint()
      ..color = ConfidenceColorPalette.getColor(avgConf).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill);
  }

  // Dans _drawBone, remplacer canvas.drawLine par :
  void _drawBoneCurved(Canvas canvas, Offset from, Offset to, Paint paint) {
    // Point de contrôle légèrement décalé perpendiculairement
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final perp = Offset(-(to.dy - from.dy), to.dx - from.dx);
    final perpLen = perp.distance.clamp(1.0, double.infinity);
    final ctrl = mid + (perp / perpLen) * 8.0; // courbure de 8px

    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy);
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
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
    _drawBoneCurved(canvas,fromPoint, toPoint, paint);

    // Ajouter un effet de lueur pour les high-confidence bones
    if (!isMiniature && avgConf > 0.5) {
      paint.shader = ui.Gradient.linear(
        fromPoint, toPoint,
        [ConfidenceColorPalette.getColor(fromConf),
          ConfidenceColorPalette.getColor(toConf)],
      );
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

      // Coordonnée Z pour simuler la profondeur (négatif = vers caméra)
      final z = pose.getLandmark(entry.key).z;
      final depthFactor = (1.0 - (z.clamp(-0.5, 0.5) + 0.5)).clamp(0.5, 1.0);

      // Taille modulée par confiance ET profondeur Z
      final baseRadius = isMiniature ? 2.0 : 4.0;
      final radius = (baseRadius + (conf * baseRadius)) * depthFactor;

      // Opacité modulée par la profondeur
      final alpha = (0.5 + conf * 0.5) * depthFactor;

      final color = enableColorByConfidence
          ? ConfidenceColorPalette.getJointColor(conf)
          : Colors.white;

      // Articulation principale
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = color.withValues(alpha: alpha),
      );

      // Halo (seulement si confiance suffisante et pas miniature)
      if (conf > 0.6 && !isMiniature) {
        canvas.drawCircle(
          point,
          radius * 1.4,
          Paint()
            ..color = color.withValues(alpha: 0.18 * depthFactor)
            ..strokeWidth = 0.8
            ..style = PaintingStyle.stroke,
        );
      }

      // Second halo pour les joints très proches de la caméra (z très négatif)
      if (z < -0.2 && conf > 0.7 && !isMiniature) {
        canvas.drawCircle(
          point,
          radius * 1.9,
          Paint()
            ..color = color.withValues(alpha: 0.08)
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
  bool shouldRepaint(covariant _PoseAvatarPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.frameSize != frameSize ||
      oldDelegate.mirrorX != mirrorX ||
      oldDelegate.isMiniature != isMiniature;
}

class _LocalParticipantWidgetState extends _ParticipantWidgetState<LocalParticipantWidget> {
  @override
  LocalTrackPublication<LocalVideoTrack>? get videoPublication => widget.participant.videoTrackPublications.where((e) => e.source == widget.type.lkVideoSourceType).firstOrNull;
  @override
  LocalTrackPublication<LocalAudioTrack>? get audioPublication => widget.participant.audioTrackPublications.where((e) => e.source == widget.type.lkAudioSourceType).firstOrNull;
  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;
  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;
}

class _RemoteParticipantWidgetState extends _ParticipantWidgetState<RemoteParticipantWidget> {
  @override
  RemoteTrackPublication<RemoteVideoTrack>? get videoPublication => widget.participant.videoTrackPublications.where((e) => e.source == widget.type.lkVideoSourceType).firstOrNull;
  @override
  RemoteTrackPublication<RemoteAudioTrack>? get audioPublication => widget.participant.audioTrackPublications.where((e) => e.source == widget.type.lkAudioSourceType).firstOrNull;
  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;
  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;

  @override
  List<Widget> extraWidgets(bool isScreenShare) => [
    Row(mainAxisSize: MainAxisSize.max, mainAxisAlignment: MainAxisAlignment.end, children: [
      if (audioPublication != null) RemoteTrackPublicationMenuWidget(pub: audioPublication!, icon: Icons.volume_up),
      if (videoPublication != null) RemoteTrackPublicationMenuWidget(pub: videoPublication!, icon: isScreenShare ? Icons.monitor : Icons.videocam),
      if (videoPublication != null) RemoteTrackFPSMenuWidget(pub: videoPublication!, icon: Icons.menu),
      if (videoPublication != null) RemoteTrackQualityMenuWidget(pub: videoPublication!, icon: Icons.monitor_outlined),
    ]),
  ];
}

class RemoteTrackPublicationMenuWidget extends StatelessWidget {
  final IconData icon; final RemoteTrackPublication pub;
  const RemoteTrackPublicationMenuWidget({required this.pub, required this.icon, super.key});
  @override
  Widget build(BuildContext context) => Material(color: Colors.black.withValues(alpha: 0.3), child: PopupMenuButton<Function>(icon: Icon(icon, color: Colors.white), onSelected: (value) => value(), itemBuilder: (ctx) => [
    if (pub.subscribed == false) PopupMenuItem(child: const Text('Subscribe'), value: () => pub.subscribe()) else if (pub.subscribed == true) PopupMenuItem(child: const Text('Un-subscribe'), value: () => pub.unsubscribe()),
  ]));
}

class RemoteTrackFPSMenuWidget extends StatelessWidget {
  final IconData icon; final RemoteTrackPublication pub;
  const RemoteTrackFPSMenuWidget({required this.pub, required this.icon, super.key});
  @override
  Widget build(BuildContext context) => Material(color: Colors.black.withValues(alpha: 0.3), child: PopupMenuButton<Function>(icon: Icon(icon, color: Colors.white), onSelected: (value) => value(), itemBuilder: (ctx) => [
    PopupMenuItem(child: const Text('30'), value: () => pub.setVideoFPS(30)),
    PopupMenuItem(child: const Text('15'), value: () => pub.setVideoFPS(15)),
    PopupMenuItem(child: const Text('8'), value: () => pub.setVideoFPS(8)),
  ]));
}

class RemoteTrackQualityMenuWidget extends StatelessWidget {
  final IconData icon; final RemoteTrackPublication pub;
  const RemoteTrackQualityMenuWidget({required this.pub, required this.icon, super.key});
  @override
  Widget build(BuildContext context) => Material(color: Colors.black.withValues(alpha: 0.3), child: PopupMenuButton<Function>(icon: Icon(icon, color: Colors.white), onSelected: (value) => value(), itemBuilder: (ctx) => [
    PopupMenuItem(child: const Text('HIGH'), value: () => pub.setVideoQuality(VideoQuality.HIGH)),
    PopupMenuItem(child: const Text('MEDIUM'), value: () => pub.setVideoQuality(VideoQuality.MEDIUM)),
    PopupMenuItem(child: const Text('LOW'), value: () => pub.setVideoQuality(VideoQuality.LOW)),
  ]));
}
