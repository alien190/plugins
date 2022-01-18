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
import androidx.annotation.VisibleForTesting;

import java.util.Arrays;

import io.flutter.embedding.engine.systemchannels.PlatformChannel;
import io.flutter.embedding.engine.systemchannels.PlatformChannel.DeviceOrientation;
import io.flutter.plugins.camera.DartMessenger;

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
    private final int sensorOrientation;
    private PlatformChannel.DeviceOrientation lastOrientation;
    private BroadcastReceiver broadcastReceiver;
    private OrientationEventListener orientationEventListener;
    private final SensorManager sensorManager;

    private final float[] accelerometerReading = new float[3];
    private final float[] magnetometerReading = new float[3];

    private final float[] rotationMatrix = new float[9];
    private final float[] orientationAngles = new float[3];

    private boolean isAccelerationSensorPresent;
    private boolean isMagneticSensorPresent;
    private boolean isRotationVectorSensorPresent;
    private int lastHorizontalTilt = 0;


    /**
     * Factory method to create a device orientation manager.
     */
    public static DeviceOrientationManager create(
            @NonNull Activity activity,
            @NonNull DartMessenger messenger,
            boolean isFrontFacing,
            int sensorOrientation) {
        return new DeviceOrientationManager(activity, messenger, isFrontFacing, sensorOrientation);
    }

    private DeviceOrientationManager(
            @NonNull Activity activity,
            @NonNull DartMessenger messenger,
            boolean isFrontFacing,
            int sensorOrientation) {
        this.activity = activity;
        this.messenger = messenger;
        this.isFrontFacing = isFrontFacing;
        this.sensorOrientation = sensorOrientation;
        this.sensorManager = (SensorManager) activity.getSystemService(Context.SENSOR_SERVICE);
        orientationAngles[0] = 0;
        orientationAngles[1] = 1.54f;
        orientationAngles[2] = 1.54f;
        isAccelerationSensorPresent = false;
        isMagneticSensorPresent = false;
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

        Sensor rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
        if (rotationSensor != null) {
            Log.i(TAG, "Rotation sensor has been initialized");
            sensorManager.registerListener(this, rotationSensor,
                    SensorManager.SENSOR_DELAY_NORMAL, SensorManager.SENSOR_DELAY_UI);
            isRotationVectorSensorPresent = true;
        } else {
            Log.w(TAG, "Rotation sensor has NOT been initialized");
            isRotationVectorSensorPresent = false;
        }

        orientationEventListener =
                new OrientationEventListener(activity, SensorManager.SENSOR_DELAY_NORMAL) {
                    @Override
                    public void onOrientationChanged(int angle) {
                        PlatformChannel.DeviceOrientation newOrientation = calculateSensorOrientation(angle);
                        if (!newOrientation.equals(lastOrientation) && isOrientationChangeAllowed()) {
                            Log.d(TAG, "sensor orientation set:" + newOrientation.toString());
                            lastOrientation = newOrientation;
                            messenger.sendDeviceOrientationChangeEvent(newOrientation);
                        }
                        if (!isRotationVectorSensorPresent && lastHorizontalTilt != angle) {
                            lastHorizontalTilt = angle;
                            messenger.sendDeviceTiltsChangeEvent(
                                    lastHorizontalTilt,
                                    OrientationEventListener.ORIENTATION_UNKNOWN
                            );
                        }
                    }
                };
        if (orientationEventListener.canDetectOrientation()) {
            orientationEventListener.enable();
        } else if (!isRotationVectorSensorPresent) {
            messenger.sendDeviceTiltsChangeEvent(
                    OrientationEventListener.ORIENTATION_UNKNOWN,
                    OrientationEventListener.ORIENTATION_UNKNOWN
            );
        }
    }

    private boolean isOrientationChangeAllowed() {
        return orientationAngles[1] >= 0.7 ||
                orientationAngles[1] <= -0.7 ||
                orientationAngles[2] >= 0.7 ||
                orientationAngles[2] <= -0.7;
    }

    private void startUIListener() {
        if (broadcastReceiver != null) return;
        broadcastReceiver =
                new BroadcastReceiver() {
                    @Override
                    public void onReceive(Context context, Intent intent) {
                        PlatformChannel.DeviceOrientation orientation = getUIOrientation();
                        if (!orientation.equals(lastOrientation) && isOrientationChangeAllowed()) {
                            Log.d(TAG, "UI orientation set:" + orientation.toString());
                            lastOrientation = orientation;
                            messenger.sendDeviceOrientationChangeEvent(orientation);
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
        return this.getPhotoOrientation(this.lastOrientation);
    }

    /**
     * Returns the device's photo orientation in degrees based on the sensor orientation and the
     * supplied {@link PlatformChannel.DeviceOrientation} value.
     *
     * <p>Returns one of 0, 90, 180 or 270.
     *
     * @param orientation The {@link PlatformChannel.DeviceOrientation} value that is to be converted
     *                    into degrees.
     * @return The device's photo orientation in degrees.
     */
    public int getPhotoOrientation(PlatformChannel.DeviceOrientation orientation) {
        int angle = 0;
        // Fallback to device orientation when the orientation value is null.
        if (orientation == null) {
            orientation = getUIOrientation();
        }

        switch (orientation) {
            case PORTRAIT_UP:
                angle = 90;
                break;
            case PORTRAIT_DOWN:
                angle = 270;
                break;
            case LANDSCAPE_LEFT:
                angle = isFrontFacing ? 180 : 0;
                break;
            case LANDSCAPE_RIGHT:
                angle = isFrontFacing ? 0 : 180;
                break;
        }

        // Sensor orientation is 90 for most devices, or 270 for some devices (eg. Nexus 5X).
        // This has to be taken into account so the JPEG is rotated properly.
        // For devices with orientation of 90, this simply returns the mapping from ORIENTATIONS.
        // For devices with orientation of 270, the JPEG is rotated 180 degrees instead.
        return (angle + sensorOrientation + 270) % 360;
    }

    /**
     * Returns the device's video orientation in degrees based on the sensor orientation and the last
     * known UI orientation.
     *
     * <p>Returns one of 0, 90, 180 or 270.
     *
     * @return The device's video orientation in degrees.
     */
    public int getVideoOrientation() {
        return this.getVideoOrientation(this.lastOrientation);
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
        int angle = 0;

        // Fallback to device orientation when the orientation value is null.
        if (orientation == null) {
            orientation = getUIOrientation();
        }

        switch (orientation) {
            case PORTRAIT_UP:
                angle = 0;
                break;
            case PORTRAIT_DOWN:
                angle = 180;
                break;
            case LANDSCAPE_LEFT:
                angle = 90;
                break;
            case LANDSCAPE_RIGHT:
                angle = 270;
                break;
        }

        if (isFrontFacing) {
            angle *= -1;
        }

        return (angle + sensorOrientation + 360) % 360;
    }

    /**
     * @return the last received UI orientation.
     */
    public PlatformChannel.DeviceOrientation getLastUIOrientation() {
        return this.lastOrientation;
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
        handleOrientationChange(orientation, lastOrientation, messenger);
        lastOrientation = orientation;
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
    public void onSensorChanged(SensorEvent event) {
        if (event.sensor.getType() == Sensor.TYPE_ROTATION_VECTOR) {
            SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values);
            SensorManager.getOrientation(rotationMatrix, orientationAngles);
            Log.i(TAG, "new Orientation angles:" + Arrays.toString(orientationAngles));
            final int horizontalTilt = Math.round((float) (orientationAngles[0] * 180 / 3.1415));
            if (lastHorizontalTilt != horizontalTilt) {
                lastHorizontalTilt = horizontalTilt;
                messenger.sendDeviceTiltsChangeEvent(
                        horizontalTilt,
                        OrientationEventListener.ORIENTATION_UNKNOWN
                );
            }
        }
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int i) {
    }
}
