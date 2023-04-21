// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera;

import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ImageFormat;
import android.graphics.Rect;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CameraMetadata;
import android.hardware.camera2.CaptureFailure;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.CaptureResult;
import android.hardware.camera2.TotalCaptureResult;
import android.hardware.camera2.params.OutputConfiguration;
import android.hardware.camera2.params.SessionConfiguration;
import android.media.CamcorderProfile;
import android.media.Image;
import android.media.ImageReader;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Build.VERSION;
import android.os.Build.VERSION_CODES;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Log;
import android.util.Size;
import android.view.Display;
import android.view.Surface;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.VisibleForTesting;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.Binarizer;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.LuminanceSource;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.NotFoundException;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.RGBLuminanceSource;
import com.google.zxing.common.GlobalHistogramBinarizer;

import io.flutter.embedding.engine.systemchannels.PlatformChannel;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugins.camera.features.CameraFeature;
import io.flutter.plugins.camera.features.CameraFeatureFactory;
import io.flutter.plugins.camera.features.CameraFeatures;
import io.flutter.plugins.camera.features.Point;
import io.flutter.plugins.camera.features.autofocus.AutoFocusFeature;
import io.flutter.plugins.camera.features.autofocus.FocusMode;
import io.flutter.plugins.camera.features.exposurelock.ExposureLockFeature;
import io.flutter.plugins.camera.features.exposurelock.ExposureMode;
import io.flutter.plugins.camera.features.exposureoffset.ExposureOffsetFeature;
import io.flutter.plugins.camera.features.exposurepoint.ExposurePointFeature;
import io.flutter.plugins.camera.features.flash.FlashFeature;
import io.flutter.plugins.camera.features.flash.FlashMode;
import io.flutter.plugins.camera.features.focuspoint.FocusPointFeature;
import io.flutter.plugins.camera.features.resolution.ResolutionFeature;
import io.flutter.plugins.camera.features.resolution.ResolutionPreset;
import io.flutter.plugins.camera.features.sensororientation.DeviceOrientationManager;
import io.flutter.plugins.camera.features.sensororientation.SensorOrientationFeature;
import io.flutter.plugins.camera.features.zoomlevel.ZoomLevelFeature;
import io.flutter.plugins.camera.media.MediaRecorderBuilder;
import io.flutter.plugins.camera.types.BarcodeCaptureSettings;
import io.flutter.plugins.camera.types.CameraBarcode;
import io.flutter.plugins.camera.types.CameraCaptureProperties;
import io.flutter.plugins.camera.types.CaptureTimeoutsWrapper;
import io.flutter.plugins.camera.types.ImageBytes;
import io.flutter.plugins.camera.types.TakePictureResult;
import io.flutter.view.TextureRegistry.SurfaceTextureEntry;

import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.Executors;

@FunctionalInterface
interface ErrorCallback {
    void onError(String errorCode, String errorMessage);
}

