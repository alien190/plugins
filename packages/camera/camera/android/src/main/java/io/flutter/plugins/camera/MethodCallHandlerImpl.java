// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera;

import android.app.Activity;
import android.hardware.camera2.CameraAccessException;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import io.flutter.embedding.engine.systemchannels.PlatformChannel;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugins.camera.CameraPermissions.PermissionsRegistry;
import io.flutter.plugins.camera.features.CameraFeatureFactoryImpl;
import io.flutter.plugins.camera.features.Point;
import io.flutter.plugins.camera.features.autofocus.FocusMode;
import io.flutter.plugins.camera.features.exposurelock.ExposureMode;
import io.flutter.plugins.camera.features.flash.FlashMode;
import io.flutter.plugins.camera.features.resolution.ResolutionPreset;
import io.flutter.plugins.camera.types.BarcodeCaptureSettings;
import io.flutter.view.TextureRegistry;

import java.util.HashMap;
import java.util.Map;

final class MethodCallHandlerImpl implements MethodChannel.MethodCallHandler {
    private static final String TAG = "MethodCallHandlerImpl";
    private final Activity activity;
    private final BinaryMessenger messenger;
    private final CameraPermissions cameraPermissions;
    private final PermissionsRegistry permissionsRegistry;
    private final TextureRegistry textureRegistry;
    private final MethodChannel methodChannel;
    private @Nullable
    Camera camera;

    private @Nullable
    Long cameraSessionId;

