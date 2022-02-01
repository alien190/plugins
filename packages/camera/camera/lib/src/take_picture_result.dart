import 'package:camera/camera.dart';
import 'package:camera/src/take_picture_mode.dart';

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

  /// The mode of the picure taking
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
