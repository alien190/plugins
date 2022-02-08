import 'package:flutter/services.dart';

/// Device tilts model
class CameraDeviceTilts {
  /// The rotation angle of the image
  final double targetImageRotation;

  /// Current horizontal tilt
  final double horizontalTilt;

  /// Current vertical tilt
  final double verticalTilt;

  /// Indicates if the horizontal tilt is available on a device
  final bool isHorizontalTiltAvailable;

  /// Indicates if the vertical tilt is available on a device
  final bool isVerticalTiltAvailable;

  /// Locked capture orientation
  final int lockedCaptureAngle;

  /// A device orientation angle
  final int deviceOrientationAngle;

  /// default constructor for [CameraDeviceTilts]
  CameraDeviceTilts({
    required this.targetImageRotation,
    required this.horizontalTilt,
    required this.verticalTilt,
    required this.isHorizontalTiltAvailable,
    required this.isVerticalTiltAvailable,
    required this.lockedCaptureAngle,
    required this.deviceOrientationAngle,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraDeviceTilts &&
          runtimeType == other.runtimeType &&
          targetImageRotation == other.targetImageRotation &&
          horizontalTilt == other.horizontalTilt &&
          verticalTilt == other.verticalTilt &&
          isHorizontalTiltAvailable == other.isHorizontalTiltAvailable &&
          isVerticalTiltAvailable == other.isVerticalTiltAvailable &&
          lockedCaptureAngle == other.lockedCaptureAngle &&
          deviceOrientationAngle == other.deviceOrientationAngle;

  @override
  int get hashCode =>
      targetImageRotation.hashCode ^
      horizontalTilt.hashCode ^
      verticalTilt.hashCode ^
      isHorizontalTiltAvailable.hashCode ^
      isVerticalTiltAvailable.hashCode ^
      lockedCaptureAngle.hashCode ^
      deviceOrientationAngle.hashCode;
}
