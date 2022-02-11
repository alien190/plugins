import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera/src/camera_device_tilts.dart';
import 'package:camera/src/camera_normal_tilts.dart';
import 'package:camera/src/camera_overhead_tilts.dart';
import 'package:flutter/material.dart';

/// Camera tilts widget
class CameraTilts extends StatefulWidget {
  final CameraController _cameraController;
  final int? _normalHorizontalTiltThreshold;
  final int? _normalVerticalTiltThreshold;
  final int? _overheadHorizontalTiltThreshold;
  final int? _overheadVerticalTiltThreshold;

  /// Default constructor
  const CameraTilts({
    Key? key,
    required CameraController cameraController,
    int? normalHorizontalTiltThreshold,
    int? normalVerticalTiltThreshold,
    int? overheadHorizontalTiltThreshold,
    int? overheadVerticalTiltThreshold,
  })  : _cameraController = cameraController,
        _normalHorizontalTiltThreshold = normalHorizontalTiltThreshold,
        _normalVerticalTiltThreshold = normalVerticalTiltThreshold,
        _overheadHorizontalTiltThreshold = overheadHorizontalTiltThreshold,
        _overheadVerticalTiltThreshold = overheadVerticalTiltThreshold,
        super(key: key);

  @override
  _CameraTiltsState createState() => _CameraTiltsState(
        cameraController: _cameraController,
        overheadHorizontalTiltThreshold: _overheadHorizontalTiltThreshold,
        overheadVerticalTiltThreshold: _overheadVerticalTiltThreshold,
        normalHorizontalTiltThreshold: _normalHorizontalTiltThreshold,
        normalVerticalTiltThreshold: _normalVerticalTiltThreshold,
      );
}

class _CameraTiltsState extends State<CameraTilts> {
  CameraController _cameraController;
  int? _normalHorizontalTiltThreshold;
  int? _normalVerticalTiltThreshold;
  int? _overheadHorizontalTiltThreshold;
  int? _overheadVerticalTiltThreshold;
  TakePictureMode? _mode;
  StreamSubscription? _tiltsSubscription;

  _CameraTiltsState({
    required CameraController cameraController,
    int? normalHorizontalTiltThreshold,
    int? normalVerticalTiltThreshold,
    int? overheadHorizontalTiltThreshold,
    int? overheadVerticalTiltThreshold,
  })  : _cameraController = cameraController,
        _normalHorizontalTiltThreshold = normalHorizontalTiltThreshold,
        _normalVerticalTiltThreshold = normalVerticalTiltThreshold,
        _overheadHorizontalTiltThreshold = overheadHorizontalTiltThreshold,
        _overheadVerticalTiltThreshold = overheadVerticalTiltThreshold;

  @override
  void initState() {
    super.initState();
    _tiltsSubscription = _cameraController.deviceTilts.listen(_tiltsListener);
  }

  @override
  void didUpdateWidget(covariant CameraTilts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._cameraController != _cameraController) {
      _tiltsSubscription?.cancel();
      _tiltsSubscription =
          widget._cameraController.deviceTilts.listen(_tiltsListener);
    }
    if (widget._cameraController != _cameraController ||
        widget._normalHorizontalTiltThreshold !=
            _normalHorizontalTiltThreshold ||
        widget._normalVerticalTiltThreshold != _normalVerticalTiltThreshold ||
        widget._overheadHorizontalTiltThreshold !=
            _overheadHorizontalTiltThreshold ||
        widget._overheadVerticalTiltThreshold !=
            _overheadVerticalTiltThreshold) {
      _cameraController = widget._cameraController;
      _normalVerticalTiltThreshold = widget._normalVerticalTiltThreshold;
      _normalHorizontalTiltThreshold = widget._normalHorizontalTiltThreshold;
      _overheadVerticalTiltThreshold = widget._overheadVerticalTiltThreshold;
      _overheadHorizontalTiltThreshold =
          widget._overheadHorizontalTiltThreshold;
      if (mounted) setState(() {});
    }
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
        verticalTiltThreshold: _normalVerticalTiltThreshold,
        horizontalTiltThreshold: _normalHorizontalTiltThreshold,
      );
    } else if (_mode == TakePictureMode.overheadShot) {
      return CameraOverheadTilts(
        cameraController: _cameraController,
        verticalTiltThreshold: _overheadVerticalTiltThreshold,
        horizontalTiltThreshold: _overheadHorizontalTiltThreshold,
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
