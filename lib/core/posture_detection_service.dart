
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

class PostureSmoothing {
  final Map<LandmarkType, _SmoothedPoint> _smoothedPoints = {};
  final double alpha;

  PostureSmoothing({this.alpha = 0.35});

  Pose smooth(Pose pose) {
    final List<PoseLandmark> smoothedLandmarks = [];

    for (final entry in pose.landmarks) {
      final type = entry.type;

      final smoothed = _smoothedPoints.putIfAbsent(
        type,
            () => _SmoothedPoint(
          entry.x,
          entry.y,
          entry.z,
        ),
      );

      smoothed.update(entry.x, entry.y, entry.z, alpha);

      smoothedLandmarks.add(
        PoseLandmark(
          type: type,
          x: smoothed.x,
          y: smoothed.y,
          z: smoothed.z,
          visibility: entry.visibility,
        ),
      );
    }

    return Pose(landmarks: smoothedLandmarks, score: pose.score);
  }

  void reset() {
    _smoothedPoints.clear();
  }
}

class _SmoothedPoint {
  double x, y, z;
  _SmoothedPoint(this.x, this.y, this.z);

  void update(double nx, double ny, double nz, double alpha) {
    x = x + alpha * (nx - x);
    y = y + alpha * (ny - y);
    z = z + alpha * (nz - z);
  }
}
