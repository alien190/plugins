import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../camera.dart';
import 'camera_device_tilts.dart';

/// Rotates the child widget according to locked and device's orientation
class CameraRotator extends StatelessWidget {
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
    return StreamBuilder<CameraDeviceTilts>(
        stream: _controller.getDeviceTilts(),
        builder: (context, AsyncSnapshot<CameraDeviceTilts> snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return _wrapInRotatedBox(
              child: _child,
              deviceTilts: snapshot.data!,
            );
          }
          return _child;
        });
  }

  Widget _wrapInRotatedBox({
    required Widget? child,
    required CameraDeviceTilts deviceTilts,
  }) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      transform: Matrix4.rotationZ(pi / 2 * deviceTilts.targetImageRotation),
      transformAlignment: Alignment.center,
      child: child,
    );
  }
}
