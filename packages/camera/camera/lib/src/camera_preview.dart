// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:camera/camera.dart';
import 'package:camera/src/camera_grid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'camera_spash.dart';

/// A widget showing a live camera preview.
class CameraPreview extends StatelessWidget {
  /// Creates a preview widget for the given camera controller.
  const CameraPreview(this.controller, {this.child});

  /// The controller for the camera that the preview is shown for.
  final CameraController controller;

  /// A widget to overlay on top of the camera preview
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, child) {
        return controller.value.isInitialized
            ? AnimatedContainer(
                duration: Duration(milliseconds: 200),
                transformAlignment: Alignment.center,
                transform: controller.value.isTakingPicture
                    ? (Matrix4.identity()..scale(0.95))
                    : Matrix4.identity(),
                child: AspectRatio(
                  aspectRatio: _isLandscape()
                      ? controller.value.aspectRatio
                      : (1 / controller.value.aspectRatio),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _wrapInRotatedBox(child: controller.buildPreview()),
                      child ?? Container(),
                      CameraGrid(),
                      CameraSplash(isShown: !controller.value.isTakingPicture),
                      if (controller.value.isTakingPicture)
                        Container(color: Color.fromARGB(100, 0, 0, 0)),
                      if (controller.value.isTakingPicture)
                        Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
              )
            : Container();
      },
      child: child,
    );
  }

  Widget _wrapInRotatedBox({required Widget child}) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return child;
    }

    return RotatedBox(
      quarterTurns: _getQuarterTurns(),
      child: child,
    );
  }

  bool _isLandscape() {
    return [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        .contains(_getApplicableOrientation());
  }

  int _getQuarterTurns() {
    Map<DeviceOrientation, int> turns = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeRight: 1,
      DeviceOrientation.portraitDown: 2,
      DeviceOrientation.landscapeLeft: 3,
    };
    return turns[_getApplicableOrientation()]!;
  }

  DeviceOrientation _getApplicableOrientation() {
    return controller.value.isRecordingVideo
        ? controller.value.recordingOrientation!
        : (controller.value.previewPauseOrientation ??
            controller.value.lockedCaptureOrientation ??
            controller.value.deviceOrientation);
  }
}
