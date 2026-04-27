import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitapp/core/api_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../exts.dart';
import '../theme.dart';
import 'room.dart';

// ─── Config POC ───────────────────────────────────────────────────────────────
// Pointe vers le LiveKit Server Docker exposé sur le réseau local
//
// Android Emulator  → 10.0.2.2  (alias loopback vers l'hôte)
// Device physique   → IP LAN de ta machine (ex: 192.168.1.42)
// iOS Simulator     → localhost
//
/*const String kLiveKitWsUrl  = 'ws://192.168.1.7:7880';   // WebSocket LiveKit
const String kLiveKitApiUrl = ApiService.localURL;  // HTTP API LiveKit
const String kApiBaseUrl    = ApiService.localURL; */ // Dashboard API (token)
const String kDefaultRoom   = 'poc-room';               // room utilisée par le POC

//const String kLiveKitWsUrl  = 'wss://livekit.opkodelabs.com';   // WebSocket LiveKit
const String kLiveKitWsUrl  = 'ws://192.168.1.7:7880';   // WebSocket LiveKit
//const String kLiveKitApiUrl = 'http://192.168.1.7:7880';  // HTTP API LiveKit
//const String kApiBaseUrl    = 'http://192.168.1.7:8000';

class JoinArgs {
  JoinArgs({
    required this.url,
    required this.token,
    required this.username,
    this.e2ee = false,
    this.e2eeKey,
    this.simulcast = true,
    this.adaptiveStream = true,
    this.dynacast = true,
    this.preferredCodec = 'VP8',
    this.enableBackupVideoCodec = true,
  });
  final String url;
  final String token;
  final String username;
  final bool e2ee;
  final String? e2eeKey;
  final bool simulcast;
  final bool adaptiveStream;
  final bool dynacast;
  final String preferredCodec;
  final bool enableBackupVideoCodec;
}

class PreJoinPage extends StatefulWidget {
  const PreJoinPage({required this.args, super.key});
  final JoinArgs args;
  @override
  State<StatefulWidget> createState() => _PreJoinPageState();
}

class _PreJoinPageState extends State<PreJoinPage> {
  static const _prefKeyEnableVideo = 'prejoin-enable-video';
  static const _prefKeyEnableAudio = 'prejoin-enable-audio';

  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _videoInputs = [];
  StreamSubscription? _subscription;

  bool _busy = false;
  bool _enableVideo = true;
  bool _enableAudio = true;
  LocalAudioTrack? _audioTrack;
  LocalVideoTrack? _videoTrack;
  MediaDevice? _selectedVideoDevice;
  MediaDevice? _selectedAudioDevice;
  VideoParameters _selectedVideoParameters = VideoParametersPresets.h720_169;

  @override
  void initState() {
    super.initState();
    unawaited(_initStateAsync());
  }

  Future<void> _initStateAsync() async {
    await _readPrefs();
    _subscription = Hardware.instance.onDeviceChange.stream.listen(_loadDevices);
    final devices = await Hardware.instance.enumerateDevices();
    await _loadDevices(devices);
  }

  @override
  void deactivate() {
    unawaited(_subscription?.cancel());
    super.deactivate();
  }

