// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.resolution;

// Mirrors camera.dart
public enum ResolutionPreset {
    low,
    medium,
    high,
    veryHigh,
    ultraHigh,
    max,
    custom43;

    public static final int PREFFERED_43FORMAT_WIDTH = 1600;
    public static final int PREFFERED_43FORMAT_HEIGHT = 1200;
    public static final double PREFFERED_43FORMAT_LOW_ASPECT_RATIO = 1.3;
    public static final double PREFFERED_43FORMAT_HIGH_ASPECT_RATIO = 1.4;
    
}