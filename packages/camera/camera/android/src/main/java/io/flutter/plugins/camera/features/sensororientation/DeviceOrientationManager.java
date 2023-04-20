// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.sensororientation;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.res.Configuration;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.util.Log;
import android.view.Display;
import android.view.OrientationEventListener;
import android.view.Surface;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.VisibleForTesting;

import io.flutter.embedding.engine.systemchannels.PlatformChannel;
import io.flutter.embedding.engine.systemchannels.PlatformChannel.DeviceOrientation;
import io.flutter.plugins.camera.DartMessenger;
import io.flutter.plugins.camera.types.DeviceTilts;
import io.flutter.plugins.camera.types.TakePictureMode;

/**
 * Support class to help to determine the media orientation based on the orientation of the device.
 */
public class DeviceOrientationManager implements SensorEventListener {

    private static final IntentFilter orientationIntentFilter =
            new IntentFilter(Intent.ACTION_CONFIGURATION_CHANGED);

    private static final String TAG = "DeviceOrientationMng";

    private final Activity activity;
    private final DartMessenger messenger;
    private final boolean isFrontFacing;
    private PlatformChannel.DeviceOrientation accelerometerOrientation;
    private PlatformChannel.DeviceOrientation uiOrientation;
    private BroadcastReceiver broadcastReceiver;
    private OrientationEventListener orientationEventListener;
    private final SensorManager sensorManager;

    private final float[] rotationMatrix = new float[9];
    private final float[] orientationAngles = new float[3];
    private double horizontalTilt = 0;
    private double horizontalTiltOverhead = 0;
    private double verticalTilt = 0;
    private double verticalTiltOverhead = 0;
    private boolean isHorizontalTiltAvailable = false;
    private boolean isVerticalTiltAvailable = false;
    private TakePictureMode takePictureMode = TakePictureMode.unknownShot;
    private double targetImageRotation = 0;
    private final PlatformChannel.DeviceOrientation lockedCaptureOrientation;
    private int lockedCaptureAngle = -1;
    private int deviceOrientationAngle = 0;

    public int getUIOrientationAngle() {
        return getOrientationAngle(uiOrientation);
    }

    /**
     * Factory method to create a device orientation manager.
     */
    public static DeviceOrientationManager create(
            @NonNull Activity activity,
            @NonNull DartMessenger messenger,
            PlatformChannel.DeviceOrientation lockedCaptureOrientation,
            boolean isFrontFacing) {
        return new DeviceOrientationManager(activity, messenger, lockedCaptureOrientation, isFrontFacing);
    }

    private DeviceOrientationManager(
            @NonNull Activity activity,
            @NonNull DartMessenger messenger,
            PlatformChannel.DeviceOrientation lockedCaptureOrientation,
            boolean isFrontFacing) {
        this.activity = activity;
        this.messenger = messenger;
        this.isFrontFacing = isFrontFacing;
        this.sensorManager = (SensorManager) activity.getSystemService(Context.SENSOR_SERVICE);
        this.lockedCaptureOrientation = lockedCaptureOrientation;
        lockedCaptureAngle = lockedCaptureOrientation != null
                ? getOrientationAngle(lockedCaptureOrientation)
                : -1;
        orientationAngles[0] = 0;
        orientationAngles[1] = 1.54f;
        orientationAngles[2] = 1.54f;
        targetImageRotation = 0;
    }

    public void start() {
        startSensorListener();
        startUIListener();
    }

    public void stop() {
        stopSensorListener();
        stopUIListener();
    }

    private void startSensorListener() {
        if (orientationEventListener != null) return;

        messenger.sendDeviceLogInfoMessageEvent("Start sensor listener");

        Sensor rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR);
        if (rotationSensor == null) {
            messenger.sendDeviceLogInfoMessageEvent(
                    "Game rotation vector sensor is not available. " +
                            "Trying to use rotation vector sensor."
            );
            rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
        }
        if (rotationSensor != null) {
            final String message = "Rotation sensor has been initialized";
            Log.i(TAG, message);
            messenger.sendDeviceLogInfoMessageEvent(message);
            sensorManager.registerListener(this, rotationSensor,
                    SensorManager.SENSOR_DELAY_NORMAL, SensorManager.SENSOR_DELAY_UI);
            isVerticalTiltAvailable = true;
        } else {
            final String message = "Rotation sensor has NOT been initialized";
            Log.w(TAG, message);
            messenger.sendDeviceLogErrorMessageEvent(message);
            isVerticalTiltAvailable = false;
            takePictureMode = TakePictureMode.unknownShot;
        }

