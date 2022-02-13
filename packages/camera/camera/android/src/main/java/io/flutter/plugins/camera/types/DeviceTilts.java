package io.flutter.plugins.camera.types;

import java.util.HashMap;

public class DeviceTilts {
    public final double horizontalTilt;
    public final double verticalTilt;
    public final boolean isHorizontalTiltAvailable;
    public final boolean isVerticalTiltAvailable;
    public final TakePictureMode mode;
    public final double targetImageRotation;
    public final int lockedCaptureAngle;
    public final int deviceOrientationAngle;
    public final boolean isUIRotationEqualAccRotation;


    public DeviceTilts(double horizontalTilt,
                       double verticalTilt,
                       boolean isHorizontalTiltAvailable,
                       boolean isVerticalTiltAvailable,
                       TakePictureMode mode,
                       double targetImageRotation,
                       int lockedCaptureAngle,
                       int deviceOrientationAngle,
                       boolean isUIRotationEqualAccRotation) {
        this.horizontalTilt = horizontalTilt;
        this.verticalTilt = verticalTilt;
        this.isHorizontalTiltAvailable = isHorizontalTiltAvailable;
        this.isVerticalTiltAvailable = isVerticalTiltAvailable;
        this.mode = mode;
        this.targetImageRotation = targetImageRotation;
        this.lockedCaptureAngle = lockedCaptureAngle;
        this.deviceOrientationAngle = deviceOrientationAngle;
        this.isUIRotationEqualAccRotation = isUIRotationEqualAccRotation;
    }

    public HashMap<String, Object> getMap() {
        return new HashMap<String, Object>() {
            {
                put("isHorizontalTiltAvailable", isHorizontalTiltAvailable);
                put("isVerticalTiltAvailable", isVerticalTiltAvailable);
                put("horizontalTilt", horizontalTilt);
                put("verticalTilt", verticalTilt);
                put("mode", mode.toString());
                put("targetImageRotation", targetImageRotation);
                put("lockedCaptureAngle", lockedCaptureAngle);
                put("deviceOrientationAngle", deviceOrientationAngle);
                put("isUIRotationEqualAccRotation", isUIRotationEqualAccRotation);
            }
        };
    }
}