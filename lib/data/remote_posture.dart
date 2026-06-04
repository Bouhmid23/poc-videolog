class RemotePosture {
  final String label;
  final double? confidence;
  final DateTime receivedAt;

  const RemotePosture({
    required this.label,
    this.confidence,
    required this.receivedAt,
  });

  factory RemotePosture.fromJson(
      Map<String, dynamic> json, {
        DateTime? receivedAt,
      }) {
    final normalized = _extractPostureMap(json);
    final label = _readLabel(normalized);
    if (label == null || label.trim().isEmpty) {
      throw const FormatException('Posture payload without label');
    }

    return RemotePosture(
      label: label.trim(),
      confidence: _readConfidence(normalized),
      receivedAt: receivedAt ?? DateTime.now(),
    );
  }

  static RemotePosture? tryParse(
      Map<String, dynamic> json, {
        DateTime? receivedAt,
      }) {
    try {
      return RemotePosture.fromJson(json, receivedAt: receivedAt);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static Map<String, dynamic> _extractPostureMap(Map<String, dynamic> json) {
    final payload = json['payload'];
    if (payload is Map) {
      final payloadMap = Map<String, dynamic>.from(payload);
      if (_looksLikePosturePayload(payloadMap)) return payloadMap;
    }

    final posture = json['posture'] ?? json['pose'];
    if (posture is Map) {
      return Map<String, dynamic>.from(posture);
    }

    if (_looksLikePosturePayload(json)) {
      return json;
    }

    throw const FormatException('Not a posture payload');
  }

  static bool _looksLikePosturePayload(Map<String, dynamic> json) {
    final type = json['type'];
    return type == 'posture' ||
        type == 'pose' ||
        json.containsKey('posture') ||
        json.containsKey('pose') ||
        json.containsKey('label') ||
        json.containsKey('status');
  }

  static String? _readLabel(Map<String, dynamic> json) {
    final posture = json['posture'] ?? json['pose'];
    if (posture is String) return posture;

    final label = json['label'] ?? json['status'] ?? json['state'];
    if (label is String) return label;

    return null;
  }

  static double? _readConfidence(Map<String, dynamic> json) {
    final value = json['confidence'] ?? json['score'] ?? json['probability'];
    if (value is num) return value.clamp(0, 1).toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed == null) return null;
      return parsed.clamp(0, 1).toDouble();
    }
    return null;
  }
}
