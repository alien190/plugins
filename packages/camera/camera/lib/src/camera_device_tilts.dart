import 'package:flutter/services.dart';

/// Device tilts model
class CameraDeviceTilts {
  /// Locked capture orientation
  final DeviceOrientation? lockedCaptureOrientation;

  /// Current device orientation
  final DeviceOrientation deviceOrientation;

  /// Current horizontal tilt
  final int horizontalTilt;

  /// Current vertical tilt
  final double verticalTilt;

  /// default constructor for [CameraDeviceTilts]
  CameraDeviceTilts({
    required this.lockedCaptureOrientation,
    required this.deviceOrientation,
    required this.horizontalTilt,
    required this.verticalTilt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraDeviceTilts &&
          runtimeType == other.runtimeType &&
          lockedCaptureOrientation == other.lockedCaptureOrientation &&
          deviceOrientation == other.deviceOrientation &&
          horizontalTilt == other.horizontalTilt &&
          verticalTilt == other.verticalTilt;

  @override
  int get hashCode =>
      lockedCaptureOrientation.hashCode ^
      deviceOrientation.hashCode ^
      horizontalTilt.hashCode ^
      verticalTilt.hashCode;
}
