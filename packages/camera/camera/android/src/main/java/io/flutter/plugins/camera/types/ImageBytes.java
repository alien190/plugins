package io.flutter.plugins.camera.types;

public class ImageBytes {
    private final int width;
    private final int height;
    private final byte[] bytes;

    public ImageBytes(int width, int height, byte[] bytes) {
        if (bytes.length != width * height) {
            throw (new IllegalArgumentException(" the length of bytes has to equal to width*height"));
        }
        this.width = width;
        this.height = height;
        this.bytes = bytes;

    }

    public int getWidth() {
        return width;
    }

    public int getHeight() {
        return height;
    }

    public byte[] getBytes() {
        return bytes;
    }
}