        orientationEventListener =
                new OrientationEventListener(activity, SensorManager.SENSOR_DELAY_NORMAL) {
                    @Override
                    public void onOrientationChanged(int angle) {
                        PlatformChannel.DeviceOrientation newOrientation = calculateSensorOrientation(angle);
                        if (!newOrientation.equals(accelerometerOrientation) && isOrientationChangeAllowed()) {
                            final String message = "OrientationEventListener set orientation:" + newOrientation;
                            Log.d(TAG, message);
                            messenger.sendDeviceLogInfoMessageEvent(message);
                            accelerometerOrientation = newOrientation;
                            messenger.sendDeviceOrientationChangeEvent(newOrientation);
                        }
                        if (isOrientationChangeAllowed()) {
                            isHorizontalTiltAvailable = angle != ORIENTATION_UNKNOWN;
                            if (angle == ORIENTATION_UNKNOWN) {
                                takePictureMode = TakePictureMode.unknownShot;
                            }
                        }
                        double relativeAngle = getOrientationAngle(accelerometerOrientation) - angle;
                        if (relativeAngle < -180) {
                            relativeAngle += 360;
                        }
                        horizontalTilt = relativeAngle;

                        if (lockedCaptureOrientation == null) {
                            targetImageRotation = getOrientationAngle(uiOrientation);
                        } else {
                            targetImageRotation = getOrientationAngle(accelerometerOrientation);
                        }
                        if (takePictureMode != TakePictureMode.overheadShot) {
                            sendDeviceTiltsChangeEvent();
                        }
                    }
                };
        if (orientationEventListener.canDetectOrientation()) {
            isHorizontalTiltAvailable = true;
            orientationEventListener.enable();
            messenger.sendDeviceLogInfoMessageEvent("OrientationEventListener can detect orientation");
        } else {
            isHorizontalTiltAvailable = false;
            takePictureMode = TakePictureMode.unknownShot;
            messenger.sendDeviceLogErrorMessageEvent("OrientationEventListener can not detect orientation");
        }
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        if (event.sensor.getType() == Sensor.TYPE_GAME_ROTATION_VECTOR
                || event.sensor.getType() == Sensor.TYPE_ROTATION_VECTOR) {
            SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values);
            SensorManager.getOrientation(rotationMatrix, orientationAngles);
            verticalTilt = Math.asin(Math.sqrt(Math.pow(event.values[0], 2)
                    + Math.pow(event.values[1], 2))) * 360 / Math.PI
                    - 90;

            if (verticalTilt >= -45 && verticalTilt <= 45) {
                takePictureMode = TakePictureMode.normalShot;
            } else {
                takePictureMode = TakePictureMode.overheadShot;
                isVerticalTiltAvailable = true;
                isHorizontalTiltAvailable = true;
                final double pitch = orientationAngles[1] * 180 / Math.PI;
                final double roll = orientationAngles[2] * 180 / Math.PI;

                switch ((int) targetImageRotation) {
                    case 0:
                        verticalTiltOverhead = -pitch;
                        horizontalTiltOverhead = -roll;
                        break;
                    case 90:
                        verticalTiltOverhead = roll;
                        horizontalTiltOverhead = -pitch;
                        break;
                    case 180:
                        verticalTiltOverhead = pitch;
                        horizontalTiltOverhead = roll;
                        break;
                    case 270:
                        verticalTiltOverhead = -roll;
                        horizontalTiltOverhead = pitch;
                        break;
                }
            }
            sendDeviceTiltsChangeEvent();
        }
    }

    private void sendDeviceTiltsChangeEvent() {
        final DeviceTilts deviceTilts = getDeviceTilts();
        //Log.d(TAG, "Device tilts:" + deviceTilts.toString());
        messenger.sendDeviceTiltsChangeEvent(deviceTilts);
    }

    private boolean isOrientationChangeAllowed() {
        return takePictureMode == TakePictureMode.normalShot
                || takePictureMode == TakePictureMode.unknownShot;
    }

    private void startUIListener() {
        if (broadcastReceiver != null) return;
        broadcastReceiver =
                new BroadcastReceiver() {
                    @Override
                    public void onReceive(Context context, Intent intent) {
                        PlatformChannel.DeviceOrientation orientation = getUIOrientation();
                        if (!orientation.equals(uiOrientation) && isOrientationChangeAllowed()) {
                            Log.d(TAG, "UI orientation set:" + orientation.toString());
                            uiOrientation = orientation;
                            messenger.sendDeviceOrientationChangeEvent(uiOrientation);
                        }
                    }
                };
        activity.registerReceiver(broadcastReceiver, orientationIntentFilter);
        broadcastReceiver.onReceive(activity, null);
    }

    private void stopSensorListener() {
        if (orientationEventListener == null) return;
        orientationEventListener.disable();
        orientationEventListener = null;
        sensorManager.unregisterListener(this);
    }

    private void stopUIListener() {
        if (broadcastReceiver == null) return;
        activity.unregisterReceiver(broadcastReceiver);
        broadcastReceiver = null;
    }


