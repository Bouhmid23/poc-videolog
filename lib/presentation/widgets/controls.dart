import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:livekit_client/livekit_client.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/ble_telemetry_service.dart';
import '../../exts.dart';


class ControlsWidget extends StatefulWidget {
  final Room room;
  final LocalParticipant participant;

  // ── Shared BLE state injected from RoomPage ──
  final BleTelemetryService bleService;
  final VoidCallback onBleConnected;
  final VoidCallback onBleDisconnected;

  const ControlsWidget(
      this.room,
      this.participant, {
        required this.bleService,
        required this.onBleConnected,
        required this.onBleDisconnected,
        super.key,
      });

  @override
  State<StatefulWidget> createState() => _ControlsWidgetState();
}

class _ControlsWidgetState extends State<ControlsWidget> {
  CameraPosition position = CameraPosition.front;

  List<MediaDevice>? _audioInputs;
  List<MediaDevice>? _audioOutputs;

  StreamSubscription? _subscription;

  bool _speakerphoneOn = Hardware.instance.speakerOn ?? false;

  // ── BLE scan state (local to controls sheet UI only) ──
  StreamSubscription<List<DiscoveredDevice>>? _bleScanSub;
  List<DiscoveredDevice> _bleDevices = const [];

  // Convenience getter — service lives in RoomPage
  BleTelemetryService get _bleService => widget.bleService;

