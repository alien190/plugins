import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../camera.dart';
import 'camera_device_tilts.dart';

/// Rotates the child widget according to locked and device's orientation
class CameraRotater extends StatelessWidget {
  final Widget _child;
  final CameraController _controller;
  final bool _isAnimated;

  /// Default constructor
  const CameraRotater({
    Key? key,
    required Widget child,
    required CameraController controller,
    bool? isAnimated,
  })  : _child = child,
        _controller = controller,
        _isAnimated = isAnimated ?? false,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CameraDeviceTilts>(
        stream: _controller.deviceTilts,
        builder: (context, AsyncSnapshot<CameraDeviceTilts> snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return _CameraRotater(
              child: _child,
              targetImageRotation: snapshot.data!.targetImageRotation,
              isAnimated: _isAnimated,
            );
          }
          return Container();
        });
  }
}

class _CameraRotater extends StatefulWidget {
  final double targetImageRotation;
  final Widget? child;
  final bool isAnimated;

  _CameraRotater({
    required this.targetImageRotation,
    required this.child,
    required this.isAnimated,
    Key? key,
  }) : super(key: key);

  @override
  _CameraRotaterState createState() => _CameraRotaterState(
        targetImageRotation: targetImageRotation,
        isAnimated: isAnimated,
      );
}

class _CameraRotaterState extends State<_CameraRotater>
    with SingleTickerProviderStateMixin {
  double _lastTargetImageRotation;
  bool _isAnimated;
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  _CameraRotaterState({
    required double targetImageRotation,
    required bool isAnimated,
  })  : _lastTargetImageRotation = targetImageRotation,
        _isAnimated = isAnimated;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: Duration(milliseconds: 3000));
    _rotationAnimation = Tween<double>(
            begin: _lastTargetImageRotation, end: _lastTargetImageRotation)
        .animate(_controller);
  }

  @override
  void didUpdateWidget(covariant _CameraRotater oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetImageRotation != _lastTargetImageRotation) {
      _updateTransform(widget.targetImageRotation);
    }
    if (widget.isAnimated != _isAnimated) {
      _isAnimated = widget.isAnimated;
      if (mounted) setState(() {});
    }
  }

  void _updateTransform(double targetImageRotation) {
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
    return _isAnimated
        ? AnimatedBuilder(
            animation: _rotationAnimation,
            builder: (_, Widget? child) => Container(
              transform: _rotationAnimation.value.transform,
              transformAlignment: Alignment.center,
              child: child,
            ),
            child: widget.child,
          )
        : Container(
            transform: _lastTargetImageRotation.transform,
            transformAlignment: Alignment.center,
            child: widget.child,
          );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

extension _TransformExtension on double {
  Matrix4 get transform => Matrix4.rotationZ(-this * pi / 180);
}
