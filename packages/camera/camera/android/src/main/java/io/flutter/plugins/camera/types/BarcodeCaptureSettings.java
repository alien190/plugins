package io.flutter.plugins.camera.types;

public class BarcodeCaptureSettings {
    public final int cropLeft;
    public final int cropRight;
    public final int cropTop;
    public final int cropBottom;

    public BarcodeCaptureSettings(int cropLeft, int cropRight, int cropTop, int cropBottom) {
        this.cropLeft = cropLeft;
        this.cropRight = cropRight;
        this.cropTop = cropTop;
        this.cropBottom = cropBottom;
    }
}
