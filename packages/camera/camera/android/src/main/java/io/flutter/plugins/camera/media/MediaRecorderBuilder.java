// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.media;

import android.media.CamcorderProfile;
import android.media.MediaRecorder;


import androidx.annotation.NonNull;

import java.io.IOException;

public class MediaRecorderBuilder {

    static class MediaRecorderFactory {
        MediaRecorder makeMediaRecorder() {
            return new MediaRecorder();
        }
    }

    private final String outputFilePath;
    private final CamcorderProfile camcorderProfile;
    private final MediaRecorderFactory recorderFactory;

    private boolean enableAudio;
    private int mediaOrientation;

    public MediaRecorderBuilder(
            @NonNull CamcorderProfile camcorderProfile, @NonNull String outputFilePath) {
        this(camcorderProfile, outputFilePath, new MediaRecorderFactory());
    }


    MediaRecorderBuilder(
            @NonNull CamcorderProfile camcorderProfile,
            @NonNull String outputFilePath,
            MediaRecorderFactory helper) {
        this.outputFilePath = outputFilePath;
        this.camcorderProfile = camcorderProfile;
        this.recorderFactory = helper;
    }

    public MediaRecorderBuilder setEnableAudio(boolean enableAudio) {
        this.enableAudio = enableAudio;
        return this;
    }

    public MediaRecorderBuilder setMediaOrientation(int orientation) {
        this.mediaOrientation = orientation;
        return this;
    }

    public MediaRecorder build() throws IOException, NullPointerException, IndexOutOfBoundsException {
        MediaRecorder mediaRecorder = recorderFactory.makeMediaRecorder();

        // There's a fixed order that mediaRecorder expects. Only change these functions accordingly.
        // You can find the specifics here: https://developer.android.com/reference/android/media/MediaRecorder.
        if (enableAudio) mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC);
        mediaRecorder.setVideoSource(MediaRecorder.VideoSource.SURFACE);


        mediaRecorder.setOutputFormat(camcorderProfile.fileFormat);
        if (enableAudio) {
            mediaRecorder.setAudioEncoder(camcorderProfile.audioCodec);
            mediaRecorder.setAudioEncodingBitRate(camcorderProfile.audioBitRate);
            mediaRecorder.setAudioSamplingRate(camcorderProfile.audioSampleRate);
        }
        mediaRecorder.setVideoEncoder(camcorderProfile.videoCodec);
        mediaRecorder.setVideoEncodingBitRate(camcorderProfile.videoBitRate);
        mediaRecorder.setVideoFrameRate(camcorderProfile.videoFrameRate);
        mediaRecorder.setVideoSize(
                camcorderProfile.videoFrameWidth, camcorderProfile.videoFrameHeight);

        mediaRecorder.setOutputFile(outputFilePath);
        mediaRecorder.setOrientationHint(this.mediaOrientation);

        mediaRecorder.prepare();

        return mediaRecorder;
    }
}
