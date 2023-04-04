// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:camera/src/camera_barcode.dart';
import 'package:camera/src/camera_device_tilts.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pedantic/pedantic.dart';
import 'package:quiver/core.dart';
import 'package:rxdart/rxdart.dart';

final MethodChannel _channel = const MethodChannel('plugins.flutter.io/camera');

/// Signature for a callback receiving the a camera image.
///
/// This is used by [CameraController.startImageStream].
// ignore: inference_failure_on_function_return_type
typedef onLatestImageAvailable = Function(CameraImage image);

/// Completes with a list of available cameras.
///
/// May throw a [CameraException].
Future<List<CameraDescription>> availableCameras() async {
  return CameraPlatform.instance.availableCameras();
}

/// The state of a [CameraController].
class CameraValue {
  /// Creates a new camera controller state.
  const CameraValue({
    required this.isInitialized,
    this.errorDescription,
    this.previewSize,
    required this.isRecordingVideo,
    required this.isTakingPicture,
    required this.isStreamingImages,
    required this.isStreamingBarcodes,
    required bool isRecordingPaused,
    required this.flashMode,
    required this.exposureMode,
    required this.focusMode,
    required this.exposurePointSupported,
    required this.focusPointSupported,
    required this.deviceOrientation,
    this.lockedCaptureOrientation,
    this.recordingOrientation,
    this.isPreviewPaused = false,
    this.previewPauseOrientation,
  }) : _isRecordingPaused = isRecordingPaused;

  /// Creates a new camera controller state for an uninitialized controller.
  const CameraValue.uninitialized()
      : this(
          isInitialized: false,
          isRecordingVideo: false,
          isTakingPicture: false,
          isStreamingImages: false,
          isRecordingPaused: false,
          flashMode: FlashMode.auto,
          exposureMode: ExposureMode.auto,
          exposurePointSupported: false,
          focusMode: FocusMode.auto,
          focusPointSupported: false,
          deviceOrientation: DeviceOrientation.portraitUp,
          isPreviewPaused: false,
          isStreamingBarcodes: false,
        );

  /// True after [CameraController.initialize] has completed successfully.
  final bool isInitialized;

  /// True when a picture capture request has been sent but as not yet returned.
  final bool isTakingPicture;

  /// True when the camera is recording (not the same as previewing).
  final bool isRecordingVideo;

  /// True when images from the camera are being streamed.
  final bool isStreamingImages;

  /// True when barcodes from the camera are being streamed.
  final bool isStreamingBarcodes;

  final bool _isRecordingPaused;

  /// True when the preview widget has been paused manually.
  final bool isPreviewPaused;

  /// Set to the orientation the preview was paused in, if it is currently paused.
  final DeviceOrientation? previewPauseOrientation;

  /// True when camera [isRecordingVideo] and recording is paused.
  bool get isRecordingPaused => isRecordingVideo && _isRecordingPaused;

  /// Description of an error state.
  ///
  /// This is null while the controller is not in an error state.
  /// When [hasError] is true this contains the error description.
  final String? errorDescription;

  /// The size of the preview in pixels.
  ///
  /// Is `null` until [isInitialized] is `true`.
  final Size? previewSize;

  /// Convenience getter for `previewSize.width / previewSize.height`.
  ///
  /// Can only be called when [initialize] is done.
  double get aspectRatio => previewSize!.width / previewSize!.height;

  /// Whether the controller is in an error state.
  ///
  /// When true [errorDescription] describes the error.
  bool get hasError => errorDescription != null;

  /// The flash mode the camera is currently set to.
  final FlashMode flashMode;

  /// The exposure mode the camera is currently set to.
  final ExposureMode exposureMode;

  /// The focus mode the camera is currently set to.
  final FocusMode focusMode;

  /// Whether setting the exposure point is supported.
  final bool exposurePointSupported;

  /// Whether setting the focus point is supported.
  final bool focusPointSupported;

  /// The current device UI orientation.
  final DeviceOrientation deviceOrientation;

