/// The mode of taking photo
enum TakePictureMode {
  /// Unknown when a device doesn't has sensors to determ the vertical position
  unknownShot,

  /// Normal when a device has verticlal position
  normalShot,

  /// Overhead when a device has horizontal position
  overheadShot,
}