//    /**
//     * Starts listening to the device's sensors or UI for orientation updates.
//     *
//     * <p>When orientation information is updated the new orientation is send to the client using the
//     * {@link DartMessenger}. This latest value can also be retrieved through the {@link
//     * #getVideoOrientation()} accessor.
//     *
//     * <p>If the device's ACCELEROMETER_ROTATION setting is enabled the {@link
//     * DeviceOrientationManager} will report orientation updates based on the sensor information. If
//     * the ACCELEROMETER_ROTATION is disabled the {@link DeviceOrientationManager} will fallback to
//     * the deliver orientation updates based on the UI orientation.
//     */
//    public void start() {
//        if (broadcastReceiver != null) {
//            return;
//        }
//        broadcastReceiver =
//                new BroadcastReceiver() {
//                    @Override
//                    public void onReceive(Context context, Intent intent) {
//                        handleUIOrientationChange();
//                    }
//                };
//        activity.registerReceiver(broadcastReceiver, orientationIntentFilter);
//        broadcastReceiver.onReceive(activity, null);
//    }
//
//    /**
//     * Stops listening for orientation updates.
//     */
//    public void stop() {
//        if (broadcastReceiver == null) {
//            return;
//        }
//        activity.unregisterReceiver(broadcastReceiver);
//        broadcastReceiver = null;
//    }

    /**
     * Returns the device's photo orientation in degrees based on the sensor orientation and the last
     * known UI orientation.
     *
     * <p>Returns one of 0, 90, 180 or 270.
     *
     * @return The device's photo orientation in degrees.
     */
    public int getPhotoOrientation() {
        return (int) this.targetImageRotation;
    }

    //    /**
//     * Returns the device's photo orientation in degrees based on the sensor orientation and the
//     * supplied {@link PlatformChannel.DeviceOrientation} value.
//     *
//     * <p>Returns one of 0, 90, 180 or 270.
//     *
//     * @param orientation The {@link PlatformChannel.DeviceOrientation} value that is to be converted
//     *                    into degrees.
//     * @return The device's photo orientation in degrees.
//     */
    private int getOrientationAngle(@Nullable PlatformChannel.DeviceOrientation orientation) {
        int angle = 0;
        if (orientation == null) {
            return angle;
        }
        switch (orientation) {
            case PORTRAIT_DOWN:
                angle = 180;
                break;
            case LANDSCAPE_LEFT:
                angle = 270;
                break;
            case LANDSCAPE_RIGHT:
                angle = 90;
                break;
        }
        return angle;
    }