  Future<void> _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();
    if (_selectedAudioDevice != null && !_audioInputs.contains(_selectedAudioDevice)) {
      _selectedAudioDevice = null;
    }
    if (_audioInputs.isEmpty) { await _audioTrack?.stop(); _audioTrack = null; }
    if (_selectedVideoDevice != null && !_videoInputs.contains(_selectedVideoDevice)) {
      _selectedVideoDevice = null;
    }
    if (_videoInputs.isEmpty) { await _videoTrack?.stop(); _videoTrack = null; }
    if (_enableAudio && _audioInputs.isNotEmpty && _selectedAudioDevice == null) {
      _selectedAudioDevice = _audioInputs.first;
      Future.delayed(const Duration(milliseconds: 100), () async {
        if (!mounted) return;
        await _changeLocalAudioTrack();
        if (mounted) setState(() {});
      });
    }
    if (_enableVideo && _videoInputs.isNotEmpty && _selectedVideoDevice == null) {
      _selectedVideoDevice = _videoInputs.first;
      Future.delayed(const Duration(milliseconds: 100), () async {
        if (!mounted) return;
        await _changeLocalVideoTrack();
        if (mounted) setState(() {});
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _setEnableVideo(value) async {
    _enableVideo = value;
    await _writePrefs();
    if (!_enableVideo) {
      await _videoTrack?.stop();
      _videoTrack = null;
      _selectedVideoDevice = null;
    } else {
      if (_selectedVideoDevice == null && _videoInputs.isNotEmpty) {
        _selectedVideoDevice = _videoInputs.first;
      }
      await _changeLocalVideoTrack();
    }
    setState(() {});
  }

  Future<void> _setEnableAudio(value) async {
    _enableAudio = value;
    await _writePrefs();
    if (!_enableAudio) {
      await _audioTrack?.stop();
      _audioTrack = null;
      _selectedAudioDevice = null;
    } else {
      if (_selectedAudioDevice == null && _audioInputs.isNotEmpty) {
        _selectedAudioDevice = _audioInputs.first;
      }
      await _changeLocalAudioTrack();
    }
    setState(() {});
  }

  Future<void> _changeLocalAudioTrack() async {
    if (!_enableAudio) return;
    if (_audioTrack != null) { await _audioTrack!.stop(); _audioTrack = null; }
    if (_selectedAudioDevice != null) {
      _audioTrack = await LocalAudioTrack.create(
        AudioCaptureOptions(deviceId: _selectedAudioDevice!.deviceId),
      );
      await _audioTrack!.start();
    }
  }

  Future<void> _changeLocalVideoTrack() async {
    if (!_enableVideo) return;
    if (_videoTrack != null) { await _videoTrack!.stop(); _videoTrack = null; }
    if (_selectedVideoDevice != null) {
      _videoTrack = await LocalVideoTrack.createCameraTrack(CameraCaptureOptions(
        deviceId: _selectedVideoDevice!.deviceId,
        params: _selectedVideoParameters,
      ));
      await _videoTrack!.start();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  _join(BuildContext context) async {
    _busy = true;
    setState(() {});

    final args = widget.args;

    try {
      E2EEOptions? e2eeOptions;
      if (args.e2ee && args.e2eeKey != null) {
        final keyProvider = await BaseKeyProvider.create();
        e2eeOptions = E2EEOptions(keyProvider: keyProvider);
        await keyProvider.setKey(args.e2eeKey!);
      }

      const cameraEncoding  = VideoEncoding(maxBitrate: 5 * 1000 * 1000, maxFramerate: 30);
      const screenEncoding  = VideoEncoding(maxBitrate: 3 * 1000 * 1000, maxFramerate: 15);

      final room = Room(
        roomOptions: RoomOptions(
          adaptiveStream: args.adaptiveStream,
          dynacast: args.dynacast,
          defaultAudioPublishOptions: const AudioPublishOptions(
            name: 'custom_audio_track_name',
          ),
          defaultCameraCaptureOptions: const CameraCaptureOptions(
            maxFrameRate: 30,
            params: VideoParameters(dimensions: VideoDimensions(1280, 720)),
          ),
          defaultScreenShareCaptureOptions: const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
            params: VideoParameters(dimensions: VideoDimensionsPresets.h1080_169),
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: args.simulcast,
            videoCodec: args.preferredCodec,
            backupVideoCodec: BackupVideoCodec(enabled: args.enableBackupVideoCodec),
            videoEncoding: cameraEncoding,
            screenShareEncoding: screenEncoding,
          ),
          encryption: e2eeOptions,
        ),
      );

      final listener = room.createListener();
      await room.prepareConnection(args.url, args.token);

      await room.connect(
        args.url,
        args.token,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(track: _audioTrack),
          camera: TrackOption(track: _videoTrack),
        ),
      );

      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => RoomPage(room, listener, fastConnection: true),
        ),
      );
    } catch (error) {
      debugPrint('Could not connect $error');
      if (!context.mounted) return;
      await context.showErrorDialog(error);
    } finally {
      setState(() { _busy = false; });
    }
  }

  void _actionBack(BuildContext context) async {
    await _setEnableVideo(false);
    await _setEnableAudio(false);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _readPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enableVideo = prefs.getBool(_prefKeyEnableVideo) ?? true;
      _enableAudio = prefs.getBool(_prefKeyEnableAudio) ?? true;
    });
  }

  Future<void> _writePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyEnableVideo, _enableVideo);
    await prefs.setBool(_prefKeyEnableAudio, _enableAudio);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Devices', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => _actionBack(context),
        ),
      ),
      body: Container(
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: 320,
                    height: 240,
                    child: Container(
                      alignment: Alignment.center,
                      color: Colors.black54,
                      child: _videoTrack != null
                          ? VideoTrackRenderer(renderMode: VideoRenderMode.auto, _videoTrack!)
                          : Container(
                        alignment: Alignment.center,
                        child: LayoutBuilder(
                          builder: (ctx, constraints) => Icon(
                            Icons.videocam_off,
                            color: LKColors.lkBlue,
                            size: math.min(constraints.maxHeight, constraints.maxWidth) * 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Camera toggle
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Camera:'),
                      Switch(value: _enableVideo, onChanged: _setEnableVideo),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 25),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton2<MediaDevice>(
                      isExpanded: true,
                      disabledHint: const Text('Disable Camera'),
                      hint: const Text('Select Camera'),
                      items: _enableVideo
                          ? _videoInputs.map((d) => DropdownMenuItem<MediaDevice>(
                        value: d,
                        child: Text(d.label, style: const TextStyle(fontSize: 14)),
                      )).toList()
                          : [],
                      value: _selectedVideoDevice,
                      onChanged: (MediaDevice? value) async {
                        if (value != null) {
                          _selectedVideoDevice = value;
                          await _changeLocalVideoTrack();
                          setState(() {});
                        }
                      },
                      buttonStyleData: const ButtonStyleData(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          height: 40, width: 140),
                      menuItemStyleData: const MenuItemStyleData(height: 40),
                    ),
                  ),
                ),
                if (_enableVideo)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 25),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton2<VideoParameters>(
                        isExpanded: true,
                        hint: const Text('Select Video Dimensions'),
                        items: [
                          VideoParametersPresets.h480_43,
                          VideoParametersPresets.h540_169,
                          VideoParametersPresets.h720_169,
                          VideoParametersPresets.h1080_169,
                        ].map((p) => DropdownMenuItem<VideoParameters>(
                          value: p,
                          child: Text('${p.dimensions.width}x${p.dimensions.height}',
                              style: const TextStyle(fontSize: 14)),
                        )).toList(),
                        value: _selectedVideoParameters,
                        onChanged: (VideoParameters? value) async {
                          if (value != null) {
                            _selectedVideoParameters = value;
                            await _changeLocalVideoTrack();
                            setState(() {});
                          }
                        },
                        buttonStyleData: const ButtonStyleData(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            height: 40, width: 140),
                        menuItemStyleData: const MenuItemStyleData(height: 40),
                      ),
                    ),
                  ),
                // Microphone toggle
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Microphone:'),
                      Switch(value: _enableAudio, onChanged: _setEnableAudio),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 25),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton2<MediaDevice>(
                      isExpanded: true,
                      disabledHint: const Text('Disable Microphone'),
                      hint: const Text('Select Microphone'),
                      items: _enableAudio
                          ? _audioInputs.map((d) => DropdownMenuItem<MediaDevice>(
                        value: d,
                        child: Text(d.label, style: const TextStyle(fontSize: 14)),
                      )).toList()
                          : [],
                      value: _selectedAudioDevice,
                      onChanged: (MediaDevice? value) async {
                        if (value != null) {
                          _selectedAudioDevice = value;
                          await _changeLocalAudioTrack();
                          setState(() {});
                        }
                      },
                      buttonStyleData: const ButtonStyleData(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          height: 40, width: 140),
                      menuItemStyleData: const MenuItemStyleData(height: 40),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : () => _join(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: SizedBox(
                            height: 15, width: 15,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          ),
                        ),
                      const Text('JOIN'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── ConnectPage ──────────────────────────────────────────────────────────────

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});
  @override
  State<StatefulWidget> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _usernameCtrl = TextEditingController();
  bool _busy = false;
  final bool _simulcast = true;
  final bool _adaptiveStream = true;
  final bool _dynacast = true;
  final bool _e2ee = false;
  final String _preferredCodec = 'VP8';

  @override
  void initState() {
    super.initState();
    if (lkPlatformIs(PlatformType.android)) {
      unawaited(_checkPermissions());
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    for (final perm in [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.camera,
      Permission.microphone,
    ]) {
      final status = await perm.request();
      if (status.isPermanentlyDenied) {
        debugPrint('Permission $perm refusée définitivement');
      }
    }
  }

  /// Génère un token JWT LiveKit via le Dashboard API du POC.
  /// L'API délègue à livekit-api Python qui signe le JWT avec API_KEY/SECRET.
  Future<String> _fetchToken({
    required String username,
    required String room,
  }) async {
    // Endpoint ajouté dans api.py du POC
    final response = await http.post(
      Uri.parse('$kApiBaseUrl/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identity': username, 'room': room}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['token'] as String;
    } else {
      throw Exception('Token fetch failed (${response.statusCode}): ${response.body}');
    }
  }

  /*Future<String> _fetchToken({
    required String username,
    required String room,
  }) async {
    // Endpoint ajouté dans api.py du POC
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/${ApiService.tokenEndpoint}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'room': room}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['token'] as String;
    } else {
      throw Exception('Token fetch failed (${response.statusCode}): ${response.body}');
    }
  }*/

  Future<void> _connect(BuildContext ctx) async {
    if (_usernameCtrl.text.trim().isEmpty) {
      await ctx.showErrorDialog('Entrer un nom d\'utilisateur');
      return;
    }

    setState(() { _busy = true; });

    try {
      final username = _usernameCtrl.text.trim();
      debugPrint('Connexion → room=$kDefaultRoom user=$username');

      final token = await _fetchToken(username: username, room: kDefaultRoom);

      if (!ctx.mounted) return;
      await Navigator.push<void>(
        ctx,
        MaterialPageRoute(
          builder: (_) => PreJoinPage(
            args: JoinArgs(
              url:                  kLiveKitWsUrl,
              username:             username,
              token:                token,
              e2ee:                 _e2ee,
              simulcast:            _simulcast,
              adaptiveStream:       _adaptiveStream,
              dynacast:             _dynacast,
              preferredCodec:       _preferredCodec,
              enableBackupVideoCodec: ['VP9', 'AV1'].contains(_preferredCodec),
            ),
          ),
        ),
      );
    } catch (error) {
      debugPrint('Erreur connexion: $error');
      if (!ctx.mounted) return;
      await ctx.showErrorDialog(error);
    } finally {
      setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Text(
                  '🎥 Videolog',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),
              // Info room
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Room: $kDefaultRoom',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('Server: $kLiveKitWsUrl',
                        style: const TextStyle(fontSize: 11, color: Colors.white54)),
                    Text('API: $kApiBaseUrl',
                        style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 25),
                child: TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom du participant',
                    hintText: 'ex: driver-01',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _busy ? null : () => _connect(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: SizedBox(
                          height: 15, width: 15,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                      ),
                    const Text('CONNECTER', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
