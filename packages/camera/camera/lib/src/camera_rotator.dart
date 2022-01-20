import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../camera.dart';

/// Rotates the child widget according to locked and device's orientation
class CameraRotator extends StatelessWidget {
  static const Map<DeviceOrientation, int> _turns = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeRight: 3,
    DeviceOrientation.portraitDown: 2,
    DeviceOrientation.landscapeLeft: 1,
  };

  final Widget _child;
  final CameraController _controller;

  /// Default constructor
  const CameraRotator({
    Key? key,
    required Widget child,
    required CameraController controller,
  })  : _child = child,
        _controller = controller,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: _controller,
      builder: (context, value, child) =>
          _wrapInRotatedBox(child: child, value: value),
      child: _child,
    );
  }

  Widget _wrapInRotatedBox({
    required Widget? child,
    required CameraValue value,
  }) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return child ?? Container();
    }

    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      transform: Matrix4.rotationZ(pi / 2 * _getQuarterTurns(value: value)),
      transformAlignment: Alignment.center,
      child: child,
    );
  }

  // Widget _wrapInRotatedBox({
  //   required Widget? child,
  //   required CameraValue value,
  // }) {
  //   if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
  //     return child ?? Container();
  //   }
  //
  //   return RotatedBox(
  //     quarterTurns: _getQuarterTurns(value: value),
  //     child: child,
  //   );
  // }

  int _getQuarterTurns({required CameraValue value}) {
    return value.lockedCaptureOrientation == null
        ? 0
        : _turns[value.deviceOrientation]! -
            (_turns[value.lockedCaptureOrientation] ?? 0);
  }
}
