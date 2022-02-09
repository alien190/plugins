import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera/src/camera_device_tilts.dart';
import 'package:camera/src/camera_normal_tilts.dart';
import 'package:camera/src/camera_overhead_tilts.dart';
import 'package:flutter/material.dart';

/// Camera tilts widget
class CameraTilts extends StatefulWidget {
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
  _CameraTiltsState createState() => _CameraTiltsState(
        cameraController: _cameraController,
        horizontalTiltThreshold: _horizontalTiltThreshold,
        verticalTiltThreshold: _verticalTiltThreshold,
      );
}

class _CameraTiltsState extends State<CameraTilts> {
  CameraController _cameraController;
  int? _horizontalTiltThreshold;
  int? _verticalTiltThreshold;
  TakePictureMode? _mode;
  StreamSubscription? _tiltsSubscription;

  _CameraTiltsState({
    required CameraController cameraController,
    int? horizontalTiltThreshold,
    int? verticalTiltThreshold,
  })  : _cameraController = cameraController,
        _horizontalTiltThreshold = horizontalTiltThreshold,
        _verticalTiltThreshold = verticalTiltThreshold;

  @override
  void initState() {
    super.initState();
    _tiltsSubscription = _cameraController.deviceTilts.listen(_tiltsListener);
  }

  void _tiltsListener(CameraDeviceTilts tilts) {
    if (_mode != tilts.mode) {
      _mode = tilts.mode;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == TakePictureMode.unknownShot ||
        _mode == TakePictureMode.normalShot) {
      return CameraNormalTilts(
        cameraController: _cameraController,
        verticalTiltThreshold: _verticalTiltThreshold,
        horizontalTiltThreshold: _horizontalTiltThreshold,
      );
    } else if (_mode == TakePictureMode.overheadShot) {
      return CameraOverheadTilts(
        cameraController: _cameraController,
        verticalTiltThreshold: _verticalTiltThreshold,
        horizontalTiltThreshold: _horizontalTiltThreshold,
      );
    }
    return Container();
  }

  @override
  void dispose() {
    _tiltsSubscription?.cancel();
    super.dispose();
  }
}
