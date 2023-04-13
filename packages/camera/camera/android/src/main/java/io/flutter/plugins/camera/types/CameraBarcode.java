package io.flutter.plugins.camera.types;

import java.util.HashMap;

public class CameraBarcode {
    final String text;
    final String format;
    final String errorDescription;

    public CameraBarcode(String text, String format, String errorDescription) {
        this.text = text;
        this.format = format;
        this.errorDescription = errorDescription;
    }

    public HashMap<String, Object> getMap() {
        return new HashMap<String, Object>() {
            {
                put("text", text != null ? text : "");
                put("format", format != null ? format : "");
                put("errorDescription", errorDescription);
            }
        };
    }

}
