// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Flutter/Flutter.h>
#import <ZXingObjC/ZXingObjC.h>

@interface CameraPlugin : NSObject <FlutterPlugin>
@end

@interface BarcodeStreamHandler : NSObject <FlutterStreamHandler>
@property FlutterEventSink eventSink;
@end