  /// The currently locked capture orientation.
  final DeviceOrientation? lockedCaptureOrientation;

  /// Whether the capture orientation is currently locked.
  bool get isCaptureOrientationLocked => lockedCaptureOrientation != null;

  /// The orientation of the currently running video recording.
  final DeviceOrientation? recordingOrientation;

  /// Creates a modified copy of the object.
  ///
  /// Explicitly specified fields get the specified value, all other fields get
  /// the same value of the current object.
  CameraValue copyWith({
    bool? isInitialized,
    bool? isRecordingVideo,
    bool? isTakingPicture,
    bool? isStreamingImages,
    bool? isStreamingBarcodes,
    String? errorDescription,
    Size? previewSize,
    bool? isRecordingPaused,
    FlashMode? flashMode,
    ExposureMode? exposureMode,
    FocusMode? focusMode,
    bool? exposurePointSupported,
    bool? focusPointSupported,
    DeviceOrientation? deviceOrientation,
    Optional<DeviceOrientation>? lockedCaptureOrientation,
    Optional<DeviceOrientation>? recordingOrientation,
    bool? isPreviewPaused,
    Optional<DeviceOrientation>? previewPauseOrientation,
  }) {
    return CameraValue(
      isInitialized: isInitialized ?? this.isInitialized,
      errorDescription: errorDescription,
      previewSize: previewSize ?? this.previewSize,
      isRecordingVideo: isRecordingVideo ?? this.isRecordingVideo,
      isTakingPicture: isTakingPicture ?? this.isTakingPicture,
      isStreamingImages: isStreamingImages ?? this.isStreamingImages,
      isRecordingPaused: isRecordingPaused ?? _isRecordingPaused,
      flashMode: flashMode ?? this.flashMode,
      exposureMode: exposureMode ?? this.exposureMode,
      focusMode: focusMode ?? this.focusMode,
      exposurePointSupported:
          exposurePointSupported ?? this.exposurePointSupported,
      focusPointSupported: focusPointSupported ?? this.focusPointSupported,
      deviceOrientation: deviceOrientation ?? this.deviceOrientation,
      lockedCaptureOrientation: lockedCaptureOrientation == null
          ? this.lockedCaptureOrientation
          : lockedCaptureOrientation.orNull,
      recordingOrientation: recordingOrientation == null
          ? this.recordingOrientation
          : recordingOrientation.orNull,
      isPreviewPaused: isPreviewPaused ?? this.isPreviewPaused,
      previewPauseOrientation: previewPauseOrientation == null
          ? this.previewPauseOrientation
          : previewPauseOrientation.orNull,
      isStreamingBarcodes: isStreamingBarcodes ?? this.isStreamingBarcodes,
    );
  }

  @override
  String toString() {
    return '$runtimeType('
        'isRecordingVideo: $isRecordingVideo, '
        'isInitialized: $isInitialized, '
        'errorDescription: $errorDescription, '
        'previewSize: $previewSize, '
        'isStreamingImages: $isStreamingImages, '
        'isStreamingBarcodes: $isStreamingBarcodes, '
        'flashMode: $flashMode, '
        'exposureMode: $exposureMode, '
        'focusMode: $focusMode, '
        'exposurePointSupported: $exposurePointSupported, '
        'focusPointSupported: $focusPointSupported, '
        'deviceOrientation: $deviceOrientation, '
        'lockedCaptureOrientation: $lockedCaptureOrientation, '
        'recordingOrientation: $recordingOrientation, '
        'isPreviewPaused: $isPreviewPaused, '
        'previewPausedOrientation: $previewPauseOrientation)';
  }
}

/// Controls a device camera.
///
/// Use [availableCameras] to get a list of available cameras.
///
/// Before using a [CameraController] a call to [initialize] must complete.
///
/// To show the camera preview on the screen use a [CameraPreview] widget.
class CameraController extends ValueNotifier<CameraValue> {
  /// Creates a new camera controller in an uninitialized state.
  CameraController(
    this.description,
    this.resolutionPreset, {
    this.enableAudio = true,
    this.imageFormatGroup,
    this.longSideSize = 1600,
    this.imageQuality = 100,
  }) : super(const CameraValue.uninitialized());

