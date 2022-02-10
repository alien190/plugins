// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.types;

// Mirrors exposure_mode.dart
public enum TakePictureMode {
  unknownShot("unknownShot"),
  normalShot("normalShot"),
  overheadShot("overheadShot");

  private final String strValue;

  TakePictureMode(String strValue) {
    this.strValue = strValue;
  }

  public static TakePictureMode getValueForString(String modeStr) {
    for (TakePictureMode value : values()) {
      if (value.strValue.equals(modeStr)) return value;
    }
    return null;
  }

  @Override
  public String toString() {
    return strValue;
  }
}