//
//        // Sensor orientation is 90 for most devices, or 270 for some devices (eg. Nexus 5X).
//        // This has to be taken into account so the JPEG is rotated properly.
//        // For devices with orientation of 90, this simply returns the mapping from ORIENTATIONS.
//        // For devices with orientation of 270, the JPEG is rotated 180 degrees instead.
//        return (angle + sensorOrientation + 270) % 360;
//    }

    /**
     * Returns the device's video orientation in degrees based on the sensor orientation and the last
     * known UI orientation.
     *
     * <p>Returns one of 0, 90, 180 or 270.
     *
     * @return The device's video orientation in degrees.
     */
    public int getVideoOrientation() {
        return this.getVideoOrientation(this.accelerometerOrientation);
    }

    /**
     * Returns the device's video orientation in degrees based on the sensor orientation and the
     * supplied {@link PlatformChannel.DeviceOrientation} value.
     *
     * <p>Returns one of 0, 90, 180 or 270.
     *
     * @param orientation The {@link PlatformChannel.DeviceOrientation} value that is to be converted
     *                    into degrees.
     * @return The device's video orientation in degrees.
     */
    public int getVideoOrientation(PlatformChannel.DeviceOrientation orientation) {
        return 0;
    }

    /**
     * @return the last received UI orientation.
     */
    public PlatformChannel.DeviceOrientation getLastUIOrientation() {
        return this.accelerometerOrientation;
    }

    /**
     * Handles orientation changes based on change events triggered by the OrientationIntentFilter.
     *
     * <p>This method is visible for testing purposes only and should never be used outside this
     * class.
     */
    @VisibleForTesting
    void handleUIOrientationChange() {
        PlatformChannel.DeviceOrientation orientation = getUIOrientation();
        handleOrientationChange(orientation, accelerometerOrientation, messenger);
        accelerometerOrientation = orientation;
    }

    /**
     * Handles orientation changes coming from either the device's sensors or the
     * OrientationIntentFilter.
     *
     * <p>This method is visible for testing purposes only and should never be used outside this
     * class.
     */
    @VisibleForTesting
    static void handleOrientationChange(
            DeviceOrientation newOrientation,
            DeviceOrientation previousOrientation,
            DartMessenger messenger) {
        if (!newOrientation.equals(previousOrientation)) {
            messenger.sendDeviceOrientationChangeEvent(newOrientation);
        }
    }

    /**
     * Gets the current user interface orientation.
     *
     * <p>This method is visible for testing purposes only and should never be used outside this
     * class.
     *
     * @return The current user interface orientation.
     */
    @VisibleForTesting
    PlatformChannel.DeviceOrientation getUIOrientation() {
        final int rotation = getDisplay().getRotation();
        final int orientation = activity.getResources().getConfiguration().orientation;

        switch (orientation) {
            case Configuration.ORIENTATION_PORTRAIT:
                if (rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_90) {
                    return PlatformChannel.DeviceOrientation.PORTRAIT_UP;
                } else {
                    return PlatformChannel.DeviceOrientation.PORTRAIT_DOWN;
                }
            case Configuration.ORIENTATION_LANDSCAPE:
                if (rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_90) {
                    return PlatformChannel.DeviceOrientation.LANDSCAPE_LEFT;
                } else {
                    return PlatformChannel.DeviceOrientation.LANDSCAPE_RIGHT;
                }
            default:
                return PlatformChannel.DeviceOrientation.PORTRAIT_UP;
        }
    }

    /**
     * Calculates the sensor orientation based on the supplied angle.
     *
     * <p>This method is visible for testing purposes only and should never be used outside this
     * class.
     *
     * @param angle Orientation angle.
     * @return The sensor orientation based on the supplied angle.
     */
    @VisibleForTesting
    PlatformChannel.DeviceOrientation calculateSensorOrientation(int angle) {
        final int tolerance = 45;
        angle += tolerance;

        // Orientation is 0 in the default orientation mode. This is portrait-mode for phones
        // and landscape for tablets. We have to compensate for this by calculating the default
        // orientation, and apply an offset accordingly.
        int defaultDeviceOrientation = getDeviceDefaultOrientation();
        if (defaultDeviceOrientation == Configuration.ORIENTATION_LANDSCAPE) {
            angle += 90;
        }
        // Determine the orientation
        angle = angle % 360;
        return new PlatformChannel.DeviceOrientation[]{
                PlatformChannel.DeviceOrientation.PORTRAIT_UP,
                PlatformChannel.DeviceOrientation.LANDSCAPE_RIGHT,
                PlatformChannel.DeviceOrientation.PORTRAIT_DOWN,
                PlatformChannel.DeviceOrientation.LANDSCAPE_LEFT,
        }
                [angle / 90];
    }

    /**
     * Gets the default orientation of the device.
     *
     * <p>This method is visible for testing purposes only and should never be used outside this
     * class.
     *
     * @return The default orientation of the device.
     */
    @VisibleForTesting
    int getDeviceDefaultOrientation() {
        Configuration config = activity.getResources().getConfiguration();
        int rotation = getDisplay().getRotation();
        if (((rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_180)
                && config.orientation == Configuration.ORIENTATION_LANDSCAPE)
                || ((rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270)
                && config.orientation == Configuration.ORIENTATION_PORTRAIT)) {
            return Configuration.ORIENTATION_LANDSCAPE;
        } else {
            return Configuration.ORIENTATION_PORTRAIT;
        }
    }

    /**
     * Gets an instance of the Android {@link android.view.Display}.
     *
     * <p>This method is visible for testing purposes only and should never be used outside this
     * class.
     *
     * @return An instance of the Android {@link android.view.Display}.
     */
    @SuppressWarnings("deprecation")
    @VisibleForTesting
    Display getDisplay() {
        return ((WindowManager) activity.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay();
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int i) {
    }

    public DeviceTilts getDeviceTilts() {
        return new DeviceTilts(
                takePictureMode == TakePictureMode.overheadShot ? horizontalTiltOverhead : horizontalTilt,
                takePictureMode == TakePictureMode.overheadShot ? verticalTiltOverhead : verticalTilt,
                isHorizontalTiltAvailable,
                isVerticalTiltAvailable,
                takePictureMode,
                targetImageRotation,
                lockedCaptureAngle,
                deviceOrientationAngle,
                getOrientationAngle(uiOrientation) == getOrientationAngle(accelerometerOrientation)
        );
    }
}
