// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.resolution;

import android.graphics.ImageFormat;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.CamcorderProfile;
import android.util.Log;
import android.util.Size;

import androidx.annotation.VisibleForTesting;

import io.flutter.plugins.camera.CameraProperties;
import io.flutter.plugins.camera.features.CameraFeature;

import java.util.ArrayList;
import java.util.Arrays;

/**
 * Controls the resolutions configuration on the {@link android.hardware.camera2} API.
 *
 * <p>The {@link ResolutionFeature} is responsible for converting the platform independent {@link
 * ResolutionPreset} into a {@link android.media.CamcorderProfile} which contains all the properties
 * required to configure the resolution using the {@link android.hardware.camera2} API.
 */
public class ResolutionFeature extends CameraFeature<ResolutionPreset> {
    private static final String TAG = "ResolutionFeature";


    private Size captureSize;
    private Size previewSize;
    private int captureFormat;
    private CamcorderProfile recordingProfileLegacy;
    private ResolutionPreset currentSetting;
    private int cameraId;
    private final int longSideSize;
    private final int shortSideSize;
    private final int imageQuality;

    /**
     * Creates a new instance of the {@link ResolutionFeature}.
     *
     * @param cameraProperties Collection of characteristics for the current camera device.
     * @param resolutionPreset Platform agnostic enum containing resolution information.
     * @param cameraName       Camera identifier of the camera for which to configure the resolution.
     */
    public ResolutionFeature(
            CameraProperties cameraProperties,
            ResolutionPreset resolutionPreset,
            String cameraName,
            int longSideSize,
            int imageQuality
    ) {
        super(cameraProperties);
        this.currentSetting = resolutionPreset;
        this.longSideSize = longSideSize > 0 ? longSideSize : 1600;
        this.shortSideSize = (int) ((float) this.longSideSize / 1.333333333f);
        this.imageQuality = imageQuality >= 0 && imageQuality <= 100 ? imageQuality : 100;
        try {
            this.cameraId = Integer.parseInt(cameraName, 10);
        } catch (NumberFormatException e) {
            this.cameraId = -1;
            return;
        }

        configureResolution(resolutionPreset, cameraId);
    }

    /**
     * Gets the {@link android.media.CamcorderProfile} containing the information to configure the
     * resolution using the {@link android.hardware.camera2} API.
     *
     * @return Resolution information to configure the {@link android.hardware.camera2} API.
     */
    public CamcorderProfile getRecordingProfileLegacy() {
        return this.recordingProfileLegacy;
    }


    /**
     * Gets the optimal preview size based on the configured resolution.
     *
     * @return The optimal preview size.
     */
    public Size getPreviewSize() {
        return this.previewSize;
    }

    /**
     * Gets the optimal capture size based on the configured resolution.
     *
     * @return The optimal capture size.
     */
    public Size getCaptureSize() {
        return this.captureSize;
    }

    public int getCaptureFormat() {
        return captureFormat;
    }

    @Override
    public String getDebugName() {
        return "ResolutionFeature";
    }

    @Override
    public ResolutionPreset getValue() {
        return currentSetting;
    }

    @Override
    public void setValue(ResolutionPreset value) {
        this.currentSetting = value;
        configureResolution(currentSetting, cameraId);
    }

    @Override
    public boolean checkIsSupported() {
        return cameraId >= 0;
    }

    @Override
    public void updateBuilder(CaptureRequest.Builder requestBuilder) {
        // No-op: when setting a resolution there is no need to update the request builder.
    }

    @VisibleForTesting
    static Size computeBestPreviewSize(int cameraId, ResolutionPreset preset)
            throws IndexOutOfBoundsException {
        if (preset.ordinal() > ResolutionPreset.high.ordinal()) {
            preset = ResolutionPreset.high;
        }

        CamcorderProfile profile =
                getBestAvailableCamcorderProfileForResolutionPresetLegacy(cameraId, preset);
        return new Size(profile.videoFrameWidth, profile.videoFrameHeight);

    }