  @override
  void initState() {
    super.initState();
    participant.addListener(_onChange);
    _subscription = Hardware.instance.onDeviceChange.stream
        .listen((List<MediaDevice> devices) {
      _loadDevices(devices);
    });
    unawaited(Hardware.instance.enumerateDevices().then(_loadDevices));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_bleScanSub?.cancel());
    // Do NOT dispose _bleService here — it is owned by RoomPage
    participant.removeListener(_onChange);
    super.dispose();
  }

  LocalParticipant get participant => widget.participant;

  void _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    setState(() {});
  }

  void _onChange() => setState(() {});

  bool get isMuted => participant.isMuted;

  void _disableAudio() async => participant.setMicrophoneEnabled(false);
  Future<void> _enableAudio() async => participant.setMicrophoneEnabled(true);
  void _disableVideo() async => participant.setCameraEnabled(false);
  void _enableVideo() async => participant.setCameraEnabled(true);

  void _selectAudioOutput(MediaDevice device) async {
    await widget.room.setAudioOutputDevice(device);
    setState(() {});
  }

  void _selectAudioInput(MediaDevice device) async {
    await widget.room.setAudioInputDevice(device);
    setState(() {});
  }

  void _setSpeakerphoneOn() async {
    _speakerphoneOn = !_speakerphoneOn;
    await widget.room.setSpeakerOn(_speakerphoneOn, forceSpeakerOutput: false);
    setState(() {});
  }

  void _toggleCamera() async {
    final track = participant.videoTrackPublications.firstOrNull?.track;
    if (track == null) return;
    try {
      final newPosition = position.switched();
      await track.setCameraPosition(newPosition);
      setState(() => position = newPosition);
    } catch (error) {
      debugPrint('could not restart track: $error');
    }
  }

  void _enableScreenShare() async {
    if (lkPlatformIsDesktop()) {
      try {
        final source = await showDialog<DesktopCapturerSource>(
          context: context,
          builder: (context) => ScreenSelectDialog(),
        );
        if (source == null) {
          debugPrint('cancelled screenshare');
          return;
        }
        final track = await LocalVideoTrack.createScreenShareTrack(
          ScreenShareCaptureOptions(
            sourceId: source.id,
            maxFrameRate: 15.0,
          ),
        );
        await participant.publishVideoTrack(track);
      } catch (e) {
        debugPrint('could not publish video: $e');
      }
      return;
    }
    if (lkPlatformIs(PlatformType.android)) {
      final hasCapturePermission = await Helper.requestCapturePermission();
      if (!hasCapturePermission) return;

      requestBackgroundPermission([bool isRetry = false]) async {
        try {
          bool hasPermissions = await FlutterBackground.hasPermissions;
          if (!isRetry) {
            const androidConfig = FlutterBackgroundAndroidConfig(
              notificationTitle: 'Screen Sharing',
              notificationText: 'LiveKit Example is sharing the screen.',
              notificationImportance: AndroidNotificationImportance.normal,
              notificationIcon:
              AndroidResource(name: 'livekit_ic_launcher', defType: 'mipmap'),
            );
            hasPermissions =
            await FlutterBackground.initialize(androidConfig: androidConfig);
          }
          if (hasPermissions && !FlutterBackground.isBackgroundExecutionEnabled) {
            await FlutterBackground.enableBackgroundExecution();
          }
        } catch (e) {
          if (!isRetry) {
            return await Future<void>.delayed(
                const Duration(seconds: 1), () => requestBackgroundPermission(true));
          }
          debugPrint('could not publish video: $e');
        }
      }

      await requestBackgroundPermission();
    }

    if (lkPlatformIsWebMobile()) {
      if (!mounted) return;
      await context.showErrorDialog('Screen share is not supported on mobile web');
      return;
    }
    await participant.setScreenShareEnabled(true, captureScreenAudio: true);
  }

  void _disableScreenShare() async {
    await participant.setScreenShareEnabled(false);
    if (lkPlatformIs(PlatformType.android)) {
      try {} catch (error) {
        debugPrint('error disabling screen share: $error');
      }
    }
  }

  void _onTapDisconnect() async {
    final result = await context.showDisconnectDialog();
    if (result == true) await widget.room.disconnect();
  }

  Future<void> _openBleSheet() async {
    await _bleService.startScan();
    await _bleScanSub?.cancel();
    _bleScanSub = _bleService.devicesStream.listen((devices) {
      if (!mounted) return;
      setState(() => _bleDevices = devices);
    });

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Devices BLE',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Connecte un capteur BLE pour envoyer la télémétrie réelle.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _bleDevices.isEmpty
                    ? const Center(child: Text('Scan BLE en cours...'))
                    : ListView.builder(
                  itemCount: _bleDevices.length,
                  itemBuilder: (context, i) {
                    final device = _bleDevices[i];
                    final name = device.name.isEmpty
                        ? 'Unnamed (${device.id})'
                        : device.name;
                    final connected =
                        _bleService.connectedDeviceId == device.id;
                    return ListTile(
                      title: Text(name),
                      subtitle: Text('RSSI ${device.rssi}'),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          await _bleService.connectAndListen(device.id);
                          // Notify RoomPage so it can subscribe to
                          // telemetryStream and update _bleTelemetry
                          widget.onBleConnected();
                          if (mounted) setState(() {});
                        },
                        child: Text(connected ? 'Connecté' : 'Connecter'),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await _bleService.disconnect();
                        // Notify RoomPage to clear _bleTelemetry
                        widget.onBleDisconnected();
                        if (mounted) setState(() {});
                      },
                      child: const Text('Déconnecter'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fermer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await _bleService.stopScan();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 5,
        runSpacing: 5,
        children: [
          if (participant.isMicrophoneEnabled())
            if (lkPlatformIs(PlatformType.android))
              IconButton(
                onPressed: _disableAudio,
                icon: const Icon(Icons.mic),
                iconSize: 30,
                tooltip: 'mute audio',
              )
            else
              PopupMenuButton<MediaDevice>(
                icon: const Icon(Icons.settings_voice),
                offset: const Offset(0, -90),
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem<MediaDevice>(
                      value: null,
                      onTap: isMuted ? _enableAudio : _disableAudio,
                      child: const ListTile(
                        leading: Icon(Icons.mic_off, color: Colors.white),
                        title: Text('Mute Microphone'),
                      ),
                    ),
                    if (_audioInputs != null)
                      ..._audioInputs!.map((device) {
                        return PopupMenuItem<MediaDevice>(
                          value: device,
                          child: ListTile(
                            leading: (device.deviceId ==
                                widget.room.selectedAudioInputDeviceId)
                                ? const Icon(Icons.check_box_outlined,
                                color: Colors.white)
                                : const Icon(Icons.check_box_outline_blank,
                                color: Colors.white),
                            title: Text(device.label),
                          ),
                          onTap: () => _selectAudioInput(device),
                        );
                      })
                  ];
                },
              )
          else
            IconButton(
              onPressed: _enableAudio,
              icon: const Icon(Icons.mic_off),
              tooltip: 'un-mute audio',
              iconSize: 30,
            ),
          if (!lkPlatformIsMobile())
            PopupMenuButton<MediaDevice>(
              icon: const Icon(Icons.volume_up),
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem<MediaDevice>(
                    value: null,
                    child: ListTile(
                      leading: Icon(Icons.speaker, color: Colors.white),
                      title: Text('Select Audio Output'),
                    ),
                  ),
                  if (_audioOutputs != null)
                    ..._audioOutputs!.map((device) {
                      return PopupMenuItem<MediaDevice>(
                        value: device,
                        child: ListTile(
                          leading: (device.deviceId ==
                              widget.room.selectedAudioOutputDeviceId)
                              ? const Icon(Icons.check_box_outlined,
                              color: Colors.white)
                              : const Icon(Icons.check_box_outline_blank,
                              color: Colors.white),
                          title: Text(device.label),
                        ),
                        onTap: () => _selectAudioOutput(device),
                      );
                    })
                ];
              },
            ),
          if (!kIsWeb && lkPlatformIsMobile())
            IconButton(
              disabledColor: Colors.grey,
              onPressed: _setSpeakerphoneOn,
              icon: Icon(_speakerphoneOn ? Icons.speaker_phone : Icons.hearing),
              tooltip: 'Switch SpeakerPhone',
              iconSize: 30,
            ),
          if (participant.isCameraEnabled())
            IconButton(
              onPressed: _disableVideo,
              icon: const Icon(Icons.videocam),
              tooltip: 'disable_video',
              iconSize: 30,
            )
          else
            IconButton(
              onPressed: _enableVideo,
              icon: const Icon(Icons.videocam_off),
              tooltip: 'un-mute video',
              iconSize: 30,
            ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: _toggleCamera,
            tooltip: 'toggle camera',
            iconSize: 30,
          ),
          IconButton(
            tooltip: 'ble-connect',
            onPressed: _openBleSheet,
            icon: const Icon(Icons.bluetooth_searching),
          ),
          if (participant.isScreenShareEnabled())
            IconButton(
              icon: const Icon(Icons.monitor_outlined),
              onPressed: _disableScreenShare,
              tooltip: 'unshare screen (experimental)',
              iconSize: 30,
            )
          else
            IconButton(
              icon: const Icon(Icons.monitor),
              onPressed: _enableScreenShare,
              tooltip: 'share screen (experimental)',
              iconSize: 30,
            ),
          IconButton(
            onPressed: _onTapDisconnect,
            icon: const Icon(Icons.call_end_rounded, color: Colors.red),
            tooltip: 'disconnect',
            iconSize: 30,
          ),
        ],
      ),
    );
  }
}