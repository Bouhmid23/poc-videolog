import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

class LiveKitService extends ChangeNotifier {
  Room? _room;

  Room? get room => _room;

  bool get isConnected => _room?.connectionState == ConnectionState.connected;

  List<Participant> get participants {
    if (_room == null) return [];
    return [
      _room!.localParticipant!,
      ..._room!.remoteParticipants.values,
    ];
  }

  Future<void> connect({
    required String url,
    required String token,
  }) async {
    _room = Room();

    await _room!.connect(url, token);

    await _room!.localParticipant?.setCameraEnabled(true);
    await _room!.localParticipant?.setMicrophoneEnabled(true);

    _room!.addListener(_roomListener);

    notifyListeners();
  }

  void _roomListener() {
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final enabled =
        _room?.localParticipant?.isCameraEnabled() ?? false;
    await _room?.localParticipant?.setCameraEnabled(!enabled);
  }

  Future<void> toggleMicrophone() async {
    final enabled =
        _room?.localParticipant?.isMicrophoneEnabled() ?? false;
    await _room?.localParticipant?.setMicrophoneEnabled(!enabled);
  }

  Future<void> disconnect() async {
    await _room?.disconnect();
    _room = null;
    notifyListeners();
  }
}