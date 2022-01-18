import 'package:flutter/services.dart';
import 'package:quiver/core.dart';

/// Device tilts model
class CameraDeviceTilts {
  /// Locked capture orientation
  final Optional<DeviceOrientation>? lockedCaptureOrientation;

  /// Current device orientation
  final DeviceOrientation deviceOrientation;

  /// Current horizontal tilt
  final int horizontalTilt;

  /// Current vertical tilt
  final int verticalTilt;

  /// default constructor for [CameraDeviceTilts]
  CameraDeviceTilts({
    required this.lockedCaptureOrientation,
    required this.deviceOrientation,
    required this.horizontalTilt,
    required this.verticalTilt,
  });
}
