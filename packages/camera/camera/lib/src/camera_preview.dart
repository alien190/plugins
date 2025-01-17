// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:camera/camera.dart';
import 'package:camera/src/camera_grid.dart';
import 'package:camera/src/camera_rotater.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_take_picture_animation.dart';
import 'camera_tilts.dart';

/// A widget showing a live camera preview.
class CameraPreview extends StatelessWidget {
  static const Map<DeviceOrientation, int> _turns = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeRight: 1,
    DeviceOrientation.portraitDown: 2,
    DeviceOrientation.landscapeLeft: 3,
  };

  /// Creates a preview widget for the given camera controller.
  const CameraPreview(
    this.controller, {
    this.child,
    this.normalHorizontalTiltThreshold,
    this.normalVerticalTiltThreshold,
    this.overheadHorizontalTiltThreshold,
    this.overheadVerticalTiltThreshold,
    this.isGridVisible = true,
    this.isTiltsIndicatorVisible = true,
  });

  /// The controller for the camera that the preview is shown for.
  final CameraController controller;

  /// A widget to overlay on top of the camera preview
  final Widget? child;

  /// Horizontal tilt threshold to show warning for normal shot mode
  final int? normalHorizontalTiltThreshold;

  /// Vertical tilt threshold to show warning for normal shot mode
  final int? normalVerticalTiltThreshold;

  /// Horizontal tilt threshold to show warning for overhead shot mode
  final int? overheadHorizontalTiltThreshold;

  /// Vertical tilt threshold to show warning for overhead shot mode
  final int? overheadVerticalTiltThreshold;

  /// Show or doesn't the grid overlay
  final bool isGridVisible;

  /// Show or doesn't the tilts indicator
  final bool isTiltsIndicatorVisible;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, child) {
        return controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _isLandscape()
                    ? controller.value.aspectRatio
                    : (1 / controller.value.aspectRatio),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _wrapPreviewInRotatedBox(
                      child: controller.buildPreview(),
                    ),
                    if (isGridVisible) CameraGrid(),
                    if (isTiltsIndicatorVisible)
                      CameraTilts(
                        cameraController: controller,
                        normalHorizontalTiltThreshold:
                            normalHorizontalTiltThreshold,
                        normalVerticalTiltThreshold:
                            normalVerticalTiltThreshold,
                        overheadHorizontalTiltThreshold:
                            overheadHorizontalTiltThreshold,
                        overheadVerticalTiltThreshold:
                            overheadVerticalTiltThreshold,
                      ),
                    if (controller.value.isTakingPicture)
                      CameraRotater(
                        child: CameraTakePictureAnimation(),
                        controller: controller,
                      ),
                    child ?? Container(),
                  ],
                ),
              )
            : Container();
      },
      child: child,
    );
  }

  Widget _wrapPreviewInRotatedBox({
    required Widget child,
  }) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return child;
    }

    return RotatedBox(
      quarterTurns: _getQuarterTurnsForPreview(),
      child: child,
    );
  }

  bool _isLandscape() {
    return [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        .contains(_getApplicableOrientation());
  }

  int _getQuarterTurnsForPreview() {
    return _turns[_getApplicableOrientation()]!;
  }

  DeviceOrientation _getApplicableOrientation() {
    return controller.value.isRecordingVideo
        ? controller.value.recordingOrientation!
        : (controller.value.previewPauseOrientation ??
            controller.value.lockedCaptureOrientation ??
            controller.value.deviceOrientation);
  }
}
