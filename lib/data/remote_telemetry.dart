class RemoteTelemetry {
  final int? heartRate;
  final double? cadence;
  final double? speed;
  final double? lat;
  final double? lng;
  final String? role;
  final DateTime receivedAt;

  const RemoteTelemetry({
    this.heartRate,
    this.cadence,
    this.speed,
    this.lat,
    this.lng,
    this.role,
    required this.receivedAt,
  });

  bool get hasHrm => heartRate != null;

  factory RemoteTelemetry.fromJson(
      Map<String, dynamic> json, {
        DateTime? receivedAt,
      }) {
    final payload = json['payload'];
    Map<String, dynamic> inner;
    if (payload is Map) {
      inner = Map<String, dynamic>.from(payload);
    } else {
      inner = json;
    }

    final gps = inner['gps'];
    double? lat;
    double? lng;
    if (gps is Map) {
      final gpsMap = Map<String, dynamic>.from(gps);
      lat = _readDouble(gpsMap['lat']);
      lng = _readDouble(gpsMap['lng']);
    }

    return RemoteTelemetry(
      heartRate: _readInt(inner['heart_rate']),
      cadence: _readDouble(inner['cadence']),
      speed: _readDouble(inner['speed']),
      lat: lat,
      lng: lng,
      role: inner['role'] is String ? inner['role'] as String : null,
      receivedAt: receivedAt ?? DateTime.now(),
    );
  }

  static RemoteTelemetry? tryParse(
      Map<String, dynamic> json, {
        DateTime? receivedAt,
      }) {
    if (json['type'] != 'telemetry') return null;
    try {
      return RemoteTelemetry.fromJson(json, receivedAt: receivedAt);
    } catch (_) {
      return null;
    }
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    return null;
  }

  static double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
