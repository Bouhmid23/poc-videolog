import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

import '../exts.dart';
import '../utils.dart';
import '../widgets/controls.dart';
import '../widgets/participant.dart';
import '../widgets/participant_info.dart';

// ─── Config réseau ────────────────────────────────────────────────────────────
// En dev local : pointe vers le dashboard-api Docker exposé sur :8000
// En prod      : remplacer par l'URL publique de ton API
//const String kApiBaseUrl = 'http://10.0.2.2:8000'; // Android emulator → localhost
 const String kApiBaseUrl = 'http://192.168.1.7:8000';
 //const String kApiBaseUrl = 'https://livekit.opkodelabs.com';

// ─── Format télémétrie (aligné avec telemetry-agent/agent.py) ─────────────────
// Le topic "telemetry" est filtré par l'agent Python.
// Le champ "ts" (Unix ms) est la clé de synchronisation avec la vidéo.
Map<String, dynamic> _buildTelemetryPayload ({
  required double speed,
  required double lat,
  required double lng,
}) {
  return {
    "type": "telemetry",
    "ts": DateTime.now().millisecondsSinceEpoch, // clé de sync PTS
    "payload": {
      "role": "trainee",
      "speed":      12.3,
      "heart_rate": 162,
      "cadence":    158,
      "gps": {
        "lat": lat,
        "lng": lng,
      },
    },
  };
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
  EventsListener<RoomEvent> get _listener => widget.listener;
  bool get fastConnection => widget.fastConnection;

  // ── DataTrack & Telemetry ────────────────────────────────────────
  //LocalDataTrack? _dataTrack;
  Timer?          _telemetryTimer;
  bool            _telemetryActive = false;
  int             _telemetryCount  = 0;

  // ── Recording ────────────────────────────────────────────────────
  bool   _recordingStarted = false;
  String _currentEgressId  = '';

  // ── Simulation de capteurs (remplacer par vrais capteurs en prod) ─
  final _random = math.Random();
  double _simT  = 0.0; // compteur de temps pour variation sinusoïdale

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
            duration: const Duration(seconds: 5));
      };
    }
  }

  // ── Setup post-connexion ──────────────────────────────────────────

  Future<void> _onConnectedSetup() async {
    final participant = widget.room.localParticipant;
    if (participant == null) {
      debugPrint('❌ Pas de participant local');
      return;
    }

    debugPrint('✅ Participant prêt → init DataTrack');

    // 1. Créer et publier le DataTrack
    /*_dataTrack = await LocalDataTrack.create();
    await participant.publishDataTrack(_dataTrack!);*/
    debugPrint('📡 DataTrack publié');

    // 2. Démarrer la télémétrie
    _startTelemetry();

    // 3. Démarrer l'enregistrement Egress (une seule fois)
    /*if (!_recordingStarted) {
      await _startRecording();
    }*/
  }

  // ── Télémétrie ────────────────────────────────────────────────────

  void _startTelemetry() {
    _telemetryActive = true;
    _telemetryTimer = Timer.periodic(
      const Duration(milliseconds: 500), // 2 Hz — aligné avec TELEMETRY_INTERVAL
      _sendTelemetryTick,
    );
    debugPrint('📊 Télémétrie démarrée (2 Hz)');
  }

  void _sendTelemetryTick(Timer timer) {
    //if (!_telemetryActive || _dataTrack == null) return;

    _simT += 0.5;

    // Données simulées — remplacer par sensors/gps packages en production
    final speed       = 90 + 30 * math.sin(_simT * 0.3) + _random.nextDouble() * 4 - 2;
    final rpm         = (2000 + speed * 25 + _random.nextDouble() * 200 - 100).toInt();
    final gear        = math.min(6, math.max(1, (speed / 20).round()));
    final throttle    = 0.4 + _random.nextDouble() * 0.6;
    final brake       = _random.nextDouble() * 0.2;
    final temperature = 85 + _random.nextDouble() * 10 - 5;
    final lat         = 36.8065 + 0.002 * math.sin(_simT * 0.1);
    final lng         = 10.1815 + 0.003 * math.cos(_simT * 0.1);

    final payload = _buildTelemetryPayload(
      speed:       double.parse(speed.toStringAsFixed(1)),
      lat:         double.parse(lat.toStringAsFixed(6)),
      lng:         double.parse(lng.toStringAsFixed(6)),
    );

    try {
      /*_dataTrack!.send(
        utf8.encode(jsonEncode(payload)),
        reliability: Reliability.reliable,
        topic: 'telemetry', // ← topic filtré par agent.py
      );*/
      widget.room.localParticipant?.publishData(
        utf8.encode(jsonEncode(payload)),
        reliable: true,
        topic: 'telemetry',
      );
      _telemetryCount++;
      if (_telemetryCount % 20 == 0) {
        debugPrint('📡 Télémétrie #$_telemetryCount | speed=${speed.toStringAsFixed(0)}km/h rpm=$rpm');
      }
    } catch (e) {
      debugPrint('❌ Erreur envoi DataTrack: $e');
    }
  }

  void _stopTelemetry() {
    _telemetryActive = false;
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    debugPrint('📊 Télémétrie arrêtée (${"$_telemetryCount"} événements envoyés)');
  }

  // ── Enregistrement Egress ─────────────────────────────────────────

  Future<void> _startRecording() async {
    final roomName = widget.room.name;
    debugPrint('🎬 Démarrage enregistrement pour room: $roomName');

    try {
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/recordings/start?room_name=$roomName&layout=speaker'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentEgressId = data['egress_id'] ?? '';
        _recordingStarted = true;
        debugPrint('✅ Enregistrement démarré | egress_id=$_currentEgressId');
      } else {
        debugPrint('⚠️  Réponse inattendue: ${response.statusCode} — ${response.body}');
        // Pas bloquant : on continue sans recording
      }
    } catch (e) {
      debugPrint('❌ Erreur démarrage recording: $e');
      // Pas bloquant : la session continue même sans recording
    }
  }

  Future<void> _stopRecording() async {
    if (_currentEgressId.isEmpty) return;
    debugPrint('⏹️  Arrêt enregistrement: $_currentEgressId');

    try {
      final response = await http.post(
        Uri.parse('$kApiBaseUrl/recordings/stop?egress_id=$_currentEgressId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Recording terminé | status=${data['status']}');
        final files = data['files'] as List? ?? [];
        for (final f in files) {
          debugPrint('   📦 ${f['filename']} (${f['size_bytes']} bytes)');
        }
      }
    } catch (e) {
      debugPrint('❌ Erreur arrêt recording: $e');
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  void dispose() {
    _stopTelemetry();
    widget.room.removeListener(_onRoomDidUpdate);
    unawaited(_disposeRoomAsync());
    onWindowShouldClose = null;
    super.dispose();
  }

  Future<void> _disposeRoomAsync() async {
    // Arrêter l'enregistrement proprement avant de quitter
    //await _stopRecording();
    await _listener.dispose();
    await widget.room.dispose();
  }

  // ── Event listeners ───────────────────────────────────────────────

  void _setUpListeners() => _listener
    ..on<RoomDisconnectedEvent>((event) async {
      if (event.reason != null) {
        debugPrint('Room déconnectée: ${event.reason}');
      }
      _stopTelemetry();
      WidgetsBindingCompatible.instance?.addPostFrameCallback(
            (timeStamp) => Navigator.popUntil(context, (route) => route.isFirst),
      );
    })
    ..on<ParticipantEvent>((event) {
      _sortParticipants();
    })
    ..on<RoomRecordingStatusChanged>((event) {
      unawaited(context.showRecordingStatusChangedDialog(event.activeRecording));
    })
    ..on<RoomAttemptReconnectEvent>((event) {
      debugPrint('Reconnexion ${event.attempt}/${event.maxAttemptsRetry}');
    })
    ..on<LocalTrackSubscribedEvent>((event) {
      debugPrint('Local track subscribé: ${event.trackSid}');
    })
    ..on<LocalTrackPublishedEvent>((_) => _sortParticipants())
    ..on<LocalTrackUnpublishedEvent>((_) => _sortParticipants())
    ..on<TrackSubscribedEvent>((_) => _sortParticipants())
    ..on<TrackUnsubscribedEvent>((_) => _sortParticipants())
    ..on<TrackE2EEStateEvent>(_onE2EEStateEvent)
    ..on<ParticipantNameUpdatedEvent>((event) {
      debugPrint('Participant renommé: ${event.participant.identity} → ${event.name}');
      _sortParticipants();
    })
    ..on<ParticipantMetadataUpdatedEvent>((event) {
      debugPrint('Metadata mise à jour: ${event.participant.identity}');
    })
    ..on<RoomMetadataChangedEvent>((event) {
      debugPrint('Room metadata: ${event.metadata}');
    })
    ..on<DataReceivedEvent>((event) {
      // Optionnel : afficher les données reçues (ex: feedback du serveur)
      String decoded = 'Failed to decode';
      try {
        decoded = utf8.decode(event.data);
      } catch (err) {
        debugPrint('Failed to decode: $err');
      }
      //unawaited(context.showDataReceivedDialog(decoded));
    })
    ..on<AudioPlaybackStatusChanged>((event) async {
      if (!widget.room.canPlaybackAudio) {
        debugPrint('Audio playback failed for iOS Safari');
        final yesno = await context.showPlayAudioManuallyDialog();
        if (yesno == true) {
          await widget.room.startAudio();
        }
      }
    });

  void _askPublish() async {
    final result = await context.showPublishDialog();
    if (!mounted) return;
    if (result != true) return;
    try {
      await widget.room.localParticipant?.setCameraEnabled(true);
    } catch (error) {
      debugPrint('could not publish video: $error');
      if (!mounted) return;
      await context.showErrorDialog(error);
    }
    try {
      await widget.room.localParticipant?.setMicrophoneEnabled(true);
    } catch (error) {
      debugPrint('could not publish audio: $error');
      if (!mounted) return;
      await context.showErrorDialog(error);
    }
  }

  void _onRoomDidUpdate() => _sortParticipants();

  void _onE2EEStateEvent(TrackE2EEStateEvent e2eeState) {
    debugPrint('e2ee state: $e2eeState');
  }

  void _sortParticipants() {
    final userMediaTracks = <ParticipantTrack>[];
    final screenTracks    = <ParticipantTrack>[];
    for (var participant in widget.room.remoteParticipants.values) {
      for (var t in participant.videoTrackPublications) {
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
            participant: participant,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          userMediaTracks.add(ParticipantTrack(participant: participant));
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
      if (a.participant.hasVideo != b.participant.hasVideo) {
        return a.participant.hasVideo ? -1 : 1;
      }
      return a.participant.joinedAt.millisecondsSinceEpoch -
          b.participant.joinedAt.millisecondsSinceEpoch;
    });
    final localTracks = widget.room.localParticipant?.videoTrackPublications;
    if (localTracks != null) {
      for (var t in localTracks) {
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
            participant: widget.room.localParticipant!,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          userMediaTracks.add(ParticipantTrack(participant: widget.room.localParticipant!));
        }
      }
    }
    setState(() {
      participantTracks = [...screenTracks, ...userMediaTracks];
    });
  }

  // ── UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: participantTracks.isNotEmpty
                  ? ParticipantWidget.widgetFor(participantTracks.first,
                  showStatsLayer: true)
                  : Container(),
            ),
            if (widget.room.localParticipant != null)
              SafeArea(
                top: false,
                child: ControlsWidget(
                    widget.room, widget.room.localParticipant!),
              )
          ],
        ),
        // Barre de participants secondaires
        Positioned(
          left: 0,
          right: 0,
          bottom: 150,
          child: SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: math.max(0, participantTracks.length - 1),
              itemBuilder: (BuildContext context, int index) => SizedBox(
                width: 200,
                height: 200,
                child: ParticipantWidget.widgetFor(
                    participantTracks[index + 1]),
              ),
            ),
          ),
        ),
        // Indicateur télémétrie (coin haut droit)
        Positioned(
          top: 48,
          right: 12,
          child: _TelemetryIndicator(
            active: _telemetryActive,
            count:  _telemetryCount,
            egressId: _currentEgressId,
          ),
        ),
      ],
    ),
  );
}

// ── Widget indicateur télémétrie ──────────────────────────────────────────────

class _TelemetryIndicator extends StatelessWidget {
  final bool   active;
  final int    count;
  final String egressId;

  const _TelemetryIndicator({
    required this.active,
    required this.count,
    required this.egressId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: active ? Colors.greenAccent : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              active ? '📡 Télémétrie ON' : '📡 OFF',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ]),
          if (count > 0)
            Text(
              '$count events envoyés',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          if (egressId.isNotEmpty)
            Text(
              '🔴 REC',
              style: const TextStyle(color: Colors.redAccent, fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }
}