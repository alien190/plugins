package io.flutter.plugins.camera.types;

import java.util.HashMap;

public class TakePictureResult {
    public final String resultPath;
    public final double horizontalTilt;
    public final double verticalTilt;
    public final boolean isHorizontalTiltAvailable;
    public final boolean isVerticalTiltAvailable;
    public final TakePictureMode mode;

    public TakePictureResult(String resultPath,
                             double horizontalTilt,
                             double verticalTilt,
                             boolean isHorizontalTiltAvailable,
                             boolean isVerticalTiltAvailable,
                             TakePictureMode mode) {
        this.resultPath = resultPath;
        this.horizontalTilt = horizontalTilt;
        this.verticalTilt = verticalTilt;
        this.isHorizontalTiltAvailable = isHorizontalTiltAvailable;
        this.isVerticalTiltAvailable = isVerticalTiltAvailable;
        this.mode = mode;
    }


    public HashMap<String, Object> getMap() {
        return new HashMap<String, Object>() {
            {
                put("resultPath", resultPath);
                put("isHorizontalTiltAvailable", isHorizontalTiltAvailable);
                put("isVerticalTiltAvailable", isVerticalTiltAvailable);
                put("horizontalTilt", horizontalTilt);
                put("verticalTilt", verticalTilt);
                put("mode", mode.toString());
            }
        };
    }
}