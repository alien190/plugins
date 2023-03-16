/// CameraBarcode
class CameraBarcode {
  /// text
  final String text;

  /// format
  final String format;

  /// errorDescription;
  final String? errorDescription;

  /// constructor
  CameraBarcode({
    required this.text,
    required this.format,
    required this.errorDescription,
  });

  /// fromJson
  CameraBarcode.fromJson(Map<dynamic, dynamic> json)
      : text = json['text'],
        format = json['format'],
        errorDescription = json['errorDescription'];

  @override
  String toString() {
    return 'CameraBarcode{text: $text, format: $format, errorDescription: $errorDescription}';
  }
}
