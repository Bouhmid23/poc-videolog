import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../data/remote_posture.dart';

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
    this.pose,
    this.poseFrameSize,
    this.avatarOnly = false,
  });
  Participant participant;
  final ParticipantTrackType type;
  final RemotePosture? posture;
  final Pose? pose;
  final Size? poseFrameSize;
  final bool avatarOnly;
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
