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

  /// Indicates if the horizontal tilt is available on a device
  final bool isHorizontalTiltAvailable;

  /// Indicates if the vertical tilt is available on a device
  final bool isVerticalTiltAvailable;

  /// default constructor for [CameraDeviceTilts]
  CameraDeviceTilts({
    required this.lockedCaptureOrientation,
    required this.deviceOrientation,
    required this.horizontalTilt,
    required this.verticalTilt,
    required this.isHorizontalTiltAvailable,
    required this.isVerticalTiltAvailable,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraDeviceTilts &&
          runtimeType == other.runtimeType &&
          lockedCaptureOrientation == other.lockedCaptureOrientation &&
          deviceOrientation == other.deviceOrientation &&
          horizontalTilt == other.horizontalTilt &&
          verticalTilt == other.verticalTilt &&
          isHorizontalTiltAvailable == other.isHorizontalTiltAvailable &&
          isVerticalTiltAvailable == other.isVerticalTiltAvailable;

  @override
  int get hashCode =>
      lockedCaptureOrientation.hashCode ^
      deviceOrientation.hashCode ^
      horizontalTilt.hashCode ^
      verticalTilt.hashCode ^
      isHorizontalTiltAvailable.hashCode ^
      isVerticalTiltAvailable.hashCode;
}
