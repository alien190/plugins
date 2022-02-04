import 'package:camera_platform_interface/camera_platform_interface.dart';

import 'take_picture_mode.dart';

/// The result of a picture taking
class TakePictureResult {
  /// The result file
  final XFile file;

  /// Indicates if the vertical tilt's calculation is available for the device
  final bool isVerticalTiltAvailable;

  /// Indicates if the horizontal tilt's calculation is available for the device
  final bool isHorizontalTiltAvailable;

  /// The value of the vertical tilt
  final double verticalTilt;

  /// The value of the horizontal tilt
  final double horizontalTilt;

  /// The mode of the picture taking
  final TakePictureMode mode;

  /// Default constructor
  TakePictureResult({
    required this.file,
    required this.isVerticalTiltAvailable,
    required this.isHorizontalTiltAvailable,
    required this.verticalTilt,
    required this.horizontalTilt,
    required this.mode,
  });

  /// Converts the supplied [Map] to an instance of the [TakePictureResult]
  /// class.
  TakePictureResult.fromJson(Map<dynamic, dynamic> json)
      : verticalTilt = json['verticalTilt'],
        horizontalTilt = json['horizontalTilt'],
        isHorizontalTiltAvailable = json['isHorizontalTiltAvailable'],
        isVerticalTiltAvailable = json['isVerticalTiltAvailable'],
        file = XFile(json['resultPath']),
        mode = (json['mode'] as String).toTakePictureMode;

  /// Converts the [TakePictureResult] instance into a [Map] instance that
  /// can be serialized to JSON.
  Map<String, dynamic> toJson() =>
      {
        'verticalTilt': verticalTilt,
        'horizontalTilt': horizontalTilt,
        'isHorizontalTiltAvailable': isHorizontalTiltAvailable,
        'isVerticalTiltAvailable': isVerticalTiltAvailable,
        'resultPath': file.path,
        'mode': mode.toStringValue,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is TakePictureResult &&
              runtimeType == other.runtimeType &&
              file == other.file &&
              isVerticalTiltAvailable == other.isVerticalTiltAvailable &&
              isHorizontalTiltAvailable == other.isHorizontalTiltAvailable &&
              verticalTilt == other.verticalTilt &&
              horizontalTilt == other.horizontalTilt &&
              mode == other.mode;

  @override
  int get hashCode =>
      file.hashCode ^
      isVerticalTiltAvailable.hashCode ^
      isHorizontalTiltAvailable.hashCode ^
      verticalTilt.hashCode ^
      horizontalTilt.hashCode ^
      mode.hashCode;

  @override
  String toString() {
    return 'TakePictureResult{file: $file, isVerticalTiltAvailable: $isVerticalTiltAvailable, isHorizontalTiltAvailable: $isHorizontalTiltAvailable, verticalTilt: $verticalTilt, horizontalTilt: $horizontalTilt, mode: $mode}';
  }
}
