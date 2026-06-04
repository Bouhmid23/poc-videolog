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
    this.connectionQuality = ConnectionQuality.unknown,
    this.isScreenShare = false,
    this.enabledE2EE = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black.withValues(alpha: 0.3),
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (title != null)
          Flexible(child: Text(title!, overflow: TextOverflow.ellipsis)),
        isScreenShare
            ? const Padding(
                padding: EdgeInsets.only(left: 5),
                child: Icon(Icons.monitor, color: Colors.white, size: 16),
              )
            : Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Icon(
                  audioAvailable ? Icons.mic : Icons.mic_off,
                  color: audioAvailable ? Colors.white : Colors.red,
                  size: 16,
                ),
              ),
        if (connectionQuality != ConnectionQuality.unknown)
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Icon(
              connectionQuality == ConnectionQuality.poor
                  ? Icons.wifi_off_outlined
                  : Icons.wifi,
              color: {
                ConnectionQuality.excellent: Colors.green,
                ConnectionQuality.good: Colors.orange,
                ConnectionQuality.poor: Colors.red,
              }[connectionQuality],
              size: 16,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Icon(
            enabledE2EE ? Icons.lock : Icons.lock_open,
            color: enabledE2EE ? Colors.green : Colors.red,
            size: 16,
          ),
        ),
      ],
    ),
  );
}
