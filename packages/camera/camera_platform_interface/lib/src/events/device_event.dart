// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:camera_platform_interface/src/utils/utils.dart';
import 'package:flutter/services.dart';

import '../../camera_platform_interface.dart';

/// Generic Event coming from the native side of Camera,
/// not related to a specific camera module.
///
/// This class is used as a base class for all the events that might be
/// triggered from a device, but it is never used directly as an event type.
///
/// Do NOT instantiate new events like `DeviceEvent()` directly,
/// use a specific class instead:
///
/// Do `class NewEvent extend DeviceEvent` when creating your own events.
/// See below for examples: `DeviceOrientationChangedEvent`...
/// These events are more semantic and more pleasant to use than raw generics.
/// They can be (and in fact, are) filtered by the `instanceof`-operator.
abstract class DeviceEvent {}

/// The [DeviceOrientationChangedEvent] is fired every time the orientation of the device UI changes.
class DeviceOrientationChangedEvent extends DeviceEvent {
  /// The new orientation of the device
  final DeviceOrientation orientation;

  /// Build a new orientation changed event.
  DeviceOrientationChangedEvent(this.orientation);

  /// Converts the supplied [Map] to an instance of the [DeviceOrientationChangedEvent]
  /// class.
  DeviceOrientationChangedEvent.fromJson(Map<String, dynamic> json)
      : orientation = deserializeDeviceOrientation(json['orientation']);

  /// Converts the [DeviceOrientationChangedEvent] instance into a [Map] instance that
  /// can be serialized to JSON.
  Map<String, dynamic> toJson() => {
        'orientation': serializeDeviceOrientation(orientation),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceOrientationChangedEvent &&
          runtimeType == other.runtimeType &&
          orientation == other.orientation;

  @override
  int get hashCode => orientation.hashCode;
}

/// The [DeviceTiltsChangedEvent] is fired every time the user changes the
/// horizontal or vertical tilts of the device.
class DeviceTiltsChangedEvent extends DeviceEvent {
  /// The new horizontal tilt of the device
  final double horizontalTilt;

  /// The new vertical tilt of the device
  final double verticalTilt;

  /// Indicates if the horizontal tilt is available on a device
  final bool isHorizontalTiltAvailable;

  /// Indicates if the vertical tilt is available on a device
  final bool isVerticalTiltAvailable;

  /// The mode of the picture taking
  final TakePictureMode mode;

  /// The rotation angle of the image
  final double targetImageRotation;

  /// The angle of locked orientation
  final int lockedCaptureAngle;

  /// A device orientation angle
  final int deviceOrientationAngle;

  /// Build a new tilts changed event.
  DeviceTiltsChangedEvent({
    required this.horizontalTilt,
    required this.verticalTilt,
    required this.isHorizontalTiltAvailable,
    required this.isVerticalTiltAvailable,
    required this.mode,
    required this.targetImageRotation,
    required this.deviceOrientationAngle,
    required this.lockedCaptureAngle,
  });

  /// Converts the supplied [Map] to an instance of the [DeviceTiltsChangedEvent]
  /// class.
  DeviceTiltsChangedEvent.fromJson(Map<dynamic, dynamic> json)
      : verticalTilt = json['verticalTilt'],
        horizontalTilt = json['horizontalTilt'],
        isHorizontalTiltAvailable = json['isHorizontalTiltAvailable'],
        isVerticalTiltAvailable = json['isVerticalTiltAvailable'],
        targetImageRotation = json['targetImageRotation'],
        deviceOrientationAngle =
            int.tryParse('${json['deviceOrientationAngle']}') ?? 0,
        lockedCaptureAngle =
            int.tryParse('${json['lockedCaptureAngle']}') ?? -1,
        mode = (json['mode'] as String).toTakePictureMode;

  /// Converts the [DeviceOrientationChangedEvent] instance into a [Map] instance that
  /// can be serialized to JSON.
  Map<String, dynamic> toJson() => {
        'verticalTilt': verticalTilt,
        'horizontalTilt': horizontalTilt,
        'isHorizontalTiltAvailable': isHorizontalTiltAvailable,
        'isVerticalTiltAvailable': isVerticalTiltAvailable,
        'targetImageRotation': targetImageRotation,
        'deviceOrientationAngle': deviceOrientationAngle,
        'lockedCaptureAngle': lockedCaptureAngle,
        'mode': mode.toStringValue,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceTiltsChangedEvent &&
          runtimeType == other.runtimeType &&
          horizontalTilt == other.horizontalTilt &&
          verticalTilt == other.verticalTilt &&
          isHorizontalTiltAvailable == other.isHorizontalTiltAvailable &&
          isVerticalTiltAvailable == other.isVerticalTiltAvailable &&
          mode == other.mode &&
          targetImageRotation == other.targetImageRotation &&
          lockedCaptureAngle == other.lockedCaptureAngle &&
          deviceOrientationAngle == other.deviceOrientationAngle;

  @override
  int get hashCode =>
      horizontalTilt.hashCode ^
      verticalTilt.hashCode ^
      isHorizontalTiltAvailable.hashCode ^
      isVerticalTiltAvailable.hashCode ^
      mode.hashCode ^
      targetImageRotation.hashCode ^
      lockedCaptureAngle.hashCode ^
      deviceOrientationAngle.hashCode;
}