  /// The properties of the camera device controlled by this controller.
  final CameraDescription description;

  /// The resolution this controller is targeting.
  ///
  /// This resolution preset is not guaranteed to be available on the device,
  /// if unavailable a lower resolution will be used.
  ///
  /// See also: [ResolutionPreset].
  final ResolutionPreset resolutionPreset;

  /// Whether to include audio when recording a video.
  final bool enableAudio;

  /// The [ImageFormatGroup] describes the output of the raw image format.
  ///
  /// When null the imageFormat will fallback to the platforms default.
  final ImageFormatGroup? imageFormatGroup;

  /// The size of the longest size of a result image
  final int longSideSize;

  /// The quality of a result JPEG image in range 0-100
  final int imageQuality;

  /// The id of a camera that hasn't been initialized.
  @visibleForTesting
  static const int kUninitializedCameraId = -1;
  int _cameraId = kUninitializedCameraId;

  bool _isDisposed = false;
  StreamSubscription<dynamic>? _imageStreamSubscription;
  FutureOr<bool>? _initCalled;
  StreamSubscription? _deviceOrientationSubscription;
  StreamSubscription? _cameraClosingSubscription;
  StreamSubscription? _cameraErrorSubscription;
  StreamSubscription? _deviceTiltsSubscription;
  StreamSubscription? _deviceLogErrorSubscription;
  StreamSubscription? _deviceLogInfoSubscription;

  BehaviorSubject<CameraDeviceTilts> _deviceTiltsSubject = BehaviorSubject();
  BehaviorSubject<String> _deviceLogErrorSubject = BehaviorSubject();
  BehaviorSubject<String> _deviceLogInfoSubject = BehaviorSubject();

  /// barcodeStreamCompleter
  final Completer<Stream<CameraBarcode>> _barcodeStreamCompleter = Completer();

  /// barcodeStream
  Future<Stream<CameraBarcode>> get barcodeStream =>
      _barcodeStreamCompleter.future;

  /// Device tilts stream
  Stream<CameraDeviceTilts> get deviceTilts => _deviceTiltsSubject.stream;

  /// Device info log stream
  Stream<String> get deviceLogInfo => _deviceLogInfoSubject.stream;

  /// Device error log stream
  Stream<String> get deviceLogError => _deviceLogErrorSubject.stream;

  /// Checks whether [CameraController.dispose] has completed successfully.
  ///
  /// This is a no-op when asserts are disabled.
  void debugCheckIsDisposed() {
    assert(_isDisposed);
  }

  /// The camera identifier with which the controller is associated.
  int get cameraId => _cameraId;

