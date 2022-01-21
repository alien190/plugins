import 'dart:math';
import 'dart:ui';

import 'package:camera/src/camera_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_device_tilts.dart';

/// Shows device tilts
class CameraTilts extends StatelessWidget {
  final CameraController _cameraController;
  final int? _horizontalTiltThreshold;
  final int? _verticalTiltThreshold;

  /// Default constructor
  const CameraTilts({
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
      stream: _cameraController.getDeviceTilts(),
      builder: (_, AsyncSnapshot<CameraDeviceTilts> snapshot) {
        final CameraDeviceTilts? deviceTilts = snapshot.data;
        if (snapshot.hasData && deviceTilts != null) {
          return _AnimatedCameraTilts(
            deviceTilts: deviceTilts,
            horizontalTiltThreshold: _horizontalTiltThreshold,
            verticalTiltThreshold: _verticalTiltThreshold,
          );
        }
        return Container();
      },
    );
  }
}

class _AnimatedCameraTilts extends StatefulWidget {
  final CameraDeviceTilts deviceTilts;
  final int? horizontalTiltThreshold;
  final int? verticalTiltThreshold;

  const _AnimatedCameraTilts({
    Key? key,
    required this.deviceTilts,
    this.horizontalTiltThreshold,
    this.verticalTiltThreshold,
  }) : super(key: key);

  @override
  _AnimatedCameraTiltsState createState() => _AnimatedCameraTiltsState(
        deviceTilts: deviceTilts,
        verticalTiltThreshold: verticalTiltThreshold,
        horizontalTiltThreshold: horizontalTiltThreshold,
      );
}

