package io.flutter.plugins.camera.types;

public class ImageBytes {
    private final int width;
    private final int height;
    private final byte[] bytes;
    private final int imageFormat;

    private final int[] pixels;

    public ImageBytes(int width, int height, byte[] bytes, int[] pixels, int imageFormat) {
        if (bytes == null && pixels == null) {
            throw (new IllegalArgumentException("bytes is null and pixels is null"));
        }
        if (bytes != null && bytes.length != width * height) {
            throw (new IllegalArgumentException("the length of bytes has to be equal to width*height"));
        }
        if (pixels != null && pixels.length != width * height) {
            throw (new IllegalArgumentException("the length of bytes has to be equal to width*height"));
        }
        this.width = width;
        this.height = height;
        this.bytes = bytes;
        this.pixels = pixels;
        this.imageFormat = imageFormat;
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

    public int getImageFormat() {
        return imageFormat;
    }

    public int[] getPixels() {
        return pixels;
    }
}
