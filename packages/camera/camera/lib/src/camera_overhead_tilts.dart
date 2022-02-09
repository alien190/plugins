import 'dart:math';
import 'dart:ui';

import 'package:camera/src/camera_controller.dart';
import 'package:flutter/material.dart';

import 'camera_device_tilts.dart';

/// Shows device tilts
class CameraOverheadTilts extends StatelessWidget {
  final CameraController _cameraController;
  final int? _horizontalTiltThreshold;
  final int? _verticalTiltThreshold;

  /// Default constructor
  const CameraOverheadTilts({
    Key? key,
    required CameraController cameraController,
    int? horizontalTiltThreshold,
    int? verticalTiltThreshold,
  })  : _cameraController = cameraController,
        _horizontalTiltThreshold = horizontalTiltThreshold,
        _verticalTiltThreshold = verticalTiltThreshold,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _cameraController.deviceTilts,
      builder: (_, AsyncSnapshot<CameraDeviceTilts> snapshot) {
        final CameraDeviceTilts? deviceTilts = snapshot.data;
        if (snapshot.hasData &&
            deviceTilts != null &&
            (deviceTilts.isVerticalTiltAvailable &&
                deviceTilts.isHorizontalTiltAvailable)) {
          return CustomPaint(
            painter: _CameraOverheadTiltsPainter(
              deviceTilts: deviceTilts,
              horizontalTiltThreshold: _horizontalTiltThreshold,
              verticalTiltThreshold: _verticalTiltThreshold,
            ),
          );
        }
        return Container();
      },
    );
  }
}

class _CameraOverheadTiltsPainter extends CustomPainter {
  static final Paint _centralCrossPaint = Paint()
    ..color = Color.fromARGB(255, 255, 255, 255)
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  static final Paint _tiltsCrossPaint = Paint()
    ..color = Colors.orangeAccent
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  late final double _horizontalTilt;
  late final double _verticalTilt;

  // late final double _horizontalTiltRad;
  // late final int _horizontalTiltToPrint;
  // late final CameraDeviceTilts _deviceTilts;
  late final int _horizontalTiltThreshold;
  late final int _verticalTiltThreshold;

  // late final bool _isHorizontalTiltVisible;
  // late final bool _isVerticalTiltVisible;
  // late final bool _isAnimated;
  // late final double _animatedRotationAngleRad;
  // late final double _targetRotationRad;

  _CameraOverheadTiltsPainter({
    required CameraDeviceTilts deviceTilts,
    int? horizontalTiltThreshold,
    int? verticalTiltThreshold,
  }) {
    _horizontalTiltThreshold =
        horizontalTiltThreshold != null && horizontalTiltThreshold > 0
            ? horizontalTiltThreshold
            : 5;

    _verticalTiltThreshold =
        verticalTiltThreshold != null && verticalTiltThreshold > 0
            ? verticalTiltThreshold
            : 5;

    _horizontalTilt = deviceTilts.horizontalTilt;

    _verticalTilt = deviceTilts.verticalTilt;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double lineLength = (size.width / 3) * 0.3;
    final Offset centreOffset = Offset(size.width / 2, size.height / 2);

    final double verticalTiltToPlot =
        _verticalTilt >= -_verticalTiltThreshold * 2 &&
                _verticalTilt <= _verticalTiltThreshold * 2
            ? _verticalTilt
            : _verticalTiltThreshold * 2 * _verticalTilt.sign;

    final double horizontalTiltToPlot =
        _horizontalTilt >= -_horizontalTiltThreshold * 2 &&
                _horizontalTilt <= _horizontalTiltThreshold * 2
            ? _horizontalTilt
            : _horizontalTiltThreshold * 2 * _horizontalTilt.sign;

    final Offset tiltsOffset = Offset(
      size.width / 2 + horizontalTiltToPlot * lineLength,
      size.height / 2 + verticalTiltToPlot * lineLength,
    );

    _paintCross(
      canvas: canvas,
      centreOffset: tiltsOffset,
      paint: _tiltsCrossPaint,
      lineLength: lineLength,
    );

    _paintCross(
      canvas: canvas,
      centreOffset: centreOffset,
      paint: _centralCrossPaint,
      lineLength: lineLength,
    );
  }

  void _paintCross({
    required Canvas canvas,
    required Offset centreOffset,
    required Paint paint,
    required double lineLength,
  }) {
    final Offset leftPoint =
        Offset(centreOffset.dx - lineLength / 2, centreOffset.dy);
    final Offset rightPoint =
        Offset(centreOffset.dx + lineLength / 2, centreOffset.dy);
    canvas.drawLine(leftPoint, rightPoint, paint);
    final Offset topPoint =
        Offset(centreOffset.dx, centreOffset.dy + lineLength / 2);
    final Offset bottomPoint =
        Offset(centreOffset.dx, centreOffset.dy - lineLength / 2);
    canvas.drawLine(topPoint, bottomPoint, paint);
    canvas.drawCircle(centreOffset, 2, paint);
  }

  @override
  bool shouldRepaint(covariant _CameraOverheadTiltsPainter oldDelegate) =>
      oldDelegate._verticalTilt != _verticalTilt ||
      oldDelegate._horizontalTilt != _horizontalTilt ||
      oldDelegate._horizontalTiltThreshold != _horizontalTiltThreshold ||
      oldDelegate._verticalTiltThreshold != _verticalTiltThreshold;
}