class _AnimatedCameraTiltsState extends State<_AnimatedCameraTilts>
    with SingleTickerProviderStateMixin {
  late CameraDeviceTilts _deviceTilts;
  int? _horizontalTiltThreshold;
  int? _verticalTiltThreshold;
  late final AnimationController _controller;
  late Animation<int> _orientationAnimation;

  _AnimatedCameraTiltsState({
    required CameraDeviceTilts deviceTilts,
    int? horizontalTiltThreshold,
    int? verticalTiltThreshold,
  })  : _deviceTilts = deviceTilts,
        _horizontalTiltThreshold = horizontalTiltThreshold,
        _verticalTiltThreshold = verticalTiltThreshold;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );

    _orientationAnimation = IntTween(
      begin: 0,
      end: _deviceTilts.deviceOrientation.grad,
    ).animate(_controller);

    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedCameraTilts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.deviceTilts != _deviceTilts ||
        widget.verticalTiltThreshold != _verticalTiltThreshold ||
        widget.verticalTiltThreshold != _verticalTiltThreshold) {
      if (widget.deviceTilts.deviceOrientation.grad !=
          _orientationAnimation.value) {
        if (_controller.isAnimating) {
          _controller.stop();
        }
        _orientationAnimation = IntTween(
          begin: _orientationAnimation.value,
          end: widget.deviceTilts.deviceOrientation.grad,
        ).animate(_controller);
        _controller.forward(from: 0);
      }
      _verticalTiltThreshold = widget.verticalTiltThreshold;
      _horizontalTiltThreshold = widget.horizontalTiltThreshold;
      _deviceTilts = widget.deviceTilts;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _orientationAnimation,
      builder: (_, __) {
        return CustomPaint(
          painter: _CameraTiltsPainter(
            deviceTilts: _deviceTilts,
            horizontalTiltThreshold: _horizontalTiltThreshold,
            verticalTiltThreshold: _verticalTiltThreshold,
            deviceOrientationGrad: _orientationAnimation.value,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _CameraTiltsPainter extends CustomPainter {
  static const Color _lineColor = Color.fromARGB(255, 255, 255, 255);
  static const IconData _horizontalAlertIcon = Icons.error;
  static final Paint _horizontalTiltLinePaint = Paint()
    ..color = _lineColor
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  static final Paint _verticalTiltLinePaint = Paint()
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  late final int _horizontalTilt;
  late final double _verticalTilt;
  late final double _horizontalTiltRad;
  late final int _horizontalTiltToPrint;
  late final CameraDeviceTilts _deviceTilts;
  late final int _horizontalTiltThreshold;
  late final int _verticalTiltThreshold;
  late final int _deviceOrientationGrad;
  late final bool _isHorizontalTiltVisible;
  late final bool _isVerticalTiltVisible;

  _CameraTiltsPainter({
    required CameraDeviceTilts deviceTilts,
    int? horizontalTiltThreshold,
    int? verticalTiltThreshold,
    int? deviceOrientationGrad,
  }) {
    _isHorizontalTiltVisible = deviceTilts.horizontalTilt != -1;

    _isVerticalTiltVisible = deviceTilts.verticalTilt != 0;

    _deviceTilts = deviceTilts;

    _horizontalTiltThreshold =
        horizontalTiltThreshold != null && horizontalTiltThreshold > 0
            ? horizontalTiltThreshold
            : 5;

    _verticalTiltThreshold =
        verticalTiltThreshold != null && verticalTiltThreshold > 0
            ? verticalTiltThreshold
            : 5;

    _deviceOrientationGrad = deviceOrientationGrad ?? 0;

    _horizontalTilt =
        (deviceTilts.horizontalTilt + _deviceOrientationGrad) % 360;

    _horizontalTiltRad = _horizontalTilt * pi / 180;

    _horizontalTiltToPrint =
        _horizontalTilt < 90 ? _horizontalTilt : 360 - _horizontalTilt;

    _verticalTilt = deviceTilts.verticalTilt - 90;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double lineLength = (size.width / 3) * 0.8;
    final Offset centreOffset = Offset(size.width / 2, size.height / 2);
    if (_isVerticalTiltVisible) {
      _paintVerticalTiltLine(
        canvas: canvas,
        centreOffset: centreOffset,
        lineLength: lineLength,
      );
    }
    if (_isHorizontalTiltVisible) {
      _paintHorizontalTiltDegree(
        size: size,
        canvas: canvas,
      );
      _paintHorizontalTiltLine(
        canvas: canvas,
        centreOffset: centreOffset,
        lineLength: lineLength,
      );
    }
  }

  void _paintHorizontalTiltLine({
    required Canvas canvas,
    required double lineLength,
    required Offset centreOffset,
  }) {
    final double deltaX = 0.5 * lineLength * sin(pi / 2 - _horizontalTiltRad);
    final double deltaY = 0.5 * lineLength * sin(_horizontalTiltRad);
    final Offset leftPoint =
        Offset(centreOffset.dx + deltaX, centreOffset.dy - deltaY);
    final Offset rightPoint =
        Offset(centreOffset.dx - deltaX, centreOffset.dy + deltaY);
    canvas.drawLine(leftPoint, rightPoint, _horizontalTiltLinePaint);
  }

  void _paintHorizontalTiltDegree({
    required Size size,
    required Canvas canvas,
  }) {
    final TextSpan textSpan = _getHorizontalDegreeTextSpan();
    final TextPainter textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final double xCenter = (size.width - textPainter.width) / 2;
    final double yCenter = (size.height - textPainter.height * 3) / 2;
    final Offset offset = Offset(xCenter, yCenter);
    textPainter.paint(canvas, offset);
  }

  TextSpan _getHorizontalDegreeTextSpan() {
    if (_horizontalTiltToPrint <= _horizontalTiltThreshold &&
        _deviceOrientationGrad % 90 == 0) {
      return TextSpan(
        text: '$_horizontalTiltToPrint\u{00B0}',
        style: TextStyle(
          fontSize: 18,
          color: Colors.white,
        ),
      );
    } else {
      return TextSpan(
        text: String.fromCharCode(_horizontalAlertIcon.codePoint),
        style: TextStyle(
          fontSize: 22,
          color: Colors.red,
          fontFamily: _horizontalAlertIcon.fontFamily,
        ),
      );
    }
  }

  void _paintVerticalTiltLine({
    required Canvas canvas,
    required double lineLength,
    required Offset centreOffset,
  }) {
    final double verticalTiltToPlot =
        _verticalTilt >= -_verticalTiltThreshold * 2 &&
                _verticalTilt <= _verticalTiltThreshold * 2
            ? _verticalTilt
            : _verticalTiltThreshold * 2 * _verticalTilt.sign;

    final Color lineColor = verticalTiltToPlot.abs() <= _verticalTiltThreshold
        ? Colors.orangeAccent
        : Colors.red;

    _verticalTiltLinePaint.color = lineColor;

    final double verticalOffset = verticalTiltToPlot * 2;

    final Offset leftPoint = Offset(
        centreOffset.dx - lineLength / 2, centreOffset.dy + verticalOffset);
    final Offset rightPoint = Offset(
        centreOffset.dx + lineLength / 2, centreOffset.dy + verticalOffset);
    canvas.drawLine(
      leftPoint,
      rightPoint,
      _verticalTiltLinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CameraTiltsPainter oldDelegate) =>
      oldDelegate._deviceTilts != _deviceTilts ||
      oldDelegate._deviceOrientationGrad != _deviceOrientationGrad ||
      oldDelegate._horizontalTiltThreshold != _horizontalTiltThreshold ||
      oldDelegate._verticalTiltThreshold != _verticalTiltThreshold;
}

extension _DeviceOrientationToGradExtension on DeviceOrientation? {
  int get grad {
    switch (this) {
      case DeviceOrientation.portraitUp:
        return 0;
      case DeviceOrientation.landscapeRight:
        return -90;
      case DeviceOrientation.portraitDown:
        return 180;
      case DeviceOrientation.landscapeLeft:
        return 90;
      case null:
        return 0;
    }
  }
}