  /// Initializes the camera on the device.
  ///
  /// Throws a [CameraException] if the initialization fails.
  Future<void> initialize({
    bool isBarcodeStreamEnabled = false,
    int cropLeftPercent = 0,
    int cropRightPercent = 0,
    int cropTopPercent = 0,
    int cropBottomPercent = 0,
    int sessionId = 0,
  }) async {
    if (_isDisposed) {
      throw CameraException(
        'Disposed CameraController',
        'initialize was called on a disposed CameraController',
      );
    }
    try {
      Completer<CameraInitializedEvent> _initializeCompleter = Completer();

      _deviceOrientationSubscription =
          CameraPlatform.instance.onDeviceOrientationChanged().listen((event) {
        value = value.copyWith(
          deviceOrientation: event.orientation,
        );
      });

      _deviceLogErrorSubscription = CameraPlatform.instance
          .onDeviceLogError()
          .listen(_deviceLogErrorListener);

      _deviceLogInfoSubscription = CameraPlatform.instance
          .onDeviceLogInfo()
          .listen(_deviceLogInfoListener);

      _cameraId = await CameraPlatform.instance.createCamera(
        description,
        resolutionPreset,
        enableAudio: enableAudio,
        longSideSize: 1600,
        imageQuality: imageQuality,
      );

      unawaited(CameraPlatform.instance
          .onCameraInitialized(_cameraId)
          .first
          .then((event) {
        _initializeCompleter.complete(event);
      }));

      final barcodeStreamId = DateTime.now().millisecondsSinceEpoch;

      await CameraPlatform.instance.initializeCamera(
        _cameraId,
        imageFormatGroup: imageFormatGroup ?? ImageFormatGroup.unknown,
        isBarcodeStreamEnabled: isBarcodeStreamEnabled,
        cropLeftPercent: cropLeftPercent,
        cropBottomPercent: cropBottomPercent,
        cropRightPercent: cropRightPercent,
        cropTopPercent: cropTopPercent,
        barcodeStreamId: barcodeStreamId,
        sessionId: sessionId,
      );

      value = value.copyWith(
        isInitialized: true,
        previewSize: await _initializeCompleter.future
            .then((CameraInitializedEvent event) => Size(
                  event.previewWidth,
                  event.previewHeight,
                )),
        exposureMode: await _initializeCompleter.future
            .then((event) => event.exposureMode),
        focusMode:
            await _initializeCompleter.future.then((event) => event.focusMode),
        exposurePointSupported: await _initializeCompleter.future
            .then((event) => event.exposurePointSupported),
        focusPointSupported: await _initializeCompleter.future
            .then((event) => event.focusPointSupported),
        isStreamingBarcodes: isBarcodeStreamEnabled,
      );

      _cameraClosingSubscription =
          CameraPlatform.instance.onCameraClosing(cameraId).listen(
                (e) => _setCameraIsNotInit('onCameraClosing event received'),
              );

      _cameraErrorSubscription =
          CameraPlatform.instance.onCameraError(cameraId).listen(
                (e) => _setCameraIsNotInit(
                  'onCameraError event received: ${e.description}',
                ),
              );

      _deviceTiltsSubscription = CameraPlatform.instance
          .onDeviceTiltsChanged()
          .listen(_deviceTiltsListener);

      final eventChannelName =
          'plugins.flutter.io/camera/barcodeStream/$barcodeStreamId';

      final barcodeStream = EventChannel(eventChannelName)
          .receiveBroadcastStream()
          .map(_toCameraBarcode);
      _barcodeStreamCompleter.complete(barcodeStream);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }

    _initCalled = true;
  }

  CameraBarcode _toCameraBarcode(dynamic event) {
    try {
      return CameraBarcode.fromJson(event);
    } catch (error) {
      return CameraBarcode(
        text: '',
        format: '',
        errorDescription: error.toString(),
      );
    }
  }

  void _setCameraIsNotInit(String errorDescription) {
    if (!_isDisposed) {
      value = value.copyWith(
        isInitialized: false,
        errorDescription: errorDescription,
      );
    }
  }

  /// Prepare the capture session for video recording.
  ///
  /// Use of this method is optional, but it may be called for performance
  /// reasons on iOS.
  ///
  /// Preparing audio can cause a minor delay in the CameraPreview view on iOS.
  /// If video recording is intended, calling this early eliminates this delay
  /// that would otherwise be experienced when video recording is started.
  /// This operation is a no-op on Android and Web.
  ///
  /// Throws a [CameraException] if the prepare fails.
  Future<void> prepareForVideoRecording() async {
    await CameraPlatform.instance.prepareForVideoRecording();
  }