    MethodCallHandlerImpl(
            Activity activity,
            BinaryMessenger messenger,
            CameraPermissions cameraPermissions,
            PermissionsRegistry permissionsAdder,
            TextureRegistry textureRegistry) {
        this.activity = activity;
        this.messenger = messenger;
        this.cameraPermissions = cameraPermissions;
        this.permissionsRegistry = permissionsAdder;
        this.textureRegistry = textureRegistry;

        methodChannel = new MethodChannel(messenger, "plugins.flutter.io/camera");
        methodChannel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull final Result result) {
        switch (call.method) {
            case "availableCameras":
                try {
                    result.success(CameraUtils.getAvailableCameras(activity));
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            case "create": {
                if (camera != null) {
                    camera.close();
                }

                cameraPermissions.requestPermissions(
                        activity,
                        permissionsRegistry,
                        call.argument("enableAudio"),
                        (String errCode, String errDesc) -> {
                            if (errCode == null) {
                                try {
                                    instantiateCamera(call, result);
                                } catch (Exception e) {
                                    handleException(e, result);
                                }
                            } else {
                                result.error(errCode, errDesc, null);
                            }
                        });
                break;
            }
            case "initialize": {
                if (camera != null) {
                    try {
                        final Long sessionId = getSessionId(call);
                        Log.d(TAG, "Camera initialize. sessionId=" + sessionId);
                        cameraSessionId = sessionId;

                        final Boolean isBarcodeStreamEnabled = call.argument("isBarcodeStreamEnabled");
                        if (isBarcodeStreamEnabled != null && isBarcodeStreamEnabled) {
                            Integer cropLeft = call.argument("cropLeft");
                            Integer cropRight = call.argument("cropRight");
                            Integer cropTop = call.argument("cropTop");
                            Integer cropBottom = call.argument("cropBottom");
                            Long streamId = call.argument("barcodeStreamId");

                            if (cropLeft == null) cropLeft = 0;
                            if (cropRight == null) cropRight = 0;
                            if (cropTop == null) cropTop = 0;
                            if (cropBottom == null) cropBottom = 0;
                            if (streamId == null) streamId = 0L;

                            final BarcodeCaptureSettings settings = new BarcodeCaptureSettings(
                                    cropLeft,
                                    cropRight,
                                    cropTop,
                                    cropBottom
                            );
                            final EventChannel barcodeStreamChannel =
                                    new EventChannel(messenger, "plugins.flutter.io/camera/barcodeStream/" + streamId);
                            camera.open(call.argument("imageFormatGroup"), settings, barcodeStreamChannel);
                        } else {
                            camera.open(call.argument("imageFormatGroup"), null, null);
                        }
                        result.success(null);
                    } catch (Exception e) {
                        handleException(e, result);
                    }
                } else {
                    result.error(
                            "cameraNotFound",
                            "Camera not found. Please call the 'create' method before calling 'initialize'.",
                            null);
                }
                break;
            }
            case "takePicture": {
                camera.takePicture(result);
                break;
            }
            case "prepareForVideoRecording": {
                // This optimization is not required for Android.
                result.success(null);
                break;
            }
            case "startVideoRecording": {
                camera.startVideoRecording(result);
                break;
            }
            case "stopVideoRecording": {
                camera.stopVideoRecording(result);
                break;
            }
            case "pauseVideoRecording": {
                camera.pauseVideoRecording(result);
                break;
            }
            case "resumeVideoRecording": {
                camera.resumeVideoRecording(result);
                break;
            }
            case "setFlashMode": {
                String modeStr = call.argument("mode");
                FlashMode mode = FlashMode.getValueForString(modeStr);
                if (mode == null) {
                    result.error("setFlashModeFailed", "Unknown flash mode " + modeStr, null);
                    return;
                }
                try {
                    camera.setFlashMode(result, mode);
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "setExposureMode": {
                String modeStr = call.argument("mode");
                ExposureMode mode = ExposureMode.getValueForString(modeStr);
                if (mode == null) {
                    result.error("setExposureModeFailed", "Unknown exposure mode " + modeStr, null);
                    return;
                }
                try {
                    camera.setExposureMode(result, mode);
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "setExposurePoint": {
                Boolean reset = call.argument("reset");
                Double x = null;
                Double y = null;
                if (reset == null || !reset) {
                    x = call.argument("x");
                    y = call.argument("y");
                }
                try {
                    camera.setExposurePoint(result, new Point(x, y));
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "getMinExposureOffset": {
                try {
                    result.success(camera.getMinExposureOffset());
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "getMaxExposureOffset": {
                try {
                    result.success(camera.getMaxExposureOffset());
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "getExposureOffsetStepSize": {
                try {
                    result.success(camera.getExposureOffsetStepSize());
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "setExposureOffset": {
                try {
                    camera.setExposureOffset(result, call.argument("offset"));
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "setFocusMode": {
                String modeStr = call.argument("mode");
                FocusMode mode = FocusMode.getValueForString(modeStr);
                if (mode == null) {
                    result.error("setFocusModeFailed", "Unknown focus mode " + modeStr, null);
                    return;
                }
                try {
                    camera.setFocusMode(result, mode);
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "setFocusPoint": {
                Boolean reset = call.argument("reset");
                Double x = null;
                Double y = null;
                if (reset == null || !reset) {
                    x = call.argument("x");
                    y = call.argument("y");
                }
                try {
                    camera.setFocusPoint(result, new Point(x, y));
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "stopBarcodeStream": {
                try {
                    camera.startPreview();
                    result.success(null);
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "getMaxZoomLevel": {
                assert camera != null;

                try {
                    float maxZoomLevel = camera.getMaxZoomLevel();
                    result.success(maxZoomLevel);
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "getMinZoomLevel": {
                assert camera != null;

                try {
                    float minZoomLevel = camera.getMinZoomLevel();
                    result.success(minZoomLevel);
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "setZoomLevel": {
                assert camera != null;

                Double zoom = call.argument("zoom");

                if (zoom == null) {
                    result.error(
                            "ZOOM_ERROR", "setZoomLevel is called without specifying a zoom level.", null);
                    return;
                }

                try {
                    camera.setZoomLevel(result, zoom.floatValue());
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "pausePreview": {
                try {
                    camera.pausePreview();
                    result.success(null);
                } catch (Exception e) {
                    handleException(e, result);
                }
                break;
            }
            case "resumePreview": {
                camera.resumePreview();
                result.success(null);
                break;
            }
            case "dispose": {
                try {
                    if (camera != null) {
                        final Long sessionId = getSessionId(call);

                        if (cameraSessionId == null || cameraSessionId.equals(sessionId)) {
                            Log.d(TAG, "Camera dispose. sessionId=" + sessionId);
                            cameraSessionId = null;
                            camera.dispose();
                        } else {
                            Log.w(TAG, "Camera dispose request is ignored because" +
                                    " sessionId=" + sessionId +
                                    ", cameraSessionId=" + cameraSessionId
                            );
                        }
                    }
                    result.success(null);
                } catch (Exception e) {
                    result.error("CameraDisposeError", e.toString(), null);
                }
                break;
            }
            default:
                result.notImplemented();
                break;
        }
    }

    private Long getSessionId(@NonNull MethodCall call) {
        try {
            final Long sessionId = call.argument("sessionId");
            if (sessionId == null) {
                return 0L;
            } else {
                return sessionId;
            }
        } catch (ClassCastException exception) {
            try {
                final Integer sessionId = call.argument("sessionId");
                if (sessionId == null) {
                    return 0L;
                } else {
                    return sessionId.longValue();
                }
            } catch (Exception exception1) {
                return 0L;
            }
        }
    }

    void stopListening() {
        methodChannel.setMethodCallHandler(null);
    }

    private void instantiateCamera(MethodCall call, Result result) throws CameraAccessException {
        String cameraName = call.argument("cameraName");
        String preset = call.argument("resolutionPreset");
        boolean enableAudio = call.hasArgument("enableAudio") ? call.argument("enableAudio") : false;
        int longSideSize = call.hasArgument("longSideSize") ? call.argument("longSideSize") : 1600;
        int imageQuality = call.hasArgument("imageQuality") ? call.argument("imageQuality") : 100;
        String lockedCaptureOrientationStr = call.argument("lockedCaptureOrientation");
        PlatformChannel.DeviceOrientation lockedCaptureOrientation = lockedCaptureOrientationStr != null ?
                CameraUtils.deserializeDeviceOrientation(lockedCaptureOrientationStr) : null;

        TextureRegistry.SurfaceTextureEntry flutterSurfaceTexture =
                textureRegistry.createSurfaceTexture();
        DartMessenger dartMessenger =
                new DartMessenger(
                        messenger, flutterSurfaceTexture.id(), new Handler(Looper.getMainLooper()));
        CameraProperties cameraProperties =
                new CameraPropertiesImpl(cameraName, CameraUtils.getCameraManager(activity));
        ResolutionPreset resolutionPreset = ResolutionPreset.valueOf(preset);

        camera =
                new Camera(
                        activity,
                        flutterSurfaceTexture,
                        new CameraFeatureFactoryImpl(),
                        dartMessenger,
                        cameraProperties,
                        resolutionPreset,
                        enableAudio,
                        longSideSize,
                        imageQuality,
                        lockedCaptureOrientation);

        Map<String, Object> reply = new HashMap<>();
        reply.put("cameraId", flutterSurfaceTexture.id());
        result.success(reply);
    }

    // We move catching CameraAccessException out of onMethodCall because it causes a crash
    // on plugin registration for sdks incompatible with Camera2 (< 21). We want this plugin to
    // to be able to compile with <21 sdks for apps that want the camera and support earlier version.
    @SuppressWarnings("ConstantConditions")
    private void handleException(Exception exception, Result result) {
        if (exception instanceof CameraAccessException) {
            result.error("CameraAccess", exception.getMessage(), null);
            return;
        }

        // CameraAccessException can not be cast to a RuntimeException.
        throw (RuntimeException) exception;
    }
}
