import 'dart:ui';

import 'package:camera/src/camera_controller.dart';
import 'package:flutter/material.dart';

import 'camera_device_tilts.dart';

/// Shows device tilts
class CameraTilts extends StatelessWidget {
  final CameraController _cameraController;

  /// Default constructor
  const CameraTilts({
    Key? key,
    required CameraController cameraController,
  })  : _cameraController = cameraController,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _cameraController.getDeviceTilts(),
      builder: (_, AsyncSnapshot<CameraDeviceTilts> snapshot) {
        final CameraDeviceTilts? deviceTilts = snapshot.data;
        if (snapshot.hasData && deviceTilts != null) {
          return CustomPaint(
            painter: _CameraTiltsPainter(
              horizontalTilt: deviceTilts.horizontalTilt,
            ),
          );
        }
        return Container();
      },
    );
  }
}

class _CameraTiltsPainter extends CustomPainter {
  static const Color _lineColor = Color.fromARGB(255, 255, 0, 0);
  final Paint _linePaint = Paint()
    ..color = _lineColor
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  final int _horizontalTilt;

  _CameraTiltsPainter({required int horizontalTilt})
      : _horizontalTilt = horizontalTilt;

  @override
  void paint(Canvas canvas, Size size) {
    final TextSpan textSpan = TextSpan(
      text: 'tilt:$_horizontalTilt',
      style: TextStyle(
        fontSize: 20,
        color: Colors.red,
      ),
    );
    final TextPainter textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width / 2, size.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CameraTiltsPainter oldDelegate) =>
      oldDelegate._horizontalTilt != _horizontalTilt;
}