  /// Pauses the current camera preview
  Future<void> pausePreview() async {
    if (value.isPreviewPaused) {
      return;
    }
    try {
      await CameraPlatform.instance.pausePreview(_cameraId);
      value = value.copyWith(
          isPreviewPaused: true,
          previewPauseOrientation: Optional.of(this.value.deviceOrientation));
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Resumes the current camera preview
  Future<void> resumePreview() async {
    if (!value.isPreviewPaused) {
      return;
    }
    try {
      await CameraPlatform.instance.resumePreview(_cameraId);
      value = value.copyWith(
          isPreviewPaused: false, previewPauseOrientation: Optional.absent());
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Captures an image and returns the file where it was saved.
  ///
  /// Throws a [CameraException] if the capture fails.
  Future<TakePictureResult> takePicture() async {
    _throwIfNotInitialized("takePicture");
    if (value.isTakingPicture) {
      throw CameraException(
        'Previous capture has not returned yet.',
        'takePicture was called before the previous capture returned.',
      );
    }
    try {
      value = value.copyWith(
        isTakingPicture: true,
      );
      final completer = Completer<TakePictureResult>();

      final handleError = (error) {
        if (!completer.isCompleted) {
          if (error is CameraErrorEvent) {
            completer.completeError(error.description);
          } else {
            completer.completeError(error);
          }
        }
      };

      final handleResult = (result) {
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      };

      final errorSubscription =
          CameraPlatform.instance.onCameraError(_cameraId).listen(handleError);

      final handleComplete = (_) {
        errorSubscription.cancel();
        value = value.copyWith(isTakingPicture: false);
      };

      unawaited(completer.future.then(handleComplete, onError: handleComplete));

      unawaited(CameraPlatform.instance
          .takePicture(_cameraId)
          .then(handleResult, onError: handleError));

      return completer.future;
    } on PlatformException catch (e) {
      value = value.copyWith(
        isTakingPicture: false,
      );
      throw CameraException(e.code, e.message);
    }
  }

  /// Start streaming images from platform camera.
  ///
  /// Settings for capturing images on iOS and Android is set to always use the
  /// latest image available from the camera and will drop all other images.
  ///
  /// When running continuously with [CameraPreview] widget, this function runs
  /// best with [ResolutionPreset.low]. Running on [ResolutionPreset.high] can
  /// have significant frame rate drops for [CameraPreview] on lower end
  /// devices.
  ///
  /// Throws a [CameraException] if image streaming or video recording has
  /// already started.
  ///
  /// The `startImageStream` method is only available on Android and iOS (other
  /// platforms won't be supported in current setup).
  ///
  // TODO(bmparr): Add settings for resolution and fps.
  Future<void> startImageStream(onLatestImageAvailable onAvailable) async {
    assert(defaultTargetPlatform == TargetPlatform.iOS);
    _throwIfNotInitialized("startImageStream");
    if (value.isRecordingVideo) {
      throw CameraException(
        'A video recording is already started.',
        'startImageStream was called while a video is being recorded.',
      );
    }
    if (value.isStreamingImages) {
      throw CameraException(
        'A camera has started streaming images.',
        'startImageStream was called while a camera was streaming images.',
      );
    }

    try {
      await _channel.invokeMethod<void>('startImageStream');
      value = value.copyWith(isStreamingImages: true);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
    const EventChannel cameraEventChannel =
        EventChannel('plugins.flutter.io/camera/imageStream');
    _imageStreamSubscription =
        cameraEventChannel.receiveBroadcastStream().listen(
      (dynamic imageData) {
        onAvailable(CameraImage.fromPlatformData(imageData));
      },
    );
  }

  /// Stop streaming images from platform camera.
  ///
  /// Throws a [CameraException] if image streaming was not started or video
  /// recording was started.
  ///
  /// The `stopImageStream` method is only available on Android and iOS (other
  /// platforms won't be supported in current setup).
  Future<void> stopImageStream() async {
    assert(defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
    _throwIfNotInitialized("stopImageStream");
    if (value.isRecordingVideo) {
      throw CameraException(
        'A video recording is already started.',
        'stopImageStream was called while a video is being recorded.',
      );
    }
    if (!value.isStreamingImages) {
      throw CameraException(
        'No camera is streaming images',
        'stopImageStream was called when no camera is streaming images.',
      );
    }

    try {
      value = value.copyWith(isStreamingImages: false);
      await _channel.invokeMethod<void>('stopImageStream');
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }

    await _imageStreamSubscription?.cancel();
    _imageStreamSubscription = null;
  }

  /// Stop streaming barcodes from platform camera.
  Future<void> stopBarcodeStream() async {
    assert(defaultTargetPlatform == TargetPlatform.android);
    _throwIfNotInitialized("stopBarcodeStream");
    if (value.isRecordingVideo) {
      throw CameraException(
        'A video recording is already started.',
        'stopBarcodeStream was called while a video is being recorded.',
      );
    }
    if (!value.isStreamingBarcodes) {
      throw CameraException(
        'No camera is streaming barcodes',
        'stopImageStream was called when no camera is streaming images.',
      );
    }

    try {
      value = value.copyWith(isStreamingBarcodes: false);
      await _channel.invokeMethod<void>('stopBarcodeStream');
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Start a video recording.
  ///
  /// The video is returned as a [XFile] after calling [stopVideoRecording].
  /// Throws a [CameraException] if the capture fails.
  Future<void> startVideoRecording() async {
    _throwIfNotInitialized("startVideoRecording");
    if (value.isRecordingVideo) {
      throw CameraException(
        'A video recording is already started.',
        'startVideoRecording was called when a recording is already started.',
      );
    }
    if (value.isStreamingImages) {
      throw CameraException(
        'A camera has started streaming images.',
        'startVideoRecording was called while a camera was streaming images.',
      );
    }

    try {
      await CameraPlatform.instance.startVideoRecording(_cameraId);
      value = value.copyWith(
          isRecordingVideo: true,
          isRecordingPaused: false,
          recordingOrientation: Optional.fromNullable(
              value.lockedCaptureOrientation ?? value.deviceOrientation));
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Stops the video recording and returns the file where it was saved.
  ///
  /// Throws a [CameraException] if the capture failed.
  Future<XFile> stopVideoRecording() async {
    _throwIfNotInitialized("stopVideoRecording");
    if (!value.isRecordingVideo) {
      throw CameraException(
        'No video is recording',
        'stopVideoRecording was called when no video is recording.',
      );
    }
    try {
      XFile file = await CameraPlatform.instance.stopVideoRecording(_cameraId);
      value = value.copyWith(
        isRecordingVideo: false,
        recordingOrientation: Optional.absent(),
      );
      return file;
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Pause video recording.
  ///
  /// This feature is only available on iOS and Android sdk 24+.
  Future<void> pauseVideoRecording() async {
    _throwIfNotInitialized("pauseVideoRecording");
    if (!value.isRecordingVideo) {
      throw CameraException(
        'No video is recording',
        'pauseVideoRecording was called when no video is recording.',
      );
    }
    try {
      await CameraPlatform.instance.pauseVideoRecording(_cameraId);
      value = value.copyWith(isRecordingPaused: true);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Resume video recording after pausing.
  ///
  /// This feature is only available on iOS and Android sdk 24+.
  Future<void> resumeVideoRecording() async {
    _throwIfNotInitialized("resumeVideoRecording");
    if (!value.isRecordingVideo) {
      throw CameraException(
        'No video is recording',
        'resumeVideoRecording was called when no video is recording.',
      );
    }
    try {
      await CameraPlatform.instance.resumeVideoRecording(_cameraId);
      value = value.copyWith(isRecordingPaused: false);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Returns a widget showing a live camera preview.
  Widget buildPreview() {
    if (!value.isInitialized || _isDisposed) return const SizedBox();
    try {
      return CameraPlatform.instance.buildPreview(_cameraId);
    } on PlatformException catch (e) {
      value = value.copyWith(errorDescription: '${e.code}, ${e.message}');
      return const SizedBox();
    }
  }

  /// Gets the maximum supported zoom level for the selected camera.
  Future<double> getMaxZoomLevel() {
    _throwIfNotInitialized("getMaxZoomLevel");
    try {
      return CameraPlatform.instance.getMaxZoomLevel(_cameraId);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Gets the minimum supported zoom level for the selected camera.
  Future<double> getMinZoomLevel() {
    _throwIfNotInitialized("getMinZoomLevel");
    try {
      return CameraPlatform.instance.getMinZoomLevel(_cameraId);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Set the zoom level for the selected camera.
  ///
  /// The supplied [zoom] value should be between 1.0 and the maximum supported
  /// zoom level returned by the `getMaxZoomLevel`. Throws an `CameraException`
  /// when an illegal zoom level is suplied.
  Future<void> setZoomLevel(double zoom) {
    _throwIfNotInitialized("setZoomLevel");
    try {
      return CameraPlatform.instance.setZoomLevel(_cameraId, zoom);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Sets the flash mode for taking pictures.
  Future<void> setFlashMode(FlashMode mode) async {
    try {
      await CameraPlatform.instance.setFlashMode(_cameraId, mode);
      value = value.copyWith(flashMode: mode);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Sets the exposure mode for taking pictures.
  Future<void> setExposureMode(ExposureMode mode) async {
    try {
      await CameraPlatform.instance.setExposureMode(_cameraId, mode);
      value = value.copyWith(exposureMode: mode);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Sets the exposure point for automatically determining the exposure value.
  ///
  /// Supplying a `null` value will reset the exposure point to it's default
  /// value.
  Future<void> setExposurePoint(Offset? point) async {
    if (point != null &&
        (point.dx < 0 || point.dx > 1 || point.dy < 0 || point.dy > 1)) {
      throw ArgumentError(
          'The values of point should be anywhere between (0,0) and (1,1).');
    }

    try {
      await CameraPlatform.instance.setExposurePoint(
        _cameraId,
        point == null
            ? null
            : Point<double>(
                point.dx,
                point.dy,
              ),
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Gets the minimum supported exposure offset for the selected camera in EV units.
  Future<double> getMinExposureOffset() async {
    _throwIfNotInitialized("getMinExposureOffset");
    try {
      return CameraPlatform.instance.getMinExposureOffset(_cameraId);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Gets the maximum supported exposure offset for the selected camera in EV units.
  Future<double> getMaxExposureOffset() async {
    _throwIfNotInitialized("getMaxExposureOffset");
    try {
      return CameraPlatform.instance.getMaxExposureOffset(_cameraId);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Gets the supported step size for exposure offset for the selected camera in EV units.
  ///
  /// Returns 0 when the camera supports using a free value without stepping.
  Future<double> getExposureOffsetStepSize() async {
    _throwIfNotInitialized("getExposureOffsetStepSize");
    try {
      return CameraPlatform.instance.getExposureOffsetStepSize(_cameraId);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Sets the exposure offset for the selected camera.
  ///
  /// The supplied [offset] value should be in EV units. 1 EV unit represents a
  /// doubling in brightness. It should be between the minimum and maximum offsets
  /// obtained through `getMinExposureOffset` and `getMaxExposureOffset` respectively.
  /// Throws a `CameraException` when an illegal offset is supplied.
  ///
  /// When the supplied [offset] value does not align with the step size obtained
  /// through `getExposureStepSize`, it will automatically be rounded to the nearest step.
  ///
  /// Returns the (rounded) offset value that was set.
  Future<double> setExposureOffset(double offset) async {
    _throwIfNotInitialized("setExposureOffset");
    // Check if offset is in range
    List<double> range =
        await Future.wait([getMinExposureOffset(), getMaxExposureOffset()]);
    if (offset < range[0] || offset > range[1]) {
      throw CameraException(
        "exposureOffsetOutOfBounds",
        "The provided exposure offset was outside the supported range for this device.",
      );
    }

    // Round to the closest step if needed
    double stepSize = await getExposureOffsetStepSize();
    if (stepSize > 0) {
      double inv = 1.0 / stepSize;
      double roundedOffset = (offset * inv).roundToDouble() / inv;
      if (roundedOffset > range[1]) {
        roundedOffset = (offset * inv).floorToDouble() / inv;
      } else if (roundedOffset < range[0]) {
        roundedOffset = (offset * inv).ceilToDouble() / inv;
      }
      offset = roundedOffset;
    }

    try {
      return CameraPlatform.instance.setExposureOffset(_cameraId, offset);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Locks the capture orientation.
  ///
  /// If [orientation] is omitted, the current device orientation is used.
  Future<void> lockCaptureOrientation([DeviceOrientation? orientation]) async {
    try {
      await CameraPlatform.instance.lockCaptureOrientation(
          _cameraId, orientation ?? value.deviceOrientation);
      value = value.copyWith(
          lockedCaptureOrientation:
              Optional.fromNullable(orientation ?? value.deviceOrientation));
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Sets the focus mode for taking pictures.
  Future<void> setFocusMode(FocusMode mode) async {
    try {
      await CameraPlatform.instance.setFocusMode(_cameraId, mode);
      value = value.copyWith(focusMode: mode);
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Unlocks the capture orientation.
  Future<void> unlockCaptureOrientation() async {
    try {
      await CameraPlatform.instance.unlockCaptureOrientation(_cameraId);
      value = value.copyWith(lockedCaptureOrientation: Optional.absent());
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Sets the focus point for automatically determining the focus value.
  ///
  /// Supplying a `null` value will reset the focus point to it's default
  /// value.
  Future<void> setFocusPoint(Offset? point) async {
    if (point != null &&
        (point.dx < 0 || point.dx > 1 || point.dy < 0 || point.dy > 1)) {
      throw ArgumentError(
          'The values of point should be anywhere between (0,0) and (1,1).');
    }
    try {
      await CameraPlatform.instance.setFocusPoint(
        _cameraId,
        point == null
            ? null
            : Point<double>(
                point.dx,
                point.dy,
              ),
      );
    } on PlatformException catch (e) {
      throw CameraException(e.code, e.message);
    }
  }

  /// Releases the resources of this camera.
  @override
  Future<void> dispose({int sessionId = 0}) async {
    if (_isDisposed) {
      return;
    }
    unawaited(_deviceOrientationSubscription?.cancel());
    unawaited(_cameraErrorSubscription?.cancel());
    unawaited(_cameraClosingSubscription?.cancel());
    _isDisposed = true;
    if (_initCalled != null) {
      await _initCalled;
      await CameraPlatform.instance.dispose(_cameraId, sessionId: sessionId);
    }
    unawaited(_deviceTiltsSubscription?.cancel());
    unawaited(_deviceLogErrorSubscription?.cancel());
    unawaited(_deviceLogInfoSubscription?.cancel());
    super.dispose();
  }

  void _throwIfNotInitialized(String functionName) {
    if (!value.isInitialized) {
      throw CameraException(
        'Uninitialized CameraController',
        '$functionName() was called on an uninitialized CameraController.',
      );
    }
    if (_isDisposed) {
      throw CameraException(
        'Disposed CameraController',
        '$functionName() was called on a disposed CameraController.',
      );
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    // Prevent ValueListenableBuilder in CameraPreview widget from causing an
    // exception to be thrown by attempting to remove its own listener after
    // the controller has already been disposed.
    if (!_isDisposed) {
      super.removeListener(listener);
    }
  }

  void _deviceTiltsListener(DeviceTiltsChangedEvent event) {
    if (!_deviceTiltsSubject.isClosed) {
      _deviceTiltsSubject.add(CameraDeviceTilts(
        targetImageRotation: event.targetImageRotation,
        verticalTilt: event.verticalTilt,
        horizontalTilt: event.horizontalTilt,
        isHorizontalTiltAvailable: event.isHorizontalTiltAvailable,
        isVerticalTiltAvailable: event.isVerticalTiltAvailable,
        lockedCaptureAngle: event.lockedCaptureAngle,
        deviceOrientationAngle: event.deviceOrientationAngle,
        mode: event.mode,
        isUIRotationEqualAccRotation: event.isUIRotationEqualAccRotation,
      ));
    }
  }

  void _deviceLogErrorListener(DeviceLogErrorMessageEvent event) {
    if (!_deviceLogErrorSubject.isClosed) {
      _deviceLogErrorSubject.add(event.message);
    }
  }

  void _deviceLogInfoListener(DeviceLogInfoMessageEvent event) {
    if (!_deviceLogInfoSubject.isClosed) {
      _deviceLogInfoSubject.add(event.message);
    }
  }
}
