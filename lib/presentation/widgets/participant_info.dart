import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../data/remote_posture.dart';
import '../../data/remote_telemetry.dart';

enum ParticipantTrackType { kUserMedia, kScreenShare }

extension ParticipantTrackTypeExt on ParticipantTrackType {
  TrackSource get lkVideoSourceType => {
    ParticipantTrackType.kUserMedia: TrackSource.camera,
    ParticipantTrackType.kScreenShare: TrackSource.screenShareVideo,
  }[this]!;

  TrackSource get lkAudioSourceType => {
    ParticipantTrackType.kUserMedia: TrackSource.microphone,
    ParticipantTrackType.kScreenShare: TrackSource.screenShareAudio,
  }[this]!;
}

class ParticipantTrack {
  ParticipantTrack({
    required this.participant,
    this.type = ParticipantTrackType.kUserMedia,
    this.posture,
    this.telemetry,
    this.pose,
    this.poseFrameSize,
    this.avatarOnly = false,
    this.showPosePip = true,
  });
  Participant participant;
  final ParticipantTrackType type;
  final RemotePosture? posture;
  final RemoteTelemetry? telemetry;
  final Pose? pose;
  final Size? poseFrameSize;
  final bool avatarOnly;
  final bool showPosePip;
}

class ParticipantInfoWidget extends StatelessWidget {
  final String? title;
  final bool audioAvailable;
  final ConnectionQuality connectionQuality;
  final bool isScreenShare;
  final bool enabledE2EE;

  const ParticipantInfoWidget({
    this.title,
    this.audioAvailable = true,
    this.connectionQuality = ConnectionQuality.excellent,
    this.isScreenShare = false,
    this.enabledE2EE = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(10),
        topRight: Radius.circular(10),
      ),
    ),
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (title != null)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(title!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        //_icon(Icons.monitor, null, isScreenShare),
        _icon(
          audioAvailable ? Icons.mic : Icons.mic_off,
          audioAvailable ? null : Colors.red,
          !isScreenShare,
        ),
        /*if (connectionQuality != ConnectionQuality.unknown)
          _icon(
            connectionQuality == ConnectionQuality.poor
                ? Icons.wifi_off_outlined
                : Icons.wifi,
            {
              ConnectionQuality.excellent: Colors.green,
              ConnectionQuality.good: Colors.orange,
              ConnectionQuality.poor: Colors.red,
            }[connectionQuality],
            true,
          ),
        _icon(
          enabledE2EE ? Icons.lock : Icons.lock_open,
          enabledE2EE ? Colors.green : Colors.red,
          true,
        ),*/
      ],
    ),
  );

  Widget _icon(IconData icon, Color? color, bool show) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(icon, color: color ?? Colors.white, size: 20),
    );
  }
}

class TelemetryBadge extends StatelessWidget {
  final RemoteTelemetry? telemetry;
  final RemotePosture? posture;

  const TelemetryBadge({super.key, this.telemetry, this.posture});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    if (telemetry != null) {
      if (telemetry!.hasHrm) {
        items.add(_chip(
          icon: Icons.favorite,
          iconColor: Colors.redAccent,
          value: '${telemetry!.heartRate}',
          unit: 'BPM',
        ));
      }
      if (telemetry!.speed != null) {
        items.add(_chip(
          icon: Icons.speed,
          iconColor: Colors.amberAccent,
          value: telemetry!.speed!.toStringAsFixed(1),
          unit: 'km/h',
        ));
      }
      if (telemetry!.cadence != null) {
        items.add(_chip(
          icon: Icons.pedal_bike,
          iconColor: Colors.lightGreenAccent,
          value: telemetry!.cadence!.toStringAsFixed(0),
          unit: 'RPM',
        ));
      }
      /*if (telemetry!.lat != null) {
        items.add(_chip(
          icon: Icons.my_location,
          iconColor: Colors.lightBlueAccent,
          value: telemetry!.lat!.toStringAsFixed(5),
          unit: 'Lat',
        ));
      }
      if (telemetry!.lng != null) {
        items.add(_chip(
          icon: Icons.my_location,
          iconColor: Colors.lightBlueAccent,
          value: telemetry!.lng!.toStringAsFixed(5),
          unit: 'Lng',
        ));
      }*/
    }

    /*if (posture != null) {
      items.add(_chip(
        icon: Icons.accessibility_new,
        iconColor: Colors.cyanAccent,
        value: posture!.label,
        unit: null,
      ));
    }*/

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            items[i],
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required Color iconColor,
    required String value,
    String? unit,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 14),
        const SizedBox(width: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: 1),
          Text(unit, style: const TextStyle(color: Colors.white70, fontSize: 8)),
        ],
      ],
    );
  }
}