class Camera
        implements CameraCaptureCallback.CameraCaptureStateListener,
        ImageReader.OnImageAvailableListener {
    private static final String TAG = "Camera";
    private static final String TAG_CAPTURE = "CameraCapture";

    private static final HashMap<String, Integer> supportedImageFormats;

    // Current supported outputs.
    static {
        supportedImageFormats = new HashMap<>();
        supportedImageFormats.put("yuv420", ImageFormat.YUV_420_888);
        supportedImageFormats.put("jpeg", ImageFormat.JPEG);
    }

    /**
     * Holds all of the camera features/settings and will be used to update the request builder when
     * one changes.
     */
    private final CameraFeatures cameraFeatures;

    private final SurfaceTextureEntry flutterTexture;
    private final boolean enableAudio;
    private final Context applicationContext;
    private final DartMessenger dartMessenger;
    private final CameraProperties cameraProperties;
    private final CameraFeatureFactory cameraFeatureFactory;
    private final Activity activity;
    /**
     * A {@link CameraCaptureSession.CaptureCallback} that handles events related to JPEG capture.
     */
    private final CameraCaptureCallback cameraCaptureCallback;
    /**
     * A {@link Handler} for running tasks in the background.
     */
    private Handler backgroundHandler;

    private Handler barcodeBackgroundHandler;

    /**
     * An additional thread for running tasks that shouldn't block the UI.
     */
    private HandlerThread backgroundHandlerThread;

    private HandlerThread barcodeBackgroundHandlerThread;

    private CameraDevice cameraDevice;
    private CameraCaptureSession captureSession;
    private ImageReader pictureImageReader;
    private ImageReader imageStreamReader;
    /**
     * {@link CaptureRequest.Builder} for the camera preview
     */
    private CaptureRequest.Builder previewRequestBuilder;

    private MediaRecorder mediaRecorder;
    /**
     * True when recording video.
     */
    private boolean recordingVideo;
    /**
     * True when the preview is paused.
     */
    private boolean pausedPreview;

    private File captureFile;

    /**
     * Holds the current capture timeouts
     */
    private CaptureTimeoutsWrapper captureTimeouts;
    /**
     * Holds the last known capture properties
     */
    private CameraCaptureProperties captureProps;

    private MethodChannel.Result flutterResult;

    private Boolean nextImageIsRequestedToBarcodeScan;

    private EventChannel.EventSink barcodeStreamSink;

    public Camera(
            final Activity activity,
            final SurfaceTextureEntry flutterTexture,
            final CameraFeatureFactory cameraFeatureFactory,
            final DartMessenger dartMessenger,
            final CameraProperties cameraProperties,
            final ResolutionPreset resolutionPreset,
            final boolean enableAudio,
            final int longSideSize,
            final int imageQuality,
            PlatformChannel.DeviceOrientation lockedCaptureOrientation) {

        if (activity == null) {
            throw new IllegalStateException("No activity available!");
        }
        this.activity = activity;
        this.enableAudio = enableAudio;
        this.flutterTexture = flutterTexture;
        this.dartMessenger = dartMessenger;
        this.applicationContext = activity.getApplicationContext();
        this.cameraProperties = cameraProperties;
        this.cameraFeatureFactory = cameraFeatureFactory;
        this.cameraFeatures = CameraFeatures.init(
                cameraFeatureFactory,
                cameraProperties,
                activity,
                dartMessenger,
                resolutionPreset,
                longSideSize,
                imageQuality,
                lockedCaptureOrientation);

        // Create capture callback.
        captureTimeouts = new CaptureTimeoutsWrapper(3000, 3000);
        captureProps = new CameraCaptureProperties();
        cameraCaptureCallback = CameraCaptureCallback.create(this, captureTimeouts, captureProps);
        nextImageIsRequestedToBarcodeScan = false;

        startBackgroundThread();
        startBarcodeBackgroundThread();
    }

    @Override
    public void onConverged() {
        takePictureAfterPrecapture();
    }

    @Override
    public void onPrecapture() {
        runPrecaptureSequence();
    }

    /**
     * Updates the builder settings with all of the available features.
     *
     * @param requestBuilder request builder to update.
     */
    private void updateBuilderSettings(CaptureRequest.Builder requestBuilder) {
        for (CameraFeature feature : cameraFeatures.getAllFeatures()) {
            Log.d(TAG, "Updating builder with feature: " + feature.getDebugName());
            feature.updateBuilder(requestBuilder);
        }
    }

    private void prepareMediaRecorder(String outputFilePath) throws IOException {
        Log.i(TAG, "prepareMediaRecorder");

        if (mediaRecorder != null) {
            mediaRecorder.release();
        }

        final PlatformChannel.DeviceOrientation lockedOrientation =
                cameraFeatures.getSensorOrientation().getLockedCaptureOrientation();

        MediaRecorderBuilder mediaRecorderBuilder = new MediaRecorderBuilder(getRecordingProfileLegacy(), outputFilePath);


        mediaRecorder =
                mediaRecorderBuilder
                        .setEnableAudio(enableAudio)
                        .setMediaOrientation(
                                lockedOrientation == null
                                        ? getDeviceOrientationManager().getVideoOrientation()
                                        : getDeviceOrientationManager().getVideoOrientation(lockedOrientation))
                        .build();
    }

    @SuppressLint({"MissingPermission", "WrongConstant"})
    public void open(String imageFormatGroup,
                     BarcodeCaptureSettings barcodeCaptureSettings,
                     EventChannel barcodeEventChannel
    ) throws CameraAccessException {
        final ResolutionFeature resolutionFeature = cameraFeatures.getResolution();

        if (!resolutionFeature.checkIsSupported()) {
            // Tell the user that the camera they are trying to open is not supported,
            // as its {@link android.media.CamcorderProfile} cannot be fetched due to the name
            // not being a valid parsable integer.
            dartMessenger.sendCameraErrorEvent(
                    "Camera with name \""
                            + cameraProperties.getCameraName()
                            + "\" is not supported by this plugin.");
            return;
        }

        // Always capture using JPEG format.
        pictureImageReader =
                ImageReader.newInstance(
                        resolutionFeature.getCaptureSize().getWidth(),
                        resolutionFeature.getCaptureSize().getHeight(),
                        resolutionFeature.getCaptureFormat(),
                        1);

        imageStreamReader =
                ImageReader.newInstance(
                        resolutionFeature.getPreviewSize().getWidth(),
                        resolutionFeature.getPreviewSize().getHeight(),
                        resolutionFeature.getCaptureFormat(),
                        1);

        // Open the camera.
        CameraManager cameraManager = CameraUtils.getCameraManager(activity);
        cameraManager.openCamera(
                cameraProperties.getCameraName(),
                new CameraDevice.StateCallback() {
                    @Override
                    public void onOpened(@NonNull CameraDevice device) {
                        cameraDevice = device;
                        try {
                            if (barcodeCaptureSettings != null && barcodeEventChannel != null) {
                                startPreviewWithBarcodeStream(
                                        barcodeCaptureSettings,
                                        barcodeEventChannel
                                );
                            } else {
                                startPreview();
                            }
                            dartMessenger.sendCameraInitializedEvent(
                                    resolutionFeature.getPreviewSize().getWidth(),
                                    resolutionFeature.getPreviewSize().getHeight(),
                                    cameraFeatures.getExposureLock().getValue(),
                                    cameraFeatures.getAutoFocus().getValue(),
                                    cameraFeatures.getExposurePoint().checkIsSupported(),
                                    cameraFeatures.getFocusPoint().checkIsSupported());
                        } catch (Exception e) {
                            dartMessenger.sendCameraErrorEvent(e.getMessage());
                            close();
                        }
                    }

                    @Override
                    public void onClosed(@NonNull CameraDevice camera) {
                        Log.i(TAG, "open | onClosed");

                        // Prevents calls to methods that would otherwise result in IllegalStateException exceptions.
                        cameraDevice = null;
                        closeCaptureSession();
                        dartMessenger.sendCameraClosingEvent();
                    }

                    @Override
                    public void onDisconnected(@NonNull CameraDevice cameraDevice) {
                        Log.i(TAG, "open | onDisconnected");

                        close();
                        dartMessenger.sendCameraErrorEvent("The camera was disconnected.");
                    }

                    @Override
                    public void onError(@NonNull CameraDevice cameraDevice, int errorCode) {
                        Log.i(TAG, "open | onError");

                        close();
                        String errorDescription;
                        switch (errorCode) {
                            case ERROR_CAMERA_IN_USE:
                                errorDescription = "The camera device is in use already.";
                                break;
                            case ERROR_MAX_CAMERAS_IN_USE:
                                errorDescription = "Max cameras in use";
                                break;
                            case ERROR_CAMERA_DISABLED:
                                errorDescription = "The camera device could not be opened due to a device policy.";
                                break;
                            case ERROR_CAMERA_DEVICE:
                                errorDescription = "The camera device has encountered a fatal error";
                                break;
                            case ERROR_CAMERA_SERVICE:
                                errorDescription = "The camera service has encountered a fatal error.";
                                break;
                            default:
                                errorDescription = "Unknown camera error";
                        }
                        dartMessenger.sendCameraErrorEvent(errorDescription);
                    }
                },
                backgroundHandler);
    }

    private void createCaptureSession(int templateType, Surface... surfaces)
            throws CameraAccessException {
        createCaptureSession(
                templateType,
                () -> Log.d(TAG, "Capture session was created successfully"),
                surfaces
        );
    }

    private void createCaptureSession(
            int templateType,
            Runnable onSuccessCallback,
            Surface... surfaces
    ) throws CameraAccessException {
        // Close any existing capture session.
        closeCaptureSession();

        // Create a new capture builder.
        previewRequestBuilder = cameraDevice.createCaptureRequest(templateType);

        // Build Flutter surface to render to.
        ResolutionFeature resolutionFeature = cameraFeatures.getResolution();
        SurfaceTexture surfaceTexture = flutterTexture.surfaceTexture();
        surfaceTexture.setDefaultBufferSize(
                resolutionFeature.getPreviewSize().getWidth(),
                resolutionFeature.getPreviewSize().getHeight());
        Surface flutterSurface = new Surface(surfaceTexture);
        previewRequestBuilder.addTarget(flutterSurface);

        List<Surface> remainingSurfaces = Arrays.asList(surfaces);
        if (templateType != CameraDevice.TEMPLATE_PREVIEW) {
            // If it is not preview mode, add all surfaces as targets.
            for (Surface surface : remainingSurfaces) {
                previewRequestBuilder.addTarget(surface);
            }
        }

        // Update camera regions.
        Size cameraBoundaries =
                CameraRegionUtils.getCameraBoundaries(cameraProperties, previewRequestBuilder);
        cameraFeatures.getExposurePoint().setCameraBoundaries(cameraBoundaries);
        cameraFeatures.getFocusPoint().setCameraBoundaries(cameraBoundaries);

        // Prepare the callback.
        CameraCaptureSession.StateCallback callback =
                new CameraCaptureSession.StateCallback() {
                    boolean captureSessionClosed = false;

                    @Override
                    public void onConfigured(@NonNull CameraCaptureSession session) {
                        Log.i(TAG, "CameraCaptureSession onConfigured");
                        // Camera was already closed.
                        if (cameraDevice == null || captureSessionClosed) {
                            dartMessenger.sendCameraErrorEvent("The camera was closed during configuration.");
                            return;
                        }
                        captureSession = session;

                        Log.i(TAG, "Updating builder settings");
                        updateBuilderSettings(previewRequestBuilder);

                        refreshPreviewCaptureSession(
                                onSuccessCallback,
                                (code, message) -> dartMessenger.sendCameraErrorEvent(message)
                        );
                    }

                    @Override
                    public void onConfigureFailed(@NonNull CameraCaptureSession cameraCaptureSession) {
                        Log.i(TAG, "CameraCaptureSession onConfigureFailed");
                        dartMessenger.sendCameraErrorEvent("Failed to configure camera session.");
                    }

                    @Override
                    public void onClosed(@NonNull CameraCaptureSession session) {
                        Log.i(TAG, "CameraCaptureSession onClosed");
                        captureSessionClosed = true;
                    }
                };

        // Start the session.
        if (VERSION.SDK_INT >= VERSION_CODES.P) {
            // Collect all surfaces to render to.
            List<OutputConfiguration> configs = new ArrayList<>();
            configs.add(new OutputConfiguration(flutterSurface));
            for (Surface surface : remainingSurfaces) {
                configs.add(new OutputConfiguration(surface));
            }
            createCaptureSessionWithSessionConfig(configs, callback);
        } else {
            // Collect all surfaces to render to.
            List<Surface> surfaceList = new ArrayList<>();
            surfaceList.add(flutterSurface);
            surfaceList.addAll(remainingSurfaces);
            createCaptureSession(surfaceList, callback);
        }
    }

    @TargetApi(VERSION_CODES.P)
    private void createCaptureSessionWithSessionConfig(
            List<OutputConfiguration> outputConfigs, CameraCaptureSession.StateCallback callback)
            throws CameraAccessException {
        cameraDevice.createCaptureSession(
                new SessionConfiguration(
                        SessionConfiguration.SESSION_REGULAR,
                        outputConfigs,
                        Executors.newSingleThreadExecutor(),
                        callback));
    }

    @TargetApi(VERSION_CODES.LOLLIPOP)
    @SuppressWarnings("deprecation")
    private void createCaptureSession(
            List<Surface> surfaces, CameraCaptureSession.StateCallback callback)
            throws CameraAccessException {
        cameraDevice.createCaptureSession(surfaces, callback, backgroundHandler);
    }

    // Send a repeating request to refresh  capture session.
    private void refreshPreviewCaptureSession(
            @Nullable Runnable onSuccessCallback,
            @NonNull ErrorCallback onErrorCallback
    ) {
        Log.i(TAG, "refreshPreviewCaptureSession");

        if (captureSession == null) {
            Log.i(
                    TAG,
                    "refreshPreviewCaptureSession: captureSession not yet initialized, "
                            + "skipping preview capture session refresh.");
            onErrorCallback.onError("refreshPreviewCaptureSession", "captureSession not yet initialized");
            return;
        }

        try {
            if (!pausedPreview) {
                captureSession.setRepeatingRequest(
                        previewRequestBuilder.build(),
                        cameraCaptureCallback,
                        backgroundHandler
                );
            }

            if (onSuccessCallback != null) {
                onSuccessCallback.run();
            }

        } catch (IllegalStateException e) {
            onErrorCallback.onError("refreshPreviewCaptureSession", "Camera is closed: " + e.getMessage());
        } catch (Exception e) {
            onErrorCallback.onError("refreshPreviewCaptureSession", e.getMessage());
        }
    }

    public void takePicture(@NonNull final Result result) {
        Log.w(TAG_CAPTURE, "takePicture() invoked");
        // Only take one picture at a time.
        if (cameraCaptureCallback.getCameraState() != CameraState.STATE_PREVIEW) {
            result.error("captureAlreadyActive", "Picture is currently already being captured", null);
            return;
        }

        flutterResult = result;

        // Create temporary file.
        final File outputDir = applicationContext.getCacheDir();
        try {
            captureFile = File.createTempFile("CAP", ".jpg", outputDir);
            captureTimeouts.reset();
        } catch (Exception e) {
            dartMessenger.error(flutterResult, "cannotCreateFile", e.getMessage(), null);
            return;
        }

        // Listen for picture being taken.
        pictureImageReader.setOnImageAvailableListener(this, backgroundHandler);

        final AutoFocusFeature autoFocusFeature = cameraFeatures.getAutoFocus();
        final boolean isAutoFocusSupported = autoFocusFeature.checkIsSupported();
        //if (isAutoFocusSupported && autoFocusFeature.getValue() == FocusMode.auto) {
        //    runPictureAutoFocus();
        //} else {
        runPrecaptureSequence();
        //}
    }

    /**
     * Run the precapture sequence for capturing a still image. This method should be called when a
     * response is received in {@link #cameraCaptureCallback} from lockFocus().
     */
    private void runPrecaptureSequence() {
        Log.i(TAG, "runPrecaptureSequence");
        try {
            // First set precapture state to idle or else it can hang in STATE_WAITING_PRECAPTURE_START.
            previewRequestBuilder.set(
                    CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER,
                    CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER_IDLE);
            captureSession.capture(
                    previewRequestBuilder.build(), cameraCaptureCallback, backgroundHandler);

            // Repeating request to refresh preview session.
            refreshPreviewCaptureSession(
                    null,
                    (code, message) -> dartMessenger.error(flutterResult, "cameraAccess", message, null));

            // Start precapture.
            cameraCaptureCallback.setCameraState(CameraState.STATE_WAITING_PRECAPTURE_START);

            previewRequestBuilder.set(
                    CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER,
                    CaptureRequest.CONTROL_AE_PRECAPTURE_TRIGGER_START);

            // Trigger one capture to start AE sequence.
            captureSession.capture(
                    previewRequestBuilder.build(), cameraCaptureCallback, backgroundHandler);

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    /**
     * Capture a still picture. This method should be called when a response is received {@link
     * #cameraCaptureCallback} from both lockFocus().
     */
    private void takePictureAfterPrecapture() {
        Log.i(TAG, "captureStillPicture");
        cameraCaptureCallback.setCameraState(CameraState.STATE_CAPTURING);

        if (cameraDevice == null) {
            return;
        }
        // This is the CaptureRequest.Builder that is used to take a picture.
        CaptureRequest.Builder stillBuilder;
        try {
            stillBuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
        } catch (Exception e) {
            dartMessenger.error(flutterResult, "cameraAccess", e.getMessage(), null);
            return;
        }
        stillBuilder.addTarget(pictureImageReader.getSurface());

        // Zoom.
        stillBuilder.set(
                CaptureRequest.SCALER_CROP_REGION,
                previewRequestBuilder.get(CaptureRequest.SCALER_CROP_REGION));

        // Have all features update the builder.
        updateBuilderSettings(stillBuilder);

        CameraCaptureSession.CaptureCallback captureCallback =
                new CameraCaptureSession.CaptureCallback() {
                    @Override
                    public void onCaptureCompleted(
                            @NonNull CameraCaptureSession session,
                            @NonNull CaptureRequest request,
                            @NonNull TotalCaptureResult result) {
                        Log.i(TAG, "CaptureCallback.onCaptureCompleted()");
                        unlockAutoFocus();
                    }

                    @Override
                    public void onCaptureStarted(@NonNull CameraCaptureSession session, @NonNull CaptureRequest request, long timestamp, long frameNumber) {
                        Log.i(TAG, "CaptureCallback.onCaptureStarted()");
                    }

                    @Override
                    public void onCaptureProgressed(@NonNull CameraCaptureSession session, @NonNull CaptureRequest request, @NonNull CaptureResult partialResult) {
                        Log.i(TAG, "CaptureCallback.onCaptureProgressed()");
                    }

                    @Override
                    public void onCaptureFailed(@NonNull CameraCaptureSession session, @NonNull CaptureRequest request, @NonNull CaptureFailure failure) {
                        Log.i(TAG, "CaptureCallback.onCaptureFailed(), reason:" + failure.getReason());
                    }

                    @Override
                    public void onCaptureSequenceCompleted(@NonNull CameraCaptureSession session, int sequenceId, long frameNumber) {
                        Log.i(TAG, "CaptureCallback.onCaptureSequenceCompleted()");
                    }

                    @Override
                    public void onCaptureSequenceAborted(@NonNull CameraCaptureSession session, int sequenceId) {
                        Log.i(TAG, "CaptureCallback.onCaptureSequenceAborted()");
                    }

                    @Override
                    public void onCaptureBufferLost(@NonNull CameraCaptureSession session, @NonNull CaptureRequest request, @NonNull Surface target, long frameNumber) {
                        Log.i(TAG, "CaptureCallback.onCaptureBufferLost()");
                    }
                };
        try {
            captureSession.stopRepeating();
            Log.i(TAG, "sending capture request");
            captureSession.capture(stillBuilder.build(), captureCallback, backgroundHandler);
        } catch (Exception e) {
            dartMessenger.error(flutterResult, "cameraAccess", e.getMessage(), null);
        }
    }

    @SuppressWarnings("deprecation")
    private Display getDefaultDisplay() {
        return activity.getWindowManager().getDefaultDisplay();
    }

    /**
     * Starts a background thread and its {@link Handler}.
     */
    public void startBackgroundThread() {
        if (backgroundHandlerThread != null) {
            return;
        }

        backgroundHandlerThread = HandlerThreadFactory.create("CameraBackground");
        try {
            backgroundHandlerThread.start();
        } catch (Exception e) {
            // Ignore exception in case the thread has already started.
        }
        backgroundHandler = HandlerFactory.create(backgroundHandlerThread.getLooper());
    }

    public void startBarcodeBackgroundThread() {
        if (barcodeBackgroundHandlerThread != null) {
            return;
        }

        barcodeBackgroundHandlerThread = HandlerThreadFactory.create("BarcodeBackground");
        try {
            barcodeBackgroundHandlerThread.start();
        } catch (Exception e) {
            // Ignore exception in case the thread has already started.
        }
        barcodeBackgroundHandler = HandlerFactory.create(barcodeBackgroundHandlerThread.getLooper());
    }

    /**
     * Stops the background thread and its {@link Handler}.
     */
    public void stopBackgroundThread() {
        if (backgroundHandlerThread != null) {
            backgroundHandlerThread.quit();
        }
        backgroundHandlerThread = null;
        backgroundHandler = null;
    }

    public void stopBarcodeBackgroundThread() {
        if (barcodeBackgroundHandlerThread != null) {
            barcodeBackgroundHandlerThread.quit();
        }
        barcodeBackgroundHandlerThread = null;
        barcodeBackgroundHandler = null;
    }


    /**
     * Start capturing a picture, doing autofocus first.
     */
    private void runPictureAutoFocus() {
        Log.i(TAG, "runPictureAutoFocus");

        cameraCaptureCallback.setCameraState(CameraState.STATE_WAITING_FOCUS);
        lockAutoFocus();
    }

    private void lockAutoFocus() {
        Log.i(TAG, "lockAutoFocus");
        if (captureSession == null) {
            Log.i(TAG, "[unlockAutoFocus] captureSession null, returning");
            return;
        }

        // Trigger AF to start.
        previewRequestBuilder.set(
                CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_START);

        try {
            captureSession.capture(previewRequestBuilder.build(), null, backgroundHandler);
        } catch (Exception e) {
            dartMessenger.sendCameraErrorEvent(e.getMessage());
        }
    }

    /**
     * Cancel and reset auto focus state and refresh the preview session.
     */
    private void unlockAutoFocus() {
        Log.i(TAG, "unlockAutoFocus");
        if (captureSession == null) {
            Log.i(TAG, "[unlockAutoFocus] captureSession null, returning");
            return;
        }
        try {
            // Cancel existing AF state.
            previewRequestBuilder.set(
                    CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_CANCEL);
            captureSession.capture(previewRequestBuilder.build(), null, backgroundHandler);

            // Set AF state to idle again.
            previewRequestBuilder.set(
                    CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_IDLE);

            captureSession.capture(previewRequestBuilder.build(), null, backgroundHandler);
        } catch (Exception e) {
            dartMessenger.sendCameraErrorEvent(e.getMessage());
            return;
        }

        refreshPreviewCaptureSession(
                null,
                (errorCode, errorMessage) ->
                        dartMessenger.error(flutterResult, errorCode, errorMessage, null));
    }

    public void startVideoRecording(@NonNull Result result) {
        final File outputDir = applicationContext.getCacheDir();
        try {
            captureFile = File.createTempFile("REC", ".mp4", outputDir);
        } catch (Exception e) {
            result.error("cannotCreateFile", e.getMessage(), null);
            return;
        }
        try {
            prepareMediaRecorder(captureFile.getAbsolutePath());
        } catch (Exception e) {
            recordingVideo = false;
            captureFile = null;
            result.error("videoRecordingFailed", e.getMessage(), null);
            return;
        }
        // Re-create autofocus feature so it's using video focus mode now.
        cameraFeatures.setAutoFocus(
                cameraFeatureFactory.createAutoFocusFeature(cameraProperties, true));
        recordingVideo = true;
        try {
            createCaptureSession(
                    CameraDevice.TEMPLATE_RECORD, () -> mediaRecorder.start(), mediaRecorder.getSurface());
            result.success(null);
        } catch (Exception e) {
            recordingVideo = false;
            captureFile = null;
            result.error("videoRecordingFailed", e.getMessage(), null);
        }
    }

    public void stopVideoRecording(@NonNull final Result result) {
        if (!recordingVideo) {
            result.success(null);
            return;
        }
        // Re-create autofocus feature so it's using continuous capture focus mode now.
        cameraFeatures.setAutoFocus(
                cameraFeatureFactory.createAutoFocusFeature(cameraProperties, false));
        recordingVideo = false;
        try {
            captureSession.abortCaptures();
            mediaRecorder.stop();
        } catch (Exception e) {
            // Ignore exceptions and try to continue (changes are camera session already aborted capture).
        }
        mediaRecorder.reset();
        try {
            startPreview();
        } catch (Exception e) {
            result.error("videoRecordingFailed", e.getMessage(), null);
            return;
        }
        result.success(captureFile.getAbsolutePath());
        captureFile = null;
    }

    public void pauseVideoRecording(@NonNull final Result result) {
        if (!recordingVideo) {
            result.success(null);
            return;
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                mediaRecorder.pause();
            } else {
                result.error("videoRecordingFailed", "pauseVideoRecording requires Android API +24.", null);
                return;
            }
        } catch (Exception e) {
            result.error("videoRecordingFailed", e.getMessage(), null);
            return;
        }

        result.success(null);
    }

    public void resumeVideoRecording(@NonNull final Result result) {
        if (!recordingVideo) {
            result.success(null);
            return;
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                mediaRecorder.resume();
            } else {
                result.error(
                        "videoRecordingFailed", "resumeVideoRecording requires Android API +24.", null);
                return;
            }
        } catch (Exception e) {
            result.error("videoRecordingFailed", e.getMessage(), null);
            return;
        }

        result.success(null);
    }

    /**
     * Method handler for setting new flash modes.
     *
     * @param result  Flutter result.
     * @param newMode new mode.
     */
    public void setFlashMode(@NonNull final Result result, @NonNull FlashMode newMode) {
        // Save the new flash mode setting.
        final FlashFeature flashFeature = cameraFeatures.getFlash();
        flashFeature.setValue(newMode);
        flashFeature.updateBuilder(previewRequestBuilder);

        refreshPreviewCaptureSession(
                () -> result.success(null),
                (code, message) -> result.error("setFlashModeFailed", "Could not set flash mode.", null));
    }

    /**
     * Method handler for setting new exposure modes.
     *
     * @param result  Flutter result.
     * @param newMode new mode.
     */
    public void setExposureMode(@NonNull final Result result, @NonNull ExposureMode newMode) {
        final ExposureLockFeature exposureLockFeature = cameraFeatures.getExposureLock();
        exposureLockFeature.setValue(newMode);
        exposureLockFeature.updateBuilder(previewRequestBuilder);

        refreshPreviewCaptureSession(
                () -> result.success(null),
                (code, message) ->
                        result.error("setExposureModeFailed", "Could not set exposure mode.", null));
    }

    /**
     * Sets new exposure point from dart.
     *
     * @param result Flutter result.
     * @param point  The exposure point.
     */
    public void setExposurePoint(@NonNull final Result result, @Nullable Point point) {
        final ExposurePointFeature exposurePointFeature = cameraFeatures.getExposurePoint();
        exposurePointFeature.setValue(point);
        exposurePointFeature.updateBuilder(previewRequestBuilder);

        refreshPreviewCaptureSession(
                () -> result.success(null),
                (code, message) ->
                        result.error("setExposurePointFailed", "Could not set exposure point.", null));
    }

    /**
     * Return the max exposure offset value supported by the camera to dart.
     */
    public double getMaxExposureOffset() {
        return cameraFeatures.getExposureOffset().getMaxExposureOffset();
    }

    /**
     * Return the min exposure offset value supported by the camera to dart.
     */
    public double getMinExposureOffset() {
        return cameraFeatures.getExposureOffset().getMinExposureOffset();
    }

    /**
     * Return the exposure offset step size to dart.
     */
    public double getExposureOffsetStepSize() {
        return cameraFeatures.getExposureOffset().getExposureOffsetStepSize();
    }

    /**
     * Sets new focus mode from dart.
     *
     * @param result  Flutter result.
     * @param newMode New mode.
     */
    public void setFocusMode(final Result result, @NonNull FocusMode newMode) {
        final AutoFocusFeature autoFocusFeature = cameraFeatures.getAutoFocus();
        autoFocusFeature.setValue(newMode);
        autoFocusFeature.updateBuilder(previewRequestBuilder);

        /*
         * For focus mode an extra step of actually locking/unlocking the
         * focus has to be done, in order to ensure it goes into the correct state.
         */
        if (!pausedPreview) {
            switch (newMode) {
                case locked:
                    // Perform a single focus trigger.
                    if (captureSession == null) {
                        Log.i(TAG, "[unlockAutoFocus] captureSession null, returning");
                        return;
                    }
                    lockAutoFocus();

                    // Set AF state to idle again.
                    previewRequestBuilder.set(
                            CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_IDLE);

                    try {
                        captureSession.setRepeatingRequest(
                                previewRequestBuilder.build(), null, backgroundHandler);
                    } catch (Exception e) {
                        if (result != null) {
                            result.error(
                                    "setFocusModeFailed", "Error setting focus mode: " + e.getMessage(), null);
                        }
                        return;
                    }
                    break;
                case auto:
                    // Cancel current AF trigger and set AF to idle again.
                    unlockAutoFocus();
                    break;
            }
        }

        if (result != null) {
            result.success(null);
        }
    }

    /**
     * Sets new focus point from dart.
     *
     * @param result Flutter result.
     * @param point  the new coordinates.
     */
    public void setFocusPoint(@NonNull final Result result, @Nullable Point point) {
        final FocusPointFeature focusPointFeature = cameraFeatures.getFocusPoint();
        focusPointFeature.setValue(point);
        focusPointFeature.updateBuilder(previewRequestBuilder);

        refreshPreviewCaptureSession(
                () -> result.success(null),
                (code, message) -> result.error("setFocusPointFailed", "Could not set focus point.", null));

        this.setFocusMode(null, cameraFeatures.getAutoFocus().getValue());
    }

    /**
     * Sets a new exposure offset from dart. From dart the offset comes as a double, like +1.3 or
     * -1.3.
     *
     * @param result flutter result.
     * @param offset new value.
     */
    public void setExposureOffset(@NonNull final Result result, double offset) {
        final ExposureOffsetFeature exposureOffsetFeature = cameraFeatures.getExposureOffset();
        exposureOffsetFeature.setValue(offset);
        exposureOffsetFeature.updateBuilder(previewRequestBuilder);

        refreshPreviewCaptureSession(
                () -> result.success(exposureOffsetFeature.getValue()),
                (code, message) ->
                        result.error("setExposureOffsetFailed", "Could not set exposure offset.", null));
    }

    public float getMaxZoomLevel() {
        return cameraFeatures.getZoomLevel().getMaximumZoomLevel();
    }

    public float getMinZoomLevel() {
        return cameraFeatures.getZoomLevel().getMinimumZoomLevel();
    }

    /**
     * Shortcut to get current recording profile. Legacy method provides support for SDK < 31.
     */
    CamcorderProfile getRecordingProfileLegacy() {
        return cameraFeatures.getResolution().getRecordingProfileLegacy();
    }

    /**
     * Shortut to get deviceOrientationListener.
     */
    DeviceOrientationManager getDeviceOrientationManager() {
        return cameraFeatures.getSensorOrientation().getDeviceOrientationManager();
    }

    /**
     * Sets zoom level from dart.
     *
     * @param result Flutter result.
     * @param zoom   new value.
     */
    public void setZoomLevel(@NonNull final Result result, float zoom) throws CameraAccessException {
        final ZoomLevelFeature zoomLevel = cameraFeatures.getZoomLevel();
        float maxZoom = zoomLevel.getMaximumZoomLevel();
        float minZoom = zoomLevel.getMinimumZoomLevel();

        if (zoom > maxZoom || zoom < minZoom) {
            String errorMessage =
                    String.format(
                            Locale.ENGLISH,
                            "Zoom level out of bounds (zoom level should be between %f and %f).",
                            minZoom,
                            maxZoom);
            result.error("ZOOM_ERROR", errorMessage, null);
            return;
        }

        zoomLevel.setValue(zoom);
        zoomLevel.updateBuilder(previewRequestBuilder);

        refreshPreviewCaptureSession(
                () -> result.success(null),
                (code, message) -> result.error("setZoomLevelFailed", "Could not set zoom level.", null));
    }

    /**
     * Pause the preview from dart.
     */
    public void pausePreview() throws CameraAccessException {
        this.pausedPreview = true;
        this.captureSession.stopRepeating();
    }

    /**
     * Resume the preview from dart.
     */
    public void resumePreview() {
        this.pausedPreview = false;
        this.refreshPreviewCaptureSession(
                null, (code, message) -> dartMessenger.sendCameraErrorEvent(message));
    }

    public void startPreview() throws CameraAccessException {
        if (pictureImageReader == null || pictureImageReader.getSurface() == null) return;
        Log.i(TAG, "startPreview");

        createCaptureSession(CameraDevice.TEMPLATE_PREVIEW, pictureImageReader.getSurface());
    }

    public void startPreviewWithBarcodeStream(BarcodeCaptureSettings settings,
                                              EventChannel barcodeEventChannel
    ) throws CameraAccessException {
        setBarcodeStreamAvailableListener(settings);

        createCaptureSession(CameraDevice.TEMPLATE_RECORD, imageStreamReader.getSurface());
        Log.i(TAG, "startPreviewWithBarcodeStream");

        barcodeEventChannel.setStreamHandler(
                new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object o, EventChannel.EventSink barcodeStreamSink) {
                        Camera.this.barcodeStreamSink = barcodeStreamSink;
                        nextImageIsRequestedToBarcodeScan = true;
                    }

                    @Override
                    public void onCancel(Object o) {
                        if (imageStreamReader != null) {
                            imageStreamReader.setOnImageAvailableListener(null, backgroundHandler);
                        }
                        nextImageIsRequestedToBarcodeScan = false;
                        Camera.this.barcodeStreamSink = null;
                    }
                });
    }

    /**
     * This a callback object for the {@link ImageReader}. "onImageAvailable" will be called when a
     * still image is ready to be saved.
     */
    @Override
    public void onImageAvailable(ImageReader reader) {
        Log.i(TAG, "onImageAvailable");
        Log.w(TAG_CAPTURE, "onImageAvailable");

        backgroundHandler.post(
                new ImageSaver(
                        // Use acquireNextImage since image reader is only for one image.
                        reader.acquireNextImage(),
                        captureFile,
                        cameraFeatures.getResolution().getLongSideSize(),
                        cameraFeatures.getSensorOrientation().getDeviceOrientationManager().getDeviceTilts(),
                        cameraFeatures.getResolution().getImageQuality(),
                        cameraFeatures.getSensorOrientation().getValue(),
                        new ImageSaver.Callback() {
                            @Override
                            public void onComplete(TakePictureResult result) {
                                dartMessenger.finish(flutterResult, result.getMap());
                                Log.w(TAG_CAPTURE, "ImageSaver.onComplete()");
                            }

                            @Override
                            public void onError(String errorCode, String errorMessage) {
                                dartMessenger.error(flutterResult, errorCode, errorMessage, null);
                                Log.w(TAG_CAPTURE, "ImageSaver.onError()");
                            }
                        }));
        cameraCaptureCallback.setCameraState(CameraState.STATE_PREVIEW);
    }

    private void setBarcodeStreamAvailableListener(BarcodeCaptureSettings settings) {
        final MultiFormatReader barcodeReader = new MultiFormatReader();
        final Map<DecodeHintType, Object> hints = new HashMap<>();
        final List<BarcodeFormat> formats = new ArrayList<>();
        formats.add(BarcodeFormat.EAN_8);
        formats.add(BarcodeFormat.EAN_13);
        formats.add(BarcodeFormat.RSS_EXPANDED);
        formats.add(BarcodeFormat.RSS_14);
        hints.put(DecodeHintType.POSSIBLE_FORMATS, formats);
        barcodeReader.setHints(hints);

        imageStreamReader.setOnImageAvailableListener(
                reader -> {
                    Image img = reader.acquireNextImage();
                    // Use acquireNextImage since image reader is only for one image.
                    if (img == null) return;

                    if (!nextImageIsRequestedToBarcodeScan || barcodeStreamSink == null) {
                        img.close();
                        return;
                    }

                    nextImageIsRequestedToBarcodeScan = false;
                    final ImageBytes bytes = getBytesFromImage(img);
                    img.close();

                    if (bytes == null || barcodeBackgroundHandler == null) return;

                    barcodeBackgroundHandler.post(() -> {
                        try {
                            final int targetImageRotation = getTargetImageRotation();
                            ImageBytes downscaledBytes = rotateImageBytes(bytes, targetImageRotation);
                            downscaledBytes = cropImageBytes(
                                    downscaledBytes,
                                    settings.cropLeft,
                                    settings.cropRight,
                                    settings.cropTop,
                                    settings.cropBottom
                            );

                            for (int step = 0; step < 4; step++) {
                                final LuminanceSource luminanceSource =
                                        downscaledBytes.getImageFormat() == ImageFormat.YUV_420_888 ?
                                                new PlanarYUVLuminanceSource(
                                                        downscaledBytes.getBytes(),
                                                        downscaledBytes.getWidth(),
                                                        downscaledBytes.getHeight(),
                                                        0,
                                                        0,
                                                        downscaledBytes.getWidth(),
                                                        downscaledBytes.getHeight(),
                                                        false
                                                ) : new RGBLuminanceSource(
                                                downscaledBytes.getWidth(),
                                                downscaledBytes.getHeight(),
                                                downscaledBytes.getPixels()
                                        );


                                final Binarizer binarizer = new GlobalHistogramBinarizer(luminanceSource);
                                final BinaryBitmap binaryBitmap = new BinaryBitmap(binarizer);

                                try {
                                    final com.google.zxing.Result decodeResult = barcodeReader.decodeWithState(binaryBitmap);
                                    final CameraBarcode cameraBarcode = new CameraBarcode(
                                            decodeResult.getText(),
                                            decodeResult.getBarcodeFormat().toString(),
                                            null);


                                    sendCameraBarcodeEvent(cameraBarcode);

                                    Log.d(TAG, "Decode step: " + step);
                                    Log.d(TAG, decodeResult.getBarcodeFormat().toString());
                                    Log.d(TAG, decodeResult.getText());
                                    break;
                                } catch (NotFoundException notFoundException) {
                                    downscaledBytes = downscaleImageBytes(downscaledBytes);
                                }
                            }
                        } catch (Exception exception) {
                            Log.e(TAG, "Barcode exception", exception);
                            final CameraBarcode cameraBarcode = new CameraBarcode(
                                    null,
                                    null,
                                    exception.toString());
                            sendCameraBarcodeEvent(cameraBarcode);
                        }
                        nextImageIsRequestedToBarcodeScan = true;
                    });
                },
                backgroundHandler);
    }

    private void sendCameraBarcodeEvent(final CameraBarcode cameraBarcode) {
        final Handler handler = new Handler(Looper.getMainLooper());
        handler.post(() -> {
            if (barcodeStreamSink != null) {
                barcodeStreamSink.success(cameraBarcode.getMap());
            }
        });
    }

    private int getTargetImageRotation() {
        final SensorOrientationFeature sensorOrientation = cameraFeatures.getSensorOrientation();
        final DeviceOrientationManager deviceOrientationManager = sensorOrientation
                .getDeviceOrientationManager();
        final io.flutter.plugins.camera.types.DeviceTilts deviceTilts = deviceOrientationManager
                .getDeviceTilts();

        final Integer sensorOrientationAngle = sensorOrientation.getValue();
        final int sensorAngle = sensorOrientationAngle != null ? sensorOrientationAngle : 0;

        if (deviceTilts.lockedCaptureAngle == -1) {
            return (int) deviceTilts.targetImageRotation + sensorAngle;
        } else {
            return deviceOrientationManager.getUIOrientationAngle()
                    + deviceTilts.lockedCaptureAngle
                    + sensorAngle;
        }
    }

    private ImageBytes downscaleImageBytes(ImageBytes srcImageBytes) {
        final int srcWidth = srcImageBytes.getWidth();
        final int dstWidth = srcWidth / 2;
        final int dstHeight = srcImageBytes.getHeight() / 2;
        if (srcImageBytes.getBytes() != null) {
            final byte[] srcBytes = srcImageBytes.getBytes();
            byte[] dstBytes = new byte[dstWidth * dstHeight];

            for (int rowIndex = 0; rowIndex < dstHeight; rowIndex++) {
                for (int colIndex = 0; colIndex < dstWidth; colIndex++) {
                    final int byte00 = srcBytes[rowIndex * srcWidth * 2 + colIndex * 2];
                    final int byte01 = srcBytes[rowIndex * srcWidth * 2 + colIndex * 2 + 1];
                    final int byte10 = srcBytes[(rowIndex * 2 + 1) * srcWidth + colIndex * 2];
                    final int byte11 = srcBytes[(rowIndex * 2 + 1) * srcWidth + colIndex * 2 + 1];

                    final byte dstByte = (byte) Math.min(Math.min(byte00, byte01), Math.min(byte10, byte11));

                    dstBytes[rowIndex * dstWidth + colIndex] = dstByte;
                }
            }
            return new ImageBytes(dstWidth, dstHeight, dstBytes, null, srcImageBytes.getImageFormat());
        }
        if (srcImageBytes.getPixels() != null) {
            final int[] srcPixels = srcImageBytes.getPixels();
            int[] dstPixels = new int[dstWidth * dstHeight];

            for (int rowIndex = 0; rowIndex < dstHeight; rowIndex++) {
                for (int colIndex = 0; colIndex < dstWidth; colIndex++) {
                    final int pixel00 = srcPixels[rowIndex * srcWidth * 2 + colIndex * 2];
                    final int pixel01 = srcPixels[rowIndex * srcWidth * 2 + colIndex * 2 + 1];
                    final int pixel10 = srcPixels[(rowIndex * 2 + 1) * srcWidth + colIndex * 2];
                    final int pixel11 = srcPixels[(rowIndex * 2 + 1) * srcWidth + colIndex * 2 + 1];

                    // final int dstByte = Math.min(Math.min(pixel00, pixel01), Math.min(pixel10, pixel11));

                    dstPixels[rowIndex * dstWidth + colIndex] = pixel00;
                }
            }
            return new ImageBytes(dstWidth, dstHeight, null, dstPixels, srcImageBytes.getImageFormat());
        }
        return srcImageBytes;
    }

    private ImageBytes rotateImageBytes(ImageBytes srcBytes, int angle) {
        switch (angle) {
            case 90:
            case -270:
                return rotateImageBytes90(srcBytes, true);
            case 180:
            case -180:
                return rotateImageBytes180(srcBytes);
            case -90:
            case 270:
                return rotateImageBytes90(srcBytes, false);
            default:
                return srcBytes;
        }
    }

    private ImageBytes rotateImageBytes90(ImageBytes srcImageBytes, boolean isClockWise) {
        final int srcHeight = srcImageBytes.getHeight();
        final int srcWidth = srcImageBytes.getWidth();

        if (srcImageBytes.getBytes() != null) {
            final byte[] srcBytes = srcImageBytes.getBytes();
            final byte[] dstBytes = new byte[srcBytes.length];

            for (int srcRowIndex = 0; srcRowIndex < srcHeight; srcRowIndex++) {
                for (int srcColIndex = 0; srcColIndex < srcWidth; srcColIndex++) {
                    final byte curByte = srcBytes[srcRowIndex * srcWidth + srcColIndex];
                    if (isClockWise) {
                        dstBytes[srcHeight - srcRowIndex - 1 + srcColIndex * srcHeight] = curByte;
                    } else {
                        dstBytes[srcRowIndex + (srcWidth - srcColIndex - 1) * srcHeight] = curByte;
                    }
                }
            }
            return new ImageBytes(srcHeight, srcWidth, dstBytes, null, srcImageBytes.getImageFormat());
        }

        if (srcImageBytes.getPixels() != null) {
            final int[] srcPixels = srcImageBytes.getPixels();
            final int[] dstPixels = new int[srcPixels.length];

            for (int srcRowIndex = 0; srcRowIndex < srcHeight; srcRowIndex++) {
                for (int srcColIndex = 0; srcColIndex < srcWidth; srcColIndex++) {
                    final int curPixel = srcPixels[srcRowIndex * srcWidth + srcColIndex];
                    if (isClockWise) {
                        dstPixels[srcHeight - srcRowIndex - 1 + srcColIndex * srcHeight] = curPixel;
                    } else {
                        dstPixels[srcRowIndex + (srcWidth - srcColIndex - 1) * srcHeight] = curPixel;
                    }
                }
            }
            return new ImageBytes(srcHeight, srcWidth, null, dstPixels, srcImageBytes.getImageFormat());
        }

        return srcImageBytes;
    }

    private ImageBytes rotateImageBytes180(ImageBytes srcImageBytes) {
        final int srcHeight = srcImageBytes.getHeight();
        final int srcWidth = srcImageBytes.getWidth();
        if (srcImageBytes.getBytes() != null) {
            final byte[] srcBytes = srcImageBytes.getBytes();
            final byte[] dstBytes = new byte[srcBytes.length];

            for (int srcRowIndex = 0; srcRowIndex < srcHeight; srcRowIndex++) {
                for (int srcColIndex = 0; srcColIndex < srcWidth; srcColIndex++) {
                    final byte curByte = srcBytes[srcRowIndex * srcWidth + srcColIndex];
                    dstBytes[(srcHeight - srcRowIndex) * srcWidth - srcColIndex - 1] = curByte;
                }
            }
            return new ImageBytes(srcWidth, srcHeight, dstBytes, null, srcImageBytes.getImageFormat());
        }
        if (srcImageBytes.getPixels() != null) {
            final int[] srcPixels = srcImageBytes.getPixels();
            final int[] dstPixels = new int[srcPixels.length];

            for (int srcRowIndex = 0; srcRowIndex < srcHeight; srcRowIndex++) {
                for (int srcColIndex = 0; srcColIndex < srcWidth; srcColIndex++) {
                    final int curPixel = srcPixels[srcRowIndex * srcWidth + srcColIndex];
                    dstPixels[(srcHeight - srcRowIndex) * srcWidth - srcColIndex - 1] = curPixel;
                }
            }
            return new ImageBytes(srcWidth, srcHeight, null, dstPixels, srcImageBytes.getImageFormat());
        }
        return srcImageBytes;
    }

    private ImageBytes getBytesFromImage(Image image) {
        try {
            if (image.getFormat() == ImageFormat.JPEG) {
                return getBytesFromJpegImage(image);
            } else if (image.getFormat() == ImageFormat.YUV_420_888) {
                return removeStridesFromImage(image);
            }
            return null;
        } catch (Exception exception) {
            Log.e(TAG, "Barcode getBytesFromImage exception", exception);
            final CameraBarcode cameraBarcode = new CameraBarcode(
                    null,
                    null,
                    exception.toString());
            sendCameraBarcodeEvent(cameraBarcode);
            return null;
        }
    }

    @NonNull
    private ImageBytes getBytesFromJpegImage(Image image) {
        Image.Plane[] planes = image.getPlanes();
        ByteBuffer buffer = planes[0].getBuffer();
        byte[] data = new byte[buffer.capacity()];
        buffer.get(data);

        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(data, 0, data.length, options);
        if (options.outWidth == -1 || options.outHeight == -1) {
            throw new Error("JPEG conversation error, options is " + options);
        }
        options.inSampleSize = 1;
        options.inJustDecodeBounds = false;
        options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        final Bitmap srcBitmap = BitmapFactory.decodeByteArray(data, 0, data.length, options);
        final int width = srcBitmap.getWidth();
        final int height = srcBitmap.getHeight();
        final int[] pixels = new int[width * height];
        srcBitmap.getPixels(pixels, 0, width, 0, 0, width, height);
        srcBitmap.recycle();
        return new ImageBytes(
                width,
                height,
                null,
                pixels,
                ImageFormat.JPEG);
    }

    private ImageBytes removeStridesFromImage(Image image) {
        Rect crop = image.getCropRect();
        int width = crop.width();
        int height = crop.height();
        Image.Plane[] planes = image.getPlanes();
        byte[] data = new byte[width * height];
        byte[] rowData = new byte[planes[0].getRowStride()];

        int channelOffset = 0;
        int outputStride = 1;

        ByteBuffer buffer = planes[0].getBuffer();
        int rowStride = planes[0].getRowStride();
        int pixelStride = planes[0].getPixelStride();

        int shift = 0;
        int w = width >> shift;
        int h = height >> shift;
        buffer.position(rowStride * (crop.top >> shift) + pixelStride * (crop.left >> shift));
        for (int row = 0; row < h; row++) {
            int length;
            if (pixelStride == 1) {
                length = w;
                buffer.get(data, channelOffset, length);
                channelOffset += length;
            } else {
                length = (w - 1) * pixelStride + 1;
                buffer.get(rowData, 0, length);
                for (int col = 0; col < w; col++) {
                    data[channelOffset] = rowData[col * pixelStride];
                    channelOffset += outputStride;
                }
            }
            if (row < h - 1) {
                buffer.position(buffer.position() + rowStride - length);
            }
        }
        return new ImageBytes(width, height, data, null, ImageFormat.YUV_420_888);
    }

    private ImageBytes cropImageBytes(ImageBytes srcImageBytes,
                                      int left,
                                      int right,
                                      int top,
                                      int bottom) {
        int leftOffset = 0;
        int rightOffset = 0;
        int topOffset = 0;
        int bottomOffset = 0;

        if (left > 0 && right > 0 && left + right < 100) {
            leftOffset = srcImageBytes.getWidth() * left / 100;
            rightOffset = srcImageBytes.getWidth() * right / 100;
        }

        if (top > 0 && bottom > 0 && top + bottom < 100) {
            topOffset = srcImageBytes.getHeight() * top / 100;
            bottomOffset = srcImageBytes.getHeight() * bottom / 100;
        }


        final int srcWidth = srcImageBytes.getWidth();
        final int srcHeight = srcImageBytes.getHeight();

        final int dstWidth = srcWidth - leftOffset - rightOffset;
        final int dstHeight = srcHeight - topOffset - bottomOffset;

        if (srcImageBytes.getBytes() != null) {
            final byte[] srcBytes = srcImageBytes.getBytes();
            final byte[] dstBytes = new byte[dstWidth * dstHeight];

            for (int rowIndex = topOffset; rowIndex < topOffset + dstHeight; rowIndex++) {
                System.arraycopy(
                        srcBytes,
                        rowIndex * srcWidth + leftOffset,
                        dstBytes,
                        (rowIndex - topOffset) * dstWidth,
                        dstWidth
                );
            }
            return new ImageBytes(dstWidth, dstHeight, dstBytes, null, srcImageBytes.getImageFormat());
        }

        if (srcImageBytes.getPixels() != null) {
            final int[] srcPixels = srcImageBytes.getPixels();
            final int[] dstPixels = new int[dstWidth * dstHeight];

            for (int rowIndex = topOffset; rowIndex < topOffset + dstHeight; rowIndex++) {
                System.arraycopy(
                        srcPixels,
                        rowIndex * srcWidth + leftOffset,
                        dstPixels,
                        (rowIndex - topOffset) * dstWidth,
                        dstWidth
                );
            }
            return new ImageBytes(dstWidth, dstHeight, null, dstPixels, srcImageBytes.getImageFormat());
        }
        return srcImageBytes;
    }

    private void closeCaptureSession() {
        if (captureSession != null) {
            Log.i(TAG, "closeCaptureSession");

            captureSession.close();
            captureSession = null;
        }
    }

    public void close() {
        Log.i(TAG, "close");
        closeCaptureSession();

        if (cameraDevice != null) {
            cameraDevice.close();
            cameraDevice = null;
        }
        if (pictureImageReader != null) {
            pictureImageReader.close();
            pictureImageReader = null;
        }
        if (imageStreamReader != null) {
            imageStreamReader.close();
            imageStreamReader = null;
        }
        if (mediaRecorder != null) {
            mediaRecorder.reset();
            mediaRecorder.release();
            mediaRecorder = null;
        }

        stopBackgroundThread();
        stopBarcodeBackgroundThread();
    }

    public void dispose() {
        Log.i(TAG, "dispose");

        close();
        flutterTexture.release();
        getDeviceOrientationManager().stop();
    }

    /**
     * Factory class that assists in creating a {@link HandlerThread} instance.
     */
    static class HandlerThreadFactory {
        /**
         * Creates a new instance of the {@link HandlerThread} class.
         *
         * <p>This method is visible for testing purposes only and should never be used outside this *
         * class.
         *
         * @param name to give to the HandlerThread.
         * @return new instance of the {@link HandlerThread} class.
         */
        @VisibleForTesting
        public static HandlerThread create(String name) {
            return new HandlerThread(name);
        }
    }

    /**
     * Factory class that assists in creating a {@link Handler} instance.
     */
    static class HandlerFactory {
        /**
         * Creates a new instance of the {@link Handler} class.
         *
         * <p>This method is visible for testing purposes only and should never be used outside this *
         * class.
         *
         * @param looper to give to the Handler.
         * @return new instance of the {@link Handler} class.
         */
        @VisibleForTesting
        public static Handler create(Looper looper) {
            return new Handler(looper);
        }
    }
}
