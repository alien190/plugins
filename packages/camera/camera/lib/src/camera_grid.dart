import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// Grid for the preview
class CameraGrid extends StatelessWidget {
  /// Default constructor
  const CameraGrid({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CameraGridPainter(),
    );
  }
}

class _CameraGridPainter extends CustomPainter {
  static const int _verticalLinesNumber = 2;
  static const int _horizontalLinesNumber = 2;

  static const Color _lineColor = Color.fromARGB(128, 255, 255, 255);
  final Paint _linePaint = Paint()
    ..color = _lineColor
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double horizontalStep = size.width / (_verticalLinesNumber + 1);
    final double verticalStep = size.height / (_horizontalLinesNumber + 1);

    for (int i = 1; i <= _verticalLinesNumber; i++) {
      canvas.drawLine(
        Offset(horizontalStep * i, 0),
        Offset(horizontalStep * i, size.height),
        _linePaint,
      );
    }

    for (int i = 1; i <= _horizontalLinesNumber; i++) {
      canvas.drawLine(
        Offset(0, verticalStep * i),
        Offset(size.width, verticalStep * i),
        _linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CameraGridPainter oldDelegate) => false;
}
