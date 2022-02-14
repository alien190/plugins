import 'dart:math';
import 'dart:ui';

import 'package:camera/src/camera_controller.dart';
import 'package:flutter/material.dart';

import 'camera_device_tilts.dart';

/// Shows device tilts
class CameraNormalTilts extends StatelessWidget {
  final CameraController _cameraController;
  final int? _horizontalTiltThreshold;
  final int? _verticalTiltThreshold;

  /// Default constructor
  const CameraNormalTilts({
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
            (deviceTilts.isVerticalTiltAvailable ||
                deviceTilts.isHorizontalTiltAvailable)) {
          return _AnimatedCameraNormalTilts(
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

class _AnimatedCameraNormalTilts extends StatefulWidget {
  final CameraDeviceTilts deviceTilts;
  final int? horizontalTiltThreshold;
  final int? verticalTiltThreshold;

  const _AnimatedCameraNormalTilts({
    Key? key,
    required this.deviceTilts,
    this.horizontalTiltThreshold,
    this.verticalTiltThreshold,
  }) : super(key: key);

  @override
  _AnimatedCameraNormalTiltsState createState() =>
      _AnimatedCameraNormalTiltsState(
        deviceTilts: deviceTilts,
        verticalTiltThreshold: verticalTiltThreshold,
        horizontalTiltThreshold: horizontalTiltThreshold,
      );
}

class _AnimatedCameraNormalTiltsState extends State<_AnimatedCameraNormalTilts>
    with SingleTickerProviderStateMixin {
  late CameraDeviceTilts _deviceTilts;
  int? _horizontalTiltThreshold;
  int? _verticalTiltThreshold;
  late final AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late double _lastTargetImageRotation;

  _AnimatedCameraNormalTiltsState({
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

    final double initialRotation =
        _isRotationShouldBeAnimated ? _deviceTilts.targetImageRotation : 0;
    _rotationAnimation = Tween<double>(
      begin: initialRotation,
      end: initialRotation,
    ).animate(_controller);

    _lastTargetImageRotation = _deviceTilts.targetImageRotation;

    _controller.forward();
  }

  bool get _isRotationShouldBeAnimated =>
      widget.deviceTilts.lockedCaptureAngle >= 0 ||
      (widget.deviceTilts.lockedCaptureAngle < 0 &&
          !widget.deviceTilts.isUIRotationEqualAccRotation);

  @override
  void didUpdateWidget(covariant _AnimatedCameraNormalTilts oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_isRotationShouldBeAnimated) {
      if (widget.deviceTilts.targetImageRotation != _lastTargetImageRotation) {
        _updateAnimation(widget.deviceTilts.targetImageRotation);
      }
    }
    else if(_lastTargetImageRotation!=0){
      _updateAnimation(0);
    }
    //else if(_deviceTilts.lockedCaptureAngle < 0) {
    //  _updateAnimation(0);
    //}
    if (widget.deviceTilts != _deviceTilts ||
        widget.verticalTiltThreshold != _verticalTiltThreshold ||
        widget.verticalTiltThreshold != _verticalTiltThreshold) {
      _verticalTiltThreshold = widget.verticalTiltThreshold;
      _horizontalTiltThreshold = widget.horizontalTiltThreshold;
      _deviceTilts = widget.deviceTilts;
      if (mounted) setState(() {});
    }
  }

  void _updateAnimation(double targetImageRotation) {
    if (_controller.isAnimating) {
      _controller.stop();
    }
    if (_lastTargetImageRotation == 270 && targetImageRotation == 0) {
      _rotationAnimation = Tween<double>(
        begin: _rotationAnimation.value >= 0
            ? _rotationAnimation.value - 360
            : _rotationAnimation.value,
        end: targetImageRotation,
      ).animate(_controller);
    } else if (_lastTargetImageRotation == 0 && targetImageRotation == 270) {
      _rotationAnimation = Tween<double>(
        begin: _rotationAnimation.value,
        end: -90,
      ).animate(_controller);
    } else if (_lastTargetImageRotation == 270 && targetImageRotation == 180) {
      _rotationAnimation = Tween<double>(
        begin: _rotationAnimation.value >= 0
            ? _rotationAnimation.value
            : 360 + _rotationAnimation.value,
        end: targetImageRotation,
      ).animate(_controller);
    } else {
      _rotationAnimation = Tween<double>(
              begin: _rotationAnimation.value, end: targetImageRotation)
          .animate(_controller);
    }
    _controller.forward(from: 0);

    _lastTargetImageRotation = targetImageRotation;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rotationAnimation,
      builder: (_, __) {
        return CustomPaint(
          painter: _CameraNormalTiltsPainter(
            deviceTilts: _deviceTilts,
            horizontalTiltThreshold: _horizontalTiltThreshold,
            verticalTiltThreshold: _verticalTiltThreshold,
            animatedRotationAngle: _rotationAnimation.value,
            isAnimated: _controller.isAnimating,
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

class _CameraNormalTiltsPainter extends CustomPainter {
  static const Color _lineColor = Color.fromARGB(255, 255, 255, 255);
  static const IconData _horizontalAlertIcon = Icons.error;
  static final Paint _horizontalTiltLinePaint = Paint()
    ..color = _lineColor
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  static final Paint _verticalTiltLinePaint = Paint()
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  late final double _horizontalTilt;
  late final double _verticalTilt;
  late final double _horizontalTiltRad;
  late final int _horizontalTiltToPrint;
  late final CameraDeviceTilts _deviceTilts;
  late final int _horizontalTiltThreshold;
  late final int _verticalTiltThreshold;
  late final bool _isHorizontalTiltVisible;
  late final bool _isVerticalTiltVisible;
  late final bool _isAnimated;
  late final double _animatedRotationAngleRad;
  late final double _targetRotationRad;

  _CameraNormalTiltsPainter({
    required CameraDeviceTilts deviceTilts,
    required double animatedRotationAngle,
    int? horizontalTiltThreshold,
    int? verticalTiltThreshold,
    bool? isAnimated,
  }) {
    _animatedRotationAngleRad = animatedRotationAngle * pi / 180;

    _isAnimated = isAnimated ?? false;

    _targetRotationRad = deviceTilts.lockedCaptureAngle >= 0 ||
            (deviceTilts.lockedCaptureAngle < 0 &&
                !deviceTilts.isUIRotationEqualAccRotation)
        ? deviceTilts.targetImageRotation * pi / 180
        : 0;

    _isHorizontalTiltVisible = deviceTilts.isHorizontalTiltAvailable;

    _isVerticalTiltVisible = deviceTilts.isVerticalTiltAvailable;

    _deviceTilts = deviceTilts;

    _horizontalTiltThreshold =
        horizontalTiltThreshold != null && horizontalTiltThreshold > 0
            ? horizontalTiltThreshold
            : 5;

    _verticalTiltThreshold =
        verticalTiltThreshold != null && verticalTiltThreshold > 0
            ? verticalTiltThreshold
            : 5;

    _horizontalTilt = _deviceTilts.horizontalTilt;

    _horizontalTiltRad = _horizontalTilt * pi / 180;

    _horizontalTiltToPrint = _horizontalTilt.abs().toInt();

    _verticalTilt = deviceTilts.verticalTilt;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (_isHorizontalTiltVisible || _isVerticalTiltVisible) {
      final double lineLength = (size.width / 3) * 0.8;
      final Offset centreOffset = Offset(size.width / 2, size.height / 2);

      final double horizontalTiltDeltaX = 0.5 *
          lineLength *
          sin(pi / 2 + _horizontalTiltRad - _targetRotationRad);
      final double horizontalTiltDeltaY =
          0.5 * lineLength * sin(-_horizontalTiltRad + _targetRotationRad);

      if (_isVerticalTiltVisible) {
        _paintVerticalTiltLine(
          canvas: canvas,
          centreOffset: centreOffset,
          lineLength: lineLength,
          horizontalTiltDeltaX: horizontalTiltDeltaX,
          horizontalTiltDeltaY: horizontalTiltDeltaY,
        );
        if (!_isHorizontalTiltVisible) {
          _paintHorizontalTiltLine(
            canvas: canvas,
            centreOffset: centreOffset,
            deltaX: horizontalTiltDeltaX,
            deltaY: horizontalTiltDeltaY,
            lineLength: lineLength,
          );
        }
      }
      if (_isHorizontalTiltVisible) {
        _paintHorizontalTiltLine(
          canvas: canvas,
          centreOffset: centreOffset,
          deltaX: horizontalTiltDeltaX,
          deltaY: horizontalTiltDeltaY,
          lineLength: lineLength,
        );

        canvas.translate(centreOffset.dx, centreOffset.dy);
        canvas.rotate(-_animatedRotationAngleRad);
        canvas.translate(-centreOffset.dx, -centreOffset.dy);
        _paintHorizontalTiltDegree(
          size: size,
          canvas: canvas,
        );
      }
    }
  }

  void _paintHorizontalTiltLine({
    required Canvas canvas,
    required double lineLength,
    required Offset centreOffset,
    required double deltaX,
    required double deltaY,
  }) {
    final Offset leftPoint =
        Offset(centreOffset.dx + deltaX, centreOffset.dy - deltaY);
    final Offset rightPoint =
        Offset(centreOffset.dx - deltaX, centreOffset.dy + deltaY);

    canvas.drawLine(
      leftPoint,
      rightPoint,
      _horizontalTiltLinePaint,
    );
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
    if (_horizontalTiltToPrint <= _horizontalTiltThreshold && !_isAnimated) {
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
    required double horizontalTiltDeltaX,
    required double horizontalTiltDeltaY,
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

    final double verticalOffsetX =
        2 * verticalTiltToPlot * sin(_horizontalTiltRad - _targetRotationRad);
    final double verticalOffsetY = 2 *
        verticalTiltToPlot *
        sin(-pi / 2 - _horizontalTiltRad + _targetRotationRad);

    final Offset leftPoint = Offset(
      centreOffset.dx - horizontalTiltDeltaX + verticalOffsetX,
      centreOffset.dy + horizontalTiltDeltaY + verticalOffsetY,
    );

    final Offset rightPoint = Offset(
      centreOffset.dx + horizontalTiltDeltaX + verticalOffsetX,
      centreOffset.dy - horizontalTiltDeltaY + verticalOffsetY,
    );

    canvas.drawLine(
      leftPoint,
      rightPoint,
      _verticalTiltLinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CameraNormalTiltsPainter oldDelegate) =>
      oldDelegate._deviceTilts != _deviceTilts ||
      oldDelegate._horizontalTiltThreshold != _horizontalTiltThreshold ||
      oldDelegate._verticalTiltThreshold != _verticalTiltThreshold ||
      oldDelegate._animatedRotationAngleRad != _animatedRotationAngleRad;
}
