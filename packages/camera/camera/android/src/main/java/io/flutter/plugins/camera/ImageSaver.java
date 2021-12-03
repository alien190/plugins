// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.media.Image;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.VisibleForTesting;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;

/**
 * Saves a JPEG {@link Image} into the specified {@link File}.
 */
public class ImageSaver implements Runnable {

    private static final String TAG = "ImageSaver";

    /**
     * The JPEG image
     */
    private final Image image;

    /**
     * The file we save the image into.
     */
    private final File file;

    /**
     * Used to report the status of the save action.
     */
    private final Callback callback;

    private final Integer targetWidth;

    private final Integer targetAngel;

    private final Integer imageQuality;

    /**
     * Creates an instance of the ImageSaver runnable
     *
     * @param image    - The image to save
     * @param file     - The file to save the image to
     * @param callback - The callback that is run on completion, or when an error is encountered.
     */
    ImageSaver(@NonNull Image image,
               @NonNull File file,
               @Nullable Integer targetWidth,
               @Nullable Integer targetAngel,
               @Nullable Integer imageQuality,
               @NonNull Callback callback
    ) {
        this.image = image;
        this.file = file;
        this.callback = callback;
        this.targetAngel = targetAngel;
        this.targetWidth = targetWidth;
        this.imageQuality = imageQuality != null && imageQuality >= 0 && imageQuality <= 100 ? imageQuality : 100;
    }

    @Override
    public void run() {
        Log.w(TAG, "run()");
        FileOutputStream output = null;
        try {
            if (targetWidth == null && targetAngel == null) {
                Log.w(TAG, "targetWidth == null && targetAngel == null");
                ByteBuffer buffer = image.getPlanes()[0].getBuffer();
                byte[] bytes = new byte[buffer.remaining()];
                buffer.get(bytes);
                output = FileOutputStreamFactory.create(file);
                output.write(bytes);

                callback.onComplete(file.getAbsolutePath());
                Log.w(TAG, "onComplete()");
                return;
            }


            final byte[] imageBytes = CameraUtils.imageToByteArray(image);
            final Bitmap srcBitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.length);
            Log.w(TAG, "srcBitmap was created. Width:" + srcBitmap.getWidth() + ", height:" + srcBitmap.getHeight());

            final Matrix dstMatrix = new Matrix();
            float scaleFactor = 1;
            if (targetWidth != null) {
                if (srcBitmap.getWidth() > srcBitmap.getHeight()) {
                    scaleFactor = ((float) targetWidth / srcBitmap.getWidth());
                } else {
                    scaleFactor = ((float) targetWidth / srcBitmap.getHeight());
                }
            }
            Log.w(TAG, "scaleFactor:" + scaleFactor);
            dstMatrix.postScale(scaleFactor, scaleFactor);

            if (targetAngel != null) {
                Log.w(TAG, "targetAngel:" + targetAngel);
                dstMatrix.postRotate(targetAngel);
            }

            final Bitmap dstBitmap = Bitmap.createBitmap(
                    srcBitmap,
                    0,
                    0,
                    srcBitmap.getWidth(),
                    srcBitmap.getHeight(),
                    dstMatrix,
                    true
            );
            Log.w(TAG, "dstBitmap was created (rotation + scale). Width:" + dstBitmap.getWidth() + ", height:" + dstBitmap.getHeight());

            output = FileOutputStreamFactory.create(file);
            dstBitmap.compress(Bitmap.CompressFormat.JPEG, imageQuality, output);

            callback.onComplete(file.getAbsolutePath());
            Log.w(TAG, "onComplete()");
            srcBitmap.recycle();
            dstBitmap.recycle();
        } catch (IOException e) {
            callback.onError("IOError", "Failed saving image: " + e.toString());
            Log.w(TAG, "Error: " + e.toString());
        } catch (Exception e) {
            callback.onError("Unknown Error", "Failed saving image: " + e.toString());
            Log.w(TAG, "Error: " + e.toString());
        } finally {
            image.close();
            if (null != output) {
                try {
                    output.close();
                } catch (IOException e) {
                    callback.onError("cameraAccess", e.getMessage());
                }
            }
        }
    }

    /**
     * The interface for the callback that is passed to ImageSaver, for detecting completion or
     * failure of the image saving task.
     */
    public interface Callback {
        /**
         * Called when the image file has been saved successfully.
         *
         * @param absolutePath - The absolute path of the file that was saved.
         */
        void onComplete(String absolutePath);

        /**
         * Called when an error is encountered while saving the image file.
         *
         * @param errorCode    - The error code.
         * @param errorMessage - The human readable error message.
         */
        void onError(String errorCode, String errorMessage);
    }

    /**
     * Factory class that assists in creating a {@link FileOutputStream} instance.
     */
    static class FileOutputStreamFactory {
        /**
         * Creates a new instance of the {@link FileOutputStream} class.
         *
         * <p>This method is visible for testing purposes only and should never be used outside this *
         * class.
         *
         * @param file - The file to create the output stream for
         * @return new instance of the {@link FileOutputStream} class.
         * @throws FileNotFoundException when the supplied file could not be found.
         */
        @VisibleForTesting
        public static FileOutputStream create(File file) throws FileNotFoundException {
            return new FileOutputStream(file);
        }
    }
}
