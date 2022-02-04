/// The mode of taking photo
enum TakePictureMode {
  /// Unknown when a device doesn't has sensors to determ the vertical position
  unknownShot,

  /// Normal when a device has verticlal position
  normalShot,

  /// Overhead when a device has horizontal position
  overheadShot,
}

/// Creates TakePictureMode from string value
extension TakePictureModeFromString on String {
  /// Creates TakePictureMode from string value
  TakePictureMode get toTakePictureMode {
    switch (this) {
      case 'unknownShot':
        return TakePictureMode.unknownShot;
      case 'normalShot':
        return TakePictureMode.normalShot;
      case 'overheadShot':
        return TakePictureMode.overheadShot;
      default:
        return TakePictureMode.unknownShot;
    }
  }
}

/// Creates TakePictureMode from string value
extension TakePictureModeToString on TakePictureMode {
  /// Creates TakePictureMode from string value
  String get toStringValue {
    switch (this) {
      case TakePictureMode.unknownShot:
        return 'unknownShot';
      case TakePictureMode.normalShot:
        return 'normalShot';
      case TakePictureMode.overheadShot:
        return 'overheadShot';
    }
  }
}
