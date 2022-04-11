// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera;

import android.app.Activity;
import android.content.Context;
import android.graphics.ImageFormat;
import android.graphics.Rect;
import android.graphics.YuvImage;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CameraMetadata;
import android.media.Image;
import android.util.Log;

import io.flutter.embedding.engine.systemchannels.PlatformChannel;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Provides various utilities for camera.
 */
public final class CameraUtils {

    private static final String TAG = CameraUtils.class.getSimpleName();

    private CameraUtils() {
    }

    /**
     * Gets the {@link CameraManager} singleton.
     *
     * @param context The context to get the {@link CameraManager} singleton from.
     * @return The {@link CameraManager} singleton.
     */
    static CameraManager getCameraManager(Context context) {
        return (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
    }

    /**
     * Serializes the {@link PlatformChannel.DeviceOrientation} to a string value.
     *
     * @param orientation The orientation to serialize.
     * @return The serialized orientation.
     * @throws UnsupportedOperationException when the provided orientation not have a corresponding
     *                                       string value.
     */
    static String serializeDeviceOrientation(PlatformChannel.DeviceOrientation orientation) {
        if (orientation == null)
            throw new UnsupportedOperationException("Could not serialize null device orientation.");
        switch (orientation) {
            case PORTRAIT_UP:
                return "portraitUp";
            case PORTRAIT_DOWN:
                return "portraitDown";
            case LANDSCAPE_LEFT:
                return "landscapeLeft";
            case LANDSCAPE_RIGHT:
                return "landscapeRight";
            default:
                throw new UnsupportedOperationException(
                        "Could not serialize device orientation: " + orientation.toString());
        }
    }

    /**
     * Deserializes a string value to its corresponding {@link PlatformChannel.DeviceOrientation}
     * value.
     *
     * @param orientation The string value to deserialize.
     * @return The deserialized orientation.
     * @throws UnsupportedOperationException when the provided string value does not have a
     *                                       corresponding {@link PlatformChannel.DeviceOrientation}.
     */
    static PlatformChannel.DeviceOrientation deserializeDeviceOrientation(String orientation) {
        if (orientation == null)
            throw new UnsupportedOperationException("Could not deserialize null device orientation.");
        switch (orientation) {
            case "portraitUp":
                return PlatformChannel.DeviceOrientation.PORTRAIT_UP;
            case "portraitDown":
                return PlatformChannel.DeviceOrientation.PORTRAIT_DOWN;
            case "landscapeLeft":
                return PlatformChannel.DeviceOrientation.LANDSCAPE_LEFT;
            case "landscapeRight":
                return PlatformChannel.DeviceOrientation.LANDSCAPE_RIGHT;
            default:
                throw new UnsupportedOperationException(
                        "Could not deserialize device orientation: " + orientation);
        }
    }

    /**
     * Gets all the available cameras for the device.
     *
     * @param activity The current Android activity.
     * @return A map of all the available cameras, with their name as their key.
     * @throws CameraAccessException when the camera could not be accessed.
     */
    public static List<Map<String, Object>> getAvailableCameras(Activity activity)
            throws CameraAccessException {
        CameraManager cameraManager = (CameraManager) activity.getSystemService(Context.CAMERA_SERVICE);
        String[] cameraNames = cameraManager.getCameraIdList();
        List<Map<String, Object>> cameras = new ArrayList<>();
        for (String cameraName : cameraNames) {
            try {
                int cameraId;
                try {
                    cameraId = Integer.parseInt(cameraName, 10);
                } catch (NumberFormatException e) {
                    cameraId = -1;
                }
                if (cameraId < 0) {
                    continue;
                }

                HashMap<String, Object> details = new HashMap<>();
                CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(cameraName);
                details.put("name", cameraName);
                int sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
                details.put("sensorOrientation", sensorOrientation);

                int lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING);
                switch (lensFacing) {
                    case CameraMetadata.LENS_FACING_FRONT:
                        details.put("lensFacing", "front");
                        break;
                    case CameraMetadata.LENS_FACING_BACK:
                        details.put("lensFacing", "back");
                        break;
                    case CameraMetadata.LENS_FACING_EXTERNAL:
                        details.put("lensFacing", "external");
                        break;
                }
                cameras.add(details);
            } catch (Exception e) {
                Log.e(TAG, "Error adding camera to list of available cameras: " + e.toString());
            }
        }
        return cameras;
    }

    public static byte[] imageToByteArray(Image image) {
        byte[] data = null;
        if (image.getFormat() == ImageFormat.JPEG) {
            Image.Plane[] planes = image.getPlanes();
            ByteBuffer buffer = planes[0].getBuffer();
            data = new byte[buffer.capacity()];
            buffer.get(data);
            return data;
        } else if (image.getFormat() == ImageFormat.YUV_420_888) {
            data = NV21toJPEG(
                    YUV420toNV21(image),
                    image.getWidth(), image.getHeight(),
                    100);
        }
        return data;
    }

    private static byte[] NV21toJPEG(byte[] nv21, int width, int height, int quality) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        YuvImage yuv = new YuvImage(nv21, ImageFormat.NV21, width, height, null);
        yuv.compressToJpeg(new Rect(0, 0, width, height), quality, out);
        return out.toByteArray();
    }

    private static byte[] YUV420toNV21(Image image) {
        Rect crop = image.getCropRect();
        int format = image.getFormat();
        int width = crop.width();
        int height = crop.height();
        Image.Plane[] planes = image.getPlanes();
        byte[] data = new byte[width * height * ImageFormat.getBitsPerPixel(format) / 8];
        byte[] rowData = new byte[planes[0].getRowStride()];

        int channelOffset = 0;
        int outputStride = 1;
        for (int i = 0; i < planes.length; i++) {
            switch (i) {
                case 0:
                    channelOffset = 0;
                    outputStride = 1;
                    break;
                case 1:
                    channelOffset = width * height + 1;
                    outputStride = 2;
                    break;
                case 2:
                    channelOffset = width * height;
                    outputStride = 2;
                    break;
            }

            ByteBuffer buffer = planes[i].getBuffer();
            int rowStride = planes[i].getRowStride();
            int pixelStride = planes[i].getPixelStride();

            int shift = (i == 0) ? 0 : 1;
            int w = width >> shift;
            int h = height >> shift;
            buffer.position(rowStride * (crop.top >> shift) + pixelStride * (crop.left >> shift));
            for (int row = 0; row < h; row++) {
                int length;
                if (pixelStride == 1 && outputStride == 1) {
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
        }
        return data;
    }
}