    /**
     * Gets the best possible {@link android.media.CamcorderProfile} for the supplied {@link
     * ResolutionPreset}. Supports SDK < 31.
     *
     * @param cameraId Camera identifier which indicates the device's camera for which to select a
     *                 {@link android.media.CamcorderProfile}.
     * @param preset   The {@link ResolutionPreset} for which is to be translated to a {@link
     *                 android.media.CamcorderProfile}.
     * @return The best possible {@link android.media.CamcorderProfile} that matches the supplied
     * {@link ResolutionPreset}.
     */
    public static CamcorderProfile getBestAvailableCamcorderProfileForResolutionPresetLegacy(
            int cameraId, ResolutionPreset preset) {
        if (cameraId < 0) {
            throw new AssertionError(
                    "getBestAvailableCamcorderProfileForResolutionPreset can only be used with valid (>=0) camera identifiers.");
        }

        switch (preset) {
            // All of these cases deliberately fall through to get the best available profile.
            case max:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_HIGH)) {
                    return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_HIGH);
                }
            case ultraHigh:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_2160P)) {
                    return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_2160P);
                }
            case veryHigh:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_1080P)) {
                    return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_1080P);
                }
            case custom43:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_1080P)) {
                    return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_1080P);
                }
            case high:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_720P)) {
                    return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_720P);
                }
            case medium:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_480P)) {
                    return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_480P);
                }
            case low:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_QVGA)) {
                    return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_QVGA);
                }
            default:
                if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_LOW)) {
                    return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_LOW);
                } else {
                    throw new IllegalArgumentException(
                            "No capture session available for current capture session.");
                }
        }
    }


    private void configureDefaultResolution(ResolutionPreset resolutionPreset, int cameraId)
            throws IndexOutOfBoundsException {
        if (!checkIsSupported()) {
            return;
        }

        captureFormat = ImageFormat.JPEG;

        CamcorderProfile camcorderProfile =
                getBestAvailableCamcorderProfileForResolutionPresetLegacy(cameraId, resolutionPreset);
        recordingProfileLegacy = camcorderProfile;
        captureSize =
                new Size(recordingProfileLegacy.videoFrameWidth, recordingProfileLegacy.videoFrameHeight);

        previewSize = computeBestPreviewSize(cameraId, resolutionPreset);
    }


    private void configureResolution(ResolutionPreset preset, int cameraId) {
        configureDefaultResolution(preset, cameraId);
        if (preset != ResolutionPreset.custom43) {
            return;
        }

        final StreamConfigurationMap streamConfigurationMap = cameraProperties
                .getStreamConfigurationMap();

        final int[] outputFormats = streamConfigurationMap.getOutputFormats();
        final ArrayList<Integer> selectedOutputFormats = new ArrayList<>();
        for (int format : outputFormats) {
            if (format == ImageFormat.YUV_420_888 || format == ImageFormat.JPEG) {
                selectedOutputFormats.add(format);
            }
        }
        if (selectedOutputFormats.isEmpty()) {
            Log.i(TAG, "There isn't any sizes for JPEG or YUV_420_888 format");
            return;
        }

        Size jpegClosestSize = null;
        try {
            jpegClosestSize = getClosest43Resolution(streamConfigurationMap, ImageFormat.JPEG);
        } catch (IllegalStateException exception) {
            Log.i(TAG, "There isn't any closest sizes for JPEG format");
        }

        Size yuvClosestSize = null;
        try {
            yuvClosestSize = getClosest43Resolution(streamConfigurationMap, ImageFormat.YUV_420_888);
        } catch (IllegalStateException exception) {
            Log.i(TAG, "There isn't any closest sizes for YUV_420_888 format");
        }

        if (jpegClosestSize != null && yuvClosestSize != null) {
            if (yuvClosestSize.getWidth() == longSideSize
                    && yuvClosestSize.getHeight() == shortSideSize) {
                captureFormat = ImageFormat.YUV_420_888;
                final Size size = new Size(longSideSize, shortSideSize);
                previewSize = size;
                captureSize = size;
                Log.w(TAG, "Camera was configured for size: " + size + ", format: " + captureFormat);
                return;
            }

            if (jpegClosestSize.getWidth() == longSideSize
                    && jpegClosestSize.getHeight() == shortSideSize) {
                captureFormat = ImageFormat.JPEG;
                final Size size = new Size(longSideSize, shortSideSize);
                previewSize = size;
                captureSize = size;
                Log.w(TAG, "Camera was configured for size: " + size + ", format: " + captureFormat);
                return;
            }

            if (yuvClosestSize.getWidth() <= jpegClosestSize.getWidth()
                    && yuvClosestSize.getHeight() <= jpegClosestSize.getHeight()) {
                captureFormat = ImageFormat.YUV_420_888;
                final Size size = new Size(yuvClosestSize.getWidth(), yuvClosestSize.getHeight());
                previewSize = size;
                captureSize = size;
                Log.w(TAG, "Camera was configured for size: " + size + ", format: " + captureFormat);
                return;
            }
            captureFormat = ImageFormat.JPEG;
            final Size size = new Size(jpegClosestSize.getWidth(), jpegClosestSize.getHeight());
            previewSize = size;
            captureSize = size;
            Log.w(TAG, "Camera was configured for size: " + size + ", format: " + captureFormat);
        } else if (jpegClosestSize != null) {
            captureFormat = ImageFormat.JPEG;
            final Size size = new Size(jpegClosestSize.getWidth(), jpegClosestSize.getHeight());
            previewSize = size;
            captureSize = size;
            Log.w(TAG, "Camera was configured for size: " + size + ", format: " + captureFormat);

        } else if (yuvClosestSize != null) {
            captureFormat = ImageFormat.YUV_420_888;
            final Size size = new Size(yuvClosestSize.getWidth(), yuvClosestSize.getHeight());
            previewSize = size;
            captureSize = size;
            Log.w(TAG, "Camera was configured for size: " + size + ", format: " + captureFormat);
        }
    }

    private Size getClosest43Resolution(StreamConfigurationMap streamConfigurationMap, int format)
            throws IllegalStateException {
        final Size[] sizes = streamConfigurationMap.getOutputSizes(format);
        Log.w(TAG, "Available sizes, format: " + format + ", sizes: " + Arrays.toString(sizes));
        Arrays.sort(sizes, (o1, o2) ->
                {
                    final int widthDiff = o1.getWidth() - o2.getWidth();
                    if (widthDiff == 0) {
                        return o1.getHeight() - o2.getHeight();
                    }
                    return widthDiff;
                }
        );
        for (Size size : sizes) {
            int longSide;
            int shortSide;
            if (size.getWidth() > size.getHeight()) {
                longSide = size.getWidth();
                shortSide = size.getHeight();
            } else {
                longSide = size.getHeight();
                shortSide = size.getWidth();
            }
            final float aspectRatio = ((float) longSide) / shortSide;

            if (aspectRatio >= ResolutionPreset.PREFFERED_43FORMAT_LOW_ASPECT_RATIO &&
                    aspectRatio <= ResolutionPreset.PREFFERED_43FORMAT_HIGH_ASPECT_RATIO &&
                    longSide >= longSideSize &&
                    shortSide >= shortSideSize) {
                Log.w(TAG, "Selected size: " + size + ", format: " + format);
                return size;
            }
        }
        Log.w(TAG, "Size selection error: No appropriate size");
        throw new IllegalStateException("No sizes");
    }

    public int getLongSideSize() {
        return longSideSize;
    }

    public int getShortSideSize() {
        return shortSideSize;
    }

    public int getImageQuality() {
        return imageQuality;
    }
}
