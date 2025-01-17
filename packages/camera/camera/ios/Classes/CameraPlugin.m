// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "CameraPlugin.h"
#import "CameraPlugin_Test.h"

#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreMotion/CoreMotion.h>
#import <libkern/OSAtomic.h>
#import <uuid/uuid.h>
#import "FLTThreadSafeFlutterResult.h"
#import <Foundation/Foundation.h>
#import <GLKit/GLKit.h>

int const DEFAULT_43FORMAT_LONG_SIDE_SIZE = 1600;
int const DEFAULT_43FORMAT_IMAGE_QUALITY = 100;
float const PREFFERED_43FORMAT_LOW_ASPECT_RATIO = 1.3;
float const PREFFERED_43FORMAT_HIGH_ASPECT_RATIO = 1.4;

// Mirrors ResolutionPreset in camera.dart
typedef enum {
    veryLow,
    low,
    medium,
    high,
    veryHigh,
    ultraHigh,
    max,
    custom43,
} ResolutionPreset;

@interface NSCameraResolution: NSObject
@property(readonly, nonatomic) int width;
@property(readonly, nonatomic) int heigh;
@property(readonly, nonatomic) AVCaptureDeviceFormat* format;

- (id)initWithWidth: (int) w andHeight: (int) h andFormat: (AVCaptureDeviceFormat*) f;
- (NSString*) description;
@end

@implementation NSCameraResolution
- (id)initWithWidth: (int) w andHeight: (int) h andFormat: (AVCaptureDeviceFormat*) f
{
    self = [super init];
    if(self) {
        _width = w;
        _heigh = h;
        _format = f;
    }
    return  self;
}

-(NSString *)description {
    return [NSString stringWithFormat:@"NSCameraResolution: width:%d height:%d format:%@", _width, _heigh, _format];
}
@end

@interface FLTSavePhotoDelegate : NSObject <AVCapturePhotoCaptureDelegate>
@property(readonly, nonatomic) NSString *path;
@property(readonly, nonatomic) FLTThreadSafeFlutterResult *result;
@property(assign, nonatomic) double targetImageRotationInRad;
@property(readonly, nonatomic) ResolutionPreset resolutionPreset;
@property(assign, nonatomic) int longSideSize;
@property(assign, nonatomic) int imageQality;
@property(strong,atomic) NSMutableDictionary* deviceAnglesAndPathDict;
@end

@interface FLTImageStreamHandler : NSObject <FlutterStreamHandler>
@property FlutterEventSink eventSink;
@end

@implementation FLTImageStreamHandler

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
    _eventSink = events;
    return nil;
}
@end

@implementation FLTSavePhotoDelegate {
    /// Used to keep the delegate alive until didFinishProcessingPhotoSampleBuffer.
    FLTSavePhotoDelegate *selfReference;
}

- initWithPath:(NSString *)   path result:(FLTThreadSafeFlutterResult *)result
targetImageRotationInRad:(double)targetImageRotationInRad
resolutionPreset:(ResolutionPreset)resolutionPreset
  longSideSize:(int)longSideSize
  imageQuality:(int)imageQuality
deviceAnglesDict:(NSMutableDictionary*)deviceAnglesDict{
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _path = path;
    _deviceAnglesAndPathDict = deviceAnglesDict;
    _deviceAnglesAndPathDict[@"resultPath"] = _path;
    selfReference = self;
    _result = result;
    _targetImageRotationInRad = targetImageRotationInRad;
    _resolutionPreset = resolutionPreset;
    _longSideSize = longSideSize;
    _imageQality = imageQuality;
    return self;
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photoSampleBuffer
previewPhotoSampleBuffer:(CMSampleBufferRef)previewPhotoSampleBuffer
     resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings
      bracketSettings:(AVCaptureBracketedStillImageSettings *)bracketSettings
                error:(NSError *)error API_AVAILABLE(ios(10)) {
    selfReference = nil;
    if (error) {
        [_result sendError:error];
        return;
    }
    
    NSData *data = [AVCapturePhotoOutput
                    JPEGPhotoDataRepresentationForJPEGSampleBuffer:photoSampleBuffer
                    previewPhotoSampleBuffer:previewPhotoSampleBuffer];
    
    if(_resolutionPreset == custom43) {
        [self processPhotoData:data];
    } else {
        bool success = [data writeToFile:_path atomically:YES];
        if (!success) {
            [_result sendErrorWithCode:@"IOError" message:@"Unable to write file" details:nil];
            return;
        }
        UIImage* image = [[UIImage alloc] initWithData:data];
        _deviceAnglesAndPathDict[@"width"] = @((int)image.size.width);
        _deviceAnglesAndPathDict[@"height"] = @((int)image.size.height);
        [_result sendSuccessWithData:_deviceAnglesAndPathDict];
    }
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishProcessingPhoto:(AVCapturePhoto *)photo
                error:(NSError *)error API_AVAILABLE(ios(11.0)) {
    selfReference = nil;
    if (error) {
        [_result sendError:error];
        return;
    }
    
    NSData *photoData = [photo fileDataRepresentation];
    
    if ( _resolutionPreset == custom43 ) {
        [self processPhotoData:photoData];
    } else {
        bool success = [photoData writeToFile:_path atomically:YES];
        if (!success) {
            [_result sendErrorWithCode:@"IOError" message:@"Unable to write file" details:nil];
            return;
        }
        [_result sendSuccessWithData:_deviceAnglesAndPathDict];
    }
}

-(void) processPhotoData: (NSData*) photoData {
    UIImage* image = [[UIImage alloc] initWithData:photoData];
    // Calculate Destination Size
    CGAffineTransform rotationTransform = CGAffineTransformMakeRotation(_targetImageRotationInRad);
    double ratio = 1;
    if(image.size.width > image.size.height) {
        ratio = ((double)_longSideSize) / image.size.width;
    } else {
        ratio = ((double)_longSideSize) / image.size.height;
    }
    
    CGAffineTransform scaleTransform = CGAffineTransformMakeScale(ratio, ratio);
    
    CGRect sizeRect = (CGRect) {.size = image.size};
    CGRect scaledRect = CGRectApplyAffineTransform(sizeRect, scaleTransform);
    CGRect destRect = CGRectApplyAffineTransform(scaledRect, rotationTransform);
    
    CGSize destinationSize = CGSizeMake(destRect.size.width, destRect.size.height);
    _deviceAnglesAndPathDict[@"width"] = @((int)destRect.size.width);
    _deviceAnglesAndPathDict[@"height"] = @((int)destRect.size.height);
    
    // Draw image
    UIGraphicsBeginImageContext(destinationSize);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(context, destinationSize.width / 2.0f, destinationSize.height / 2.0f);
    CGContextRotateCTM(context, _targetImageRotationInRad);
    CGContextScaleCTM(context, ratio, ratio);
    [image drawInRect:CGRectMake(-image.size.width / 2.0f, -image.size.height / 2.0f, image.size.width, image.size.height)];
    
    // Save image
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    NSData* dstImageData = UIImageJPEGRepresentation(newImage, ((float)_imageQality / 100));
    
    bool success = [dstImageData writeToFile:_path atomically:YES];
    if (!success) {
        [_result sendErrorWithCode:@"IOError" message:@"Unable to write file" details:nil];
        return;
    }
    [_result sendSuccessWithData:_deviceAnglesAndPathDict];
}

@end

// Mirrors FlashMode in flash_mode.dart
typedef enum {
    FlashModeOff,
    FlashModeAuto,
    FlashModeAlways,
    FlashModeTorch,
} FlashMode;

static FlashMode getFlashModeForString(NSString *mode) {
    if ([mode isEqualToString:@"off"]) {
        return FlashModeOff;
    } else if ([mode isEqualToString:@"auto"]) {
        return FlashModeAuto;
    } else if ([mode isEqualToString:@"always"]) {
        return FlashModeAlways;
    } else if ([mode isEqualToString:@"torch"]) {
        return FlashModeTorch;
    } else {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSURLErrorUnknown
                                         userInfo:@{
            NSLocalizedDescriptionKey : [NSString
                                         stringWithFormat:@"Unknown flash mode %@", mode]
        }];
        @throw error;
    }
}

static OSType getVideoFormatFromString(NSString *videoFormatString) {
    if ([videoFormatString isEqualToString:@"bgra8888"]) {
        return kCVPixelFormatType_32BGRA;
    } else if ([videoFormatString isEqualToString:@"yuv420"]) {
        return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    } else {
        NSLog(@"The selected imageFormatGroup is not supported by iOS. Defaulting to brga8888");
        return kCVPixelFormatType_32BGRA;
    }
}

static AVCaptureFlashMode getAVCaptureFlashModeForFlashMode(FlashMode mode) {
    switch (mode) {
        case FlashModeOff:
            return AVCaptureFlashModeOff;
        case FlashModeAuto:
            return AVCaptureFlashModeAuto;
        case FlashModeAlways:
            return AVCaptureFlashModeOn;
        case FlashModeTorch:
        default:
            return -1;
    }
}

// Mirrors ExposureMode in camera.dart
typedef enum {
    ExposureModeAuto,
    ExposureModeLocked,
    
} ExposureMode;

static NSString *getStringForExposureMode(ExposureMode mode) {
    switch (mode) {
        case ExposureModeAuto:
            return @"auto";
        case ExposureModeLocked:
            return @"locked";
    }
    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSURLErrorUnknown
                                     userInfo:@{
        NSLocalizedDescriptionKey : [NSString
                                     stringWithFormat:@"Unknown string for exposure mode"]
    }];
    @throw error;
}

static ExposureMode getExposureModeForString(NSString *mode) {
    if ([mode isEqualToString:@"auto"]) {
        return ExposureModeAuto;
    } else if ([mode isEqualToString:@"locked"]) {
        return ExposureModeLocked;
    } else {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSURLErrorUnknown
                                         userInfo:@{
            NSLocalizedDescriptionKey : [NSString
                                         stringWithFormat:@"Unknown exposure mode %@", mode]
        }];
        @throw error;
    }
}

static UIDeviceOrientation getUIDeviceOrientationForString(NSString *orientation) {
    if ([orientation isEqualToString:@"portraitDown"]) {
        return UIDeviceOrientationPortraitUpsideDown;
    } else if ([orientation isEqualToString:@"landscapeLeft"]) {
        return UIDeviceOrientationLandscapeRight;
    } else if ([orientation isEqualToString:@"landscapeRight"]) {
        return UIDeviceOrientationLandscapeLeft;
    } else if ([orientation isEqualToString:@"portraitUp"]) {
        return UIDeviceOrientationPortrait;
    } else {
        NSError *error = [NSError
                          errorWithDomain:NSCocoaErrorDomain
                          code:NSURLErrorUnknown
                          userInfo:@{
            NSLocalizedDescriptionKey :
                [NSString stringWithFormat:@"Unknown device orientation %@", orientation]
        }];
        @throw error;
    }
}

static NSString *getStringForUIDeviceOrientation(UIDeviceOrientation orientation) {
    switch (orientation) {
        case UIDeviceOrientationPortraitUpsideDown:
            return @"portraitDown";
        case UIDeviceOrientationLandscapeRight:
            return @"landscapeLeft";
        case UIDeviceOrientationLandscapeLeft:
            return @"landscapeRight";
        case UIDeviceOrientationPortrait:
        default:
            return @"portraitUp";
            break;
    };
}

// Mirrors FocusMode in camera.dart
typedef enum {
    FocusModeAuto,
    FocusModeLocked,
} FocusMode;

static NSString *getStringForFocusMode(FocusMode mode) {
    switch (mode) {
        case FocusModeAuto:
            return @"auto";
        case FocusModeLocked:
            return @"locked";
    }
    NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSURLErrorUnknown
                                     userInfo:@{
        NSLocalizedDescriptionKey : [NSString
                                     stringWithFormat:@"Unknown string for focus mode"]
    }];
    @throw error;
}

static FocusMode getFocusModeForString(NSString *mode) {
    if ([mode isEqualToString:@"auto"]) {
        return FocusModeAuto;
    } else if ([mode isEqualToString:@"locked"]) {
        return FocusModeLocked;
    } else {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSURLErrorUnknown
                                         userInfo:@{
            NSLocalizedDescriptionKey : [NSString
                                         stringWithFormat:@"Unknown focus mode %@", mode]
        }];
        @throw error;
    }
}

static ResolutionPreset getResolutionPresetForString(NSString *preset) {
    if ([preset isEqualToString:@"veryLow"]) {
        return veryLow;
    } else if ([preset isEqualToString:@"low"]) {
        return low;
    } else if ([preset isEqualToString:@"medium"]) {
        return medium;
    } else if ([preset isEqualToString:@"high"]) {
        return high;
    } else if ([preset isEqualToString:@"veryHigh"]) {
        return veryHigh;
    } else if ([preset isEqualToString:@"ultraHigh"]) {
        return ultraHigh;
    } else if ([preset isEqualToString:@"max"]) {
        return max;
    } else if ([preset isEqualToString:@"custom43"]) {
        return custom43;
    } else {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSURLErrorUnknown
                                         userInfo:@{
            NSLocalizedDescriptionKey : [NSString
                                         stringWithFormat:@"Unknown resolution preset %@", preset]
        }];
        @throw error;
    }
}

@interface FLTCam : NSObject <FlutterTexture,
AVCaptureVideoDataOutputSampleBufferDelegate,
AVCaptureAudioDataOutputSampleBufferDelegate>
@property(readonly, nonatomic) int64_t textureId;
@property(nonatomic, copy) void (^onFrameAvailable)(void);
@property BOOL enableAudio;
@property(nonatomic) FLTImageStreamHandler *imageStreamHandler;
@property(nonatomic) FlutterMethodChannel *methodChannel;
@property(readonly, nonatomic) AVCaptureSession *captureSession;
@property(readonly, nonatomic) AVCaptureDevice *captureDevice;
@property(readonly, nonatomic) AVCapturePhotoOutput *capturePhotoOutput API_AVAILABLE(ios(10));
@property(readonly, nonatomic) AVCaptureVideoDataOutput *captureVideoOutput;
@property(readonly, nonatomic) AVCaptureInput *captureVideoInput;
@property(readonly) CVPixelBufferRef volatile latestPixelBuffer;
@property(readonly, nonatomic) CGSize previewSize;
@property(readonly, nonatomic) CGSize captureSize;
@property(strong, nonatomic) AVAssetWriter *videoWriter;
@property(strong, nonatomic) AVAssetWriterInput *videoWriterInput;
@property(strong, nonatomic) AVAssetWriterInput *audioWriterInput;
@property(strong, nonatomic) AVAssetWriterInputPixelBufferAdaptor *assetWriterPixelBufferAdaptor;
@property(strong, nonatomic) AVCaptureVideoDataOutput *videoOutput;
@property(strong, nonatomic) AVCaptureAudioDataOutput *audioOutput;
@property(strong, nonatomic) NSString *videoRecordingPath;
@property(assign, nonatomic) BOOL isRecording;
@property(assign, nonatomic) BOOL isRecordingPaused;
@property(assign, nonatomic) BOOL videoIsDisconnected;
@property(assign, nonatomic) BOOL audioIsDisconnected;
@property(assign, nonatomic) BOOL isAudioSetup;
@property(assign, nonatomic) BOOL isStreamingImages;
@property(assign, nonatomic) BOOL isPreviewPaused;
@property(assign, nonatomic) ResolutionPreset resolutionPreset;
@property(assign, nonatomic) ExposureMode exposureMode;
@property(assign, nonatomic) FocusMode focusMode;
@property(assign, nonatomic) FlashMode flashMode;
@property(assign, nonatomic) UIDeviceOrientation lockedCaptureOrientation;
@property(assign, nonatomic) CMTime lastVideoSampleTime;
@property(assign, nonatomic) CMTime lastAudioSampleTime;
@property(assign, nonatomic) CMTime videoTimeOffset;
@property(assign, nonatomic) CMTime audioTimeOffset;
@property(nonatomic) CMMotionManager *motionManager;
@property AVAssetWriterInputPixelBufferAdaptor *videoAdaptor;
@property(assign, nonatomic) int longSideSize;
@property(assign, nonatomic) int imageQality;
@property(assign, atomic) BOOL isVerticalTiltAvailable;
@property(assign, atomic) BOOL isHorizontalTiltAvailable;
@property(assign, atomic) double horizontalTilt;
@property(assign, atomic) double verticalTilt;
@property(assign, atomic) double horizontalTiltToPublish;
@property(assign, atomic) double verticalTiltToPublish;
@property(readonly, nonatomic) FlutterMethodChannel *deviceEventMethodChannel;
@property(assign, atomic) BOOL isBarcodeStreamEnabled;
@property(assign, atomic) BOOL isNextFrameToBarcodeScanRequired;
@property(assign, atomic) long barcodeStreamId;;
@property(assign, atomic) int barcodeCropLeft;
@property(assign, atomic) int barcodeCropRight;
@property(assign, atomic) int barcodeCropTop;
@property(assign, atomic) int barcodeCropBottom;
@property(readonly, nonatomic) ZXMultiFormatReader *barcodeReader;
@property(readonly, nonatomic) ZXDecodeHints *barcodeHints;
@property(nonatomic) FlutterEventChannel *barcodeEventChannel;
@property(nonatomic) BarcodeStreamHandler *barcodeStreamHandler;
@end

@implementation FLTCam {
    dispatch_queue_t _dispatchQueue;
    UIDeviceOrientation _accelerometerDeviceOrientation;
    UIDeviceOrientation _uiDeviceOrientation;
    CGFloat _targetImageRotation;
}
// Format used for video and image streaming.
FourCharCode videoFormat = kCVPixelFormatType_32BGRA;
NSString *const errorMethod = @"error";

- (instancetype)initWithCameraName:(NSString *)cameraName
                  resolutionPreset:(NSString *)resolutionPreset
                      longSideSize:(int)longSideSize
                      imageQuality:(int)imageQuality
                       enableAudio:(BOOL)enableAudio
                       orientation:(UIDeviceOrientation)orientation
                     dispatchQueue:(dispatch_queue_t)dispatchQueue
                             error:(NSError **)error
          deviceEventMethodChannel:(FlutterMethodChannel *)deviceEventMethodChannel
        lockedCaptureOrientationStr:(NSString *)lockedCaptureOrientationStr {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    @try {
        _resolutionPreset = getResolutionPresetForString(resolutionPreset);
    } @catch (NSError *e) {
        *error = e;
    }
    _enableAudio = enableAudio;
    _dispatchQueue = dispatchQueue;
    _captureSession = [[AVCaptureSession alloc] init];
    _captureDevice = [AVCaptureDevice deviceWithUniqueID:cameraName];
    _flashMode = _captureDevice.hasFlash ? FlashModeAuto : FlashModeOff;
    _exposureMode = ExposureModeAuto;
    _focusMode = FocusModeAuto;
    _lockedCaptureOrientation = UIDeviceOrientationUnknown;
    _uiDeviceOrientation = orientation;
    _longSideSize = longSideSize > 0 ? longSideSize : DEFAULT_43FORMAT_LONG_SIDE_SIZE;
    _imageQality = imageQuality > 0 ? imageQuality : DEFAULT_43FORMAT_IMAGE_QUALITY;
    _deviceEventMethodChannel = deviceEventMethodChannel;
    _isBarcodeStreamEnabled = false;
    _barcodeStreamId = 0;
    _isNextFrameToBarcodeScanRequired = false;
    _barcodeCropTop = 0;
    _barcodeCropLeft = 0;
    _barcodeCropRight = 0;
    _barcodeCropBottom = 0;
    
    
    if(lockedCaptureOrientationStr) {
        @try{
            _lockedCaptureOrientation = getUIDeviceOrientationForString(lockedCaptureOrientationStr);
        }
        @catch (NSError *e) {
            _lockedCaptureOrientation = UIDeviceOrientationUnknown;
        }
    } else {
        _lockedCaptureOrientation = UIDeviceOrientationUnknown;
    }
    
    
    NSError *localError = nil;
    _captureVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:_captureDevice
                                                               error:&localError];
    
    if (localError) {
        *error = localError;
        return nil;
    }
    
    _captureVideoOutput = [AVCaptureVideoDataOutput new];
    _captureVideoOutput.videoSettings =
    @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(videoFormat)};
    [_captureVideoOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    AVCaptureConnection *connection =
    [AVCaptureConnection connectionWithInputPorts:_captureVideoInput.ports
                                           output:_captureVideoOutput];
    
    if ([_captureDevice position] == AVCaptureDevicePositionFront) {
        connection.videoMirrored = YES;
    }
    
    [_captureSession addInputWithNoConnections:_captureVideoInput];
    [_captureSession addOutputWithNoConnections:_captureVideoOutput];
    [_captureSession addConnection:connection];
    
    if (@available(iOS 10.0, *)) {
        _capturePhotoOutput = [AVCapturePhotoOutput new];
        [_capturePhotoOutput setHighResolutionCaptureEnabled:YES];
        [_captureSession addOutput:_capturePhotoOutput];
    }
    
    [self setActiveFormatForCamera:_captureDevice
                        resolution:[self setCaptureSessionPreset:_resolutionPreset
                                                   captureDevice:_captureDevice]];
    
    [_captureVideoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [self initSensors];
    [self updateOrientation];
    
    return self;
}

- (void) initSensors {
    _motionManager = [[CMMotionManager alloc] init];
    _isVerticalTiltAvailable = false;
    _isHorizontalTiltAvailable = false;
    _horizontalTilt = 0;
    _verticalTilt = 0;
    
    if ([_motionManager isAccelerometerAvailable]) {
        _isHorizontalTiltAvailable = true;
        
        _motionManager.accelerometerUpdateInterval = 0.1f;
        [_motionManager startAccelerometerUpdatesToQueue:NSOperationQueue.mainQueue
                                             withHandler:^(CMAccelerometerData *accelerometerData, NSError* error) {
            if(accelerometerData!=nil && error == nil) {
                [self calculateAccelerometerAngles:accelerometerData.acceleration];
                if(!self->_isVerticalTiltAvailable) {
                    [self sendAnglesUpdate];
                }
            }
        }];
    }
    
    if([_motionManager isDeviceMotionAvailable]) {
        _isVerticalTiltAvailable = true;
        
        _motionManager.deviceMotionUpdateInterval = 0.1f;
        [_motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
                                                            toQueue:NSOperationQueue.mainQueue
                                                        withHandler:^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error) {
            double verticalTilt = asin(sqrt(pow(motion.attitude.quaternion.x, 2) + pow(motion.attitude.quaternion.y, 2))) * 360 / M_PI - 90;
            self->_verticalTilt = verticalTilt;
            //NSLog(@"VerticalTilt:%f", verticalTilt);
            if(verticalTilt<=45 && verticalTilt >=-45) {
                self->_verticalTiltToPublish = verticalTilt;
            } else {
                double overheadVerticalTilt = 0;
                double overheadHorizontalTilt = 0;
                int targetRotation = self->_lockedCaptureOrientation == UIDeviceOrientationUnknown
                ? [self getRotationAngleForOrintation:self->_uiDeviceOrientation]
                : (int)self->_targetImageRotation;
                
                switch(targetRotation) {
                    case 0:
                        overheadVerticalTilt = motion.attitude.pitch * 180 / M_PI;
                        overheadHorizontalTilt = -motion.attitude.roll * 180 / M_PI;
                        break;
                    case 90:
                        overheadVerticalTilt = motion.attitude.roll * 180 / M_PI;
                        overheadHorizontalTilt = motion.attitude.pitch * 180 / M_PI;
                        break;
                    case 180:
                        overheadVerticalTilt = -motion.attitude.pitch * 180 / M_PI;
                        overheadHorizontalTilt = motion.attitude.roll * 180 / M_PI;
                        break;
                    case 270:
                        overheadVerticalTilt = -motion.attitude.roll * 180 / M_PI;
                        overheadHorizontalTilt = -motion.attitude.pitch * 180 / M_PI;
                        break;
                    default:
                        break;
                }
                //NSLog(@"overheadVerticalTilt:%f", overheadVerticalTilt);
                //NSLog(@"overheadHorizontalTilt:%f", overheadHorizontalTilt);
                self->_verticalTiltToPublish = overheadVerticalTilt;
                self->_horizontalTiltToPublish = overheadHorizontalTilt;
            }
            [self sendAnglesUpdate];
        }];
    }
}

-(void) calculateAccelerometerAngles:(CMAcceleration)acceleration {
    double accelerometerAngle = fmod(atan2(-acceleration.x, acceleration.y) * 180 / M_PI + 180, 360);
    self ->_uiDeviceOrientation = [[UIDevice currentDevice] orientation];
    
    //NSLog(@"accelerometerAngle=%f", accelerometerAngle);
    
    if(!_isVerticalTiltAvailable || (_verticalTilt <= 45 && _verticalTilt >= -45)) {
        if(fabs(acceleration.y) < fabs(acceleration.x)) {
            if(acceleration.x > 0 ) {
                [self setAccelerometerDeviceOrientation: UIDeviceOrientationLandscapeRight];
            } else {
                [self setAccelerometerDeviceOrientation: UIDeviceOrientationLandscapeLeft];
            }
        } else {
            if(acceleration.y > 0 ) {
                [self setAccelerometerDeviceOrientation: UIDeviceOrientationPortraitUpsideDown];
            } else {
                [self setAccelerometerDeviceOrientation: UIDeviceOrientationPortrait];
            }
        }
        
        self->_targetImageRotation =
        (self->_lockedCaptureOrientation == UIDeviceOrientationUnknown && self->_accelerometerDeviceOrientation == self->_uiDeviceOrientation)? 0 :
        (self->_accelerometerDeviceOrientation != self->_uiDeviceOrientation
         // when UI orientation is fixed in the device settings
         ? [self getRotationAngleForOrintation:self->_accelerometerDeviceOrientation] -
         [self getRotationAngleForOrintation:self->_uiDeviceOrientation]
         // when UI orientation changing is allowed in the device settings
         : [self getRotationAngleForOrintation:self->_uiDeviceOrientation] -
         [self getRotationAngleForOrintation:self->_lockedCaptureOrientation]);
        //NSLog(@"targetImageRotation=%f", self->_targetImageRotation);
    }
    
    if(!_isVerticalTiltAvailable || (_verticalTilt <= 45 && _verticalTilt >= -45)) {
        double horizontalTilt = self->_lockedCaptureOrientation == UIDeviceOrientationUnknown
        /// Image capture orientation is not locked
        ?(self->_accelerometerDeviceOrientation == self->_uiDeviceOrientation ?
          /// UI is not locked, so the UI orientation is equal the accelerometer orientation
          [self getRotationAngleForOrintation:self->_uiDeviceOrientation] - accelerometerAngle
          /// UI is locked, so the UI orientation is not equal accelerometer orientation
          :[self getRotationAngleForOrintation:self->_accelerometerDeviceOrientation] - accelerometerAngle)
        : self->_targetImageRotation - accelerometerAngle;
        
        self->_horizontalTilt = fabs(horizontalTilt) > 90 ? horizontalTilt + 360 : horizontalTilt;
        self->_horizontalTiltToPublish = self->_horizontalTilt;
        //NSLog(@"horizontalTilt=%f", self->_horizontalTilt);
    }
}

-(int) getRotationAngleForOrintation:(UIDeviceOrientation)orintation {
    switch (orintation) {
        case UIDeviceOrientationLandscapeLeft:
            return 270;
        case UIDeviceOrientationLandscapeRight:
            return 90;
        case UIDeviceOrientationPortraitUpsideDown:
            return 180;
        case UIDeviceOrientationPortrait:
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationFaceDown:
        case UIDeviceOrientationUnknown:
            return  0;
    }
}

- (void)sendAnglesUpdate {
    NSMutableDictionary* anglesDict = [self getAnglesDictionary];
    [_deviceEventMethodChannel invokeMethod:@"tilts_changed"
                                  arguments:anglesDict];
}

-(NSMutableDictionary*) getAnglesDictionary {
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    dict[@"isVerticalTiltAvailable"] = @(_isVerticalTiltAvailable);
    dict[@"isHorizontalTiltAvailable"] = @(_isHorizontalTiltAvailable);
    dict[@"horizontalTilt"] = @(_horizontalTiltToPublish);
    dict[@"verticalTilt"] = @(_verticalTiltToPublish);
    dict[@"mode"] = _isVerticalTiltAvailable
    ? (_verticalTilt <= 45 && _verticalTilt >= -45 ? @"normalShot" : @"overheadShot" )
    : @"unknownShot";
    dict[@"targetImageRotation"] = @(_targetImageRotation);
    dict[@"lockedCaptureAngle"] = @(_lockedCaptureOrientation != UIDeviceOrientationUnknown
    ? [self getRotationAngleForOrintation:_lockedCaptureOrientation]
    : -1);
    dict[@"deviceOrientationAngle"] = @([self getRotationAngleForOrintation:_uiDeviceOrientation]);
    dict[@"isUIRotationEqualAccRotation"] =@((bool)(self->_accelerometerDeviceOrientation == self->_uiDeviceOrientation ? true : false));
    return dict;
}

- (void)start {
    if(_isBarcodeStreamEnabled) {
        _barcodeHints = [ZXDecodeHints hints];
        [_barcodeHints addPossibleFormat:kBarcodeFormatEan8];
        [_barcodeHints addPossibleFormat:kBarcodeFormatEan13];
        [_barcodeHints addPossibleFormat:kBarcodeFormatRSSExpanded];
        [_barcodeHints addPossibleFormat:kBarcodeFormatRSS14];
        
        _barcodeReader = [ZXMultiFormatReader reader];
        _isNextFrameToBarcodeScanRequired = true;
        
        if(_barcodeEventChannel != nil) {
            _barcodeStreamHandler = [[BarcodeStreamHandler alloc] init];
            if (!NSThread.isMainThread) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->_barcodeEventChannel setStreamHandler:self->_barcodeStreamHandler];
                });
            } else {
                [_barcodeEventChannel setStreamHandler:_barcodeStreamHandler];
            }
            
        }
    }
    [_captureSession startRunning];
}

- (void)stop {
    [_captureSession stopRunning];
}

- (void)setAccelerometerDeviceOrientation:(UIDeviceOrientation)orientation {
    if (_accelerometerDeviceOrientation == orientation) {
        return;
    }
    _accelerometerDeviceOrientation = orientation;
}

- (void)setUiDeviceOrientation:(UIDeviceOrientation)orientation {
    if (_uiDeviceOrientation == orientation) {
        return;
    }
    _uiDeviceOrientation = orientation;
    [self updateOrientation];
}

- (void)updateOrientation {
    if (_isRecording) {
        return;
    }
    
    UIDeviceOrientation orientation = (_lockedCaptureOrientation != UIDeviceOrientationUnknown)
    ? _lockedCaptureOrientation
    : _uiDeviceOrientation;
    
    [self updateOrientation:orientation forCaptureOutput:_capturePhotoOutput];
    [self updateOrientation:orientation forCaptureOutput:_captureVideoOutput];
}

- (void)updateOrientation:(UIDeviceOrientation)orientation
         forCaptureOutput:(AVCaptureOutput *)captureOutput {
    if (!captureOutput) {
        return;
    }
    
    AVCaptureConnection *connection = [captureOutput connectionWithMediaType:AVMediaTypeVideo];
    if (connection && connection.isVideoOrientationSupported) {
        connection.videoOrientation = [self getVideoOrientationForDeviceOrientation:orientation];
    }
}

- (void)captureToFile:(FLTThreadSafeFlutterResult *)result API_AVAILABLE(ios(10)) {
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
    if (_resolutionPreset == max) {
        [settings setHighResolutionPhotoEnabled:YES];
    }
    
    AVCaptureFlashMode avFlashMode = getAVCaptureFlashModeForFlashMode(_flashMode);
    if (avFlashMode != -1) {
        [settings setFlashMode:avFlashMode];
    }
    NSError *error;
    NSString *path = [self getTemporaryFilePathWithExtension:@"jpg"
                                                   subfolder:@"pictures"
                                                      prefix:@"CAP_"
                                                       error:error];
    if (error) {
        [result sendError:error];
        return;
    }
    
    
    [_capturePhotoOutput capturePhotoWithSettings:settings
                                         delegate:[[FLTSavePhotoDelegate alloc] initWithPath:path
                                                                                      result:result
                                                                    targetImageRotationInRad:_targetImageRotation * M_PI / 180
                                                                            resolutionPreset:_resolutionPreset
                                                                                longSideSize:_longSideSize
                                                                                imageQuality:_imageQality
                                                                            deviceAnglesDict:[self getAnglesDictionary]]];
}

- (AVCaptureVideoOrientation)getVideoOrientationForDeviceOrientation:
(UIDeviceOrientation)deviceOrientation {
    if (deviceOrientation == UIDeviceOrientationPortrait) {
        return AVCaptureVideoOrientationPortrait;
    } else if (deviceOrientation == UIDeviceOrientationLandscapeLeft) {
        // Note: device orientation is flipped compared to video orientation. When UIDeviceOrientation
        // is landscape left the video orientation should be landscape right.
        return AVCaptureVideoOrientationLandscapeRight;
    } else if (deviceOrientation == UIDeviceOrientationLandscapeRight) {
        // Note: device orientation is flipped compared to video orientation. When UIDeviceOrientation
        // is landscape right the video orientation should be landscape left.
        return AVCaptureVideoOrientationLandscapeLeft;
    } else if (deviceOrientation == UIDeviceOrientationPortraitUpsideDown) {
        return AVCaptureVideoOrientationPortraitUpsideDown;
    } else {
        return AVCaptureVideoOrientationPortrait;
    }
}

- (NSString *)getTemporaryFilePathWithExtension:(NSString *)extension
                                      subfolder:(NSString *)subfolder
                                         prefix:(NSString *)prefix
                                          error:(NSError *)error {
    NSString *docDir =
    NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *fileDir =
    [[docDir stringByAppendingPathComponent:@"camera"] stringByAppendingPathComponent:subfolder];
    NSString *fileName = [prefix stringByAppendingString:[[NSUUID UUID] UUIDString]];
    NSString *file =
    [[fileDir stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:extension];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:fileDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:fileDir
                                  withIntermediateDirectories:true
                                                   attributes:nil
                                                        error:&error];
        if (error) {
            return nil;
        }
    }
    
    return file;
}


- (NSCameraResolution*)setCaptureSessionPreset:(ResolutionPreset)resolutionPreset
                                 captureDevice:(AVCaptureDevice *)captureDevice{
    
    [self setCaptureSessionDefaultPreset:resolutionPreset];
    
    
    if(resolutionPreset == custom43) {
        NSMutableArray* resolutions = [[NSMutableArray alloc] init];
        
        for (AVCaptureDeviceFormat* format in captureDevice.formats) {
            CMVideoFormatDescriptionRef formatDescription = format.formatDescription;
            CMVideoDimensions dimentions = CMVideoFormatDescriptionGetDimensions(formatDescription);
            FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription);
            
            float aspectRatio = ((float) dimentions.width) / dimentions.height;
            
            if(aspectRatio >= PREFFERED_43FORMAT_LOW_ASPECT_RATIO &&
               aspectRatio <= PREFFERED_43FORMAT_HIGH_ASPECT_RATIO &&
               mediaSubType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
               ) {
                NSCameraResolution* resolution = [[NSCameraResolution alloc]
                                                  initWithWidth:dimentions.width
                                                  andHeight:dimentions.height
                                                  andFormat:format];
                [resolutions addObject:resolution];
            }
        }
        
        [resolutions sortUsingComparator:compareCamaraResolution];
        NSMutableArray* selectedResolutions = [[NSMutableArray alloc] init];
        
        for(NSCameraResolution* resolution in resolutions) {
            if(resolution.width >= _longSideSize) {
                [selectedResolutions addObject:resolution];
            }
        }
        
        NSLog(@"All resolutions:%@", resolutions);
        NSLog(@"Filtered resolutions:%@", selectedResolutions);
        NSCameraResolution* resolution;
        
        if([selectedResolutions count] > 0) {
            resolution = [selectedResolutions objectAtIndex:0];
        } else {
            resolution = [resolutions lastObject];
        }
        
        NSLog(@"Selected 4:3 resolution is %@", resolution);
        _previewSize = CGSizeMake(resolution.width, resolution.heigh);
        return resolution;
    }
    return nil;
}

NSComparisonResult (^compareCamaraResolution) (id,id) = ^(id obj1, id obj2)
{
    if([obj1 isKindOfClass:[NSCameraResolution class]] && [obj2 isKindOfClass:[NSCameraResolution class]]) {
        NSCameraResolution* r1 = obj1;
        NSCameraResolution* r2 = obj2;
        if(r1.width < r2.width) {
            return (NSComparisonResult) NSOrderedAscending;
        } else if(r1.width > r2.width) {
            return (NSComparisonResult) NSOrderedDescending;
        } else  if(r1.heigh < r2.heigh) {
            return (NSComparisonResult) NSOrderedAscending;
        } else if(r1.heigh > r2.heigh) {
            return (NSComparisonResult) NSOrderedDescending;
        }
    }
    return (NSComparisonResult)NSOrderedSame;
};

-(void) setActiveFormatForCamera:(AVCaptureDevice*)device
                      resolution:(NSCameraResolution* _Nullable) resolution {
    if(resolution == nil) {
        NSLog(@"Resolution is nil, skip camera device configuring");
        return;
    }
    NSError* error = nil;
    bool isLocked = [device lockForConfiguration:&error];
    if(!isLocked) {
        NSLog(@"Fail to lock camera device to configure: %@", error);
        return;
    }
    [device setActiveFormat: resolution.format];
    [device unlockForConfiguration];
    NSLog(@"Camera device was configured to format %@", resolution.format);
}

- (void)setCaptureSessionDefaultPreset:(ResolutionPreset)resolutionPreset {
    switch (resolutionPreset) {
        case max:
        case ultraHigh:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset3840x2160]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset3840x2160;
                _previewSize = CGSizeMake(3840, 2160);
                break;
            }
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
                _captureSession.sessionPreset = AVCaptureSessionPresetHigh;
                _previewSize =
                CGSizeMake(_captureDevice.activeFormat.highResolutionStillImageDimensions.width,
                           _captureDevice.activeFormat.highResolutionStillImageDimensions.height);
                break;
            }
        case veryHigh:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
                _previewSize = CGSizeMake(1920, 1080);
                break;
            }
        case custom43:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
                _previewSize = CGSizeMake(1920, 1080);
                break;
            }
        case high:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
                _previewSize = CGSizeMake(1280, 720);
                break;
            }
        case medium:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset640x480;
                _previewSize = CGSizeMake(640, 480);
                break;
            }
        case low:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset352x288]) {
                _captureSession.sessionPreset = AVCaptureSessionPreset352x288;
                _previewSize = CGSizeMake(352, 288);
                break;
            }
        default:
            if ([_captureSession canSetSessionPreset:AVCaptureSessionPresetLow]) {
                _captureSession.sessionPreset = AVCaptureSessionPresetLow;
                _previewSize = CGSizeMake(352, 288);
            } else {
                NSError *error =
                [NSError errorWithDomain:NSCocoaErrorDomain
                                    code:NSURLErrorUnknown
                                userInfo:@{
                    NSLocalizedDescriptionKey :
                        @"No capture session available for current capture session."
                }];
                @throw error;
            }
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (output == _captureVideoOutput) {
        CVPixelBufferRef newBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CFRetain(newBuffer);
        CVPixelBufferRef old = _latestPixelBuffer;
        while (!OSAtomicCompareAndSwapPtrBarrier(old, newBuffer, (void **)&_latestPixelBuffer)) {
            old = _latestPixelBuffer;
        }
        if (old != nil) {
            CFRelease(old);
        }
        if (_onFrameAvailable) {
            _onFrameAvailable();
        }
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        [_methodChannel invokeMethod:errorMethod
                           arguments:@"sample buffer is not ready. Skipping sample"];
        return;
    }
    if (_isStreamingImages) {
        if (_imageStreamHandler.eventSink) {
            CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
            CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
            
            size_t imageWidth = CVPixelBufferGetWidth(pixelBuffer);
            size_t imageHeight = CVPixelBufferGetHeight(pixelBuffer);
            
            NSMutableArray *planes = [NSMutableArray array];
            
            const Boolean isPlanar = CVPixelBufferIsPlanar(pixelBuffer);
            size_t planeCount;
            if (isPlanar) {
                planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
            } else {
                planeCount = 1;
            }
            
            for (int i = 0; i < planeCount; i++) {
                void *planeAddress;
                size_t bytesPerRow;
                size_t height;
                size_t width;
                
                if (isPlanar) {
                    planeAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, i);
                    bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, i);
                    height = CVPixelBufferGetHeightOfPlane(pixelBuffer, i);
                    width = CVPixelBufferGetWidthOfPlane(pixelBuffer, i);
                } else {
                    planeAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
                    bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
                    height = CVPixelBufferGetHeight(pixelBuffer);
                    width = CVPixelBufferGetWidth(pixelBuffer);
                }
                
                NSNumber *length = @(bytesPerRow * height);
                NSData *bytes = [NSData dataWithBytes:planeAddress length:length.unsignedIntegerValue];
                
                NSMutableDictionary *planeBuffer = [NSMutableDictionary dictionary];
                planeBuffer[@"bytesPerRow"] = @(bytesPerRow);
                planeBuffer[@"width"] = @(width);
                planeBuffer[@"height"] = @(height);
                planeBuffer[@"bytes"] = [FlutterStandardTypedData typedDataWithBytes:bytes];
                
                [planes addObject:planeBuffer];
            }
            
            NSMutableDictionary *imageBuffer = [NSMutableDictionary dictionary];
            imageBuffer[@"width"] = [NSNumber numberWithUnsignedLong:imageWidth];
            imageBuffer[@"height"] = [NSNumber numberWithUnsignedLong:imageHeight];
            imageBuffer[@"format"] = @(videoFormat);
            imageBuffer[@"planes"] = planes;
            imageBuffer[@"lensAperture"] = [NSNumber numberWithFloat:[_captureDevice lensAperture]];
            Float64 exposureDuration = CMTimeGetSeconds([_captureDevice exposureDuration]);
            Float64 nsExposureDuration = 1000000000 * exposureDuration;
            imageBuffer[@"sensorExposureTime"] = [NSNumber numberWithInt:nsExposureDuration];
            imageBuffer[@"sensorSensitivity"] = [NSNumber numberWithFloat:[_captureDevice ISO]];
            
            _imageStreamHandler.eventSink(imageBuffer);
            
            CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        }
    }
    if (_isRecording && !_isRecordingPaused) {
        if (_videoWriter.status == AVAssetWriterStatusFailed) {
            [_methodChannel invokeMethod:errorMethod
                               arguments:[NSString stringWithFormat:@"%@", _videoWriter.error]];
            return;
        }
        
        CFRetain(sampleBuffer);
        CMTime currentSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        
        if (_videoWriter.status != AVAssetWriterStatusWriting) {
            [_videoWriter startWriting];
            [_videoWriter startSessionAtSourceTime:currentSampleTime];
        }
        
        if (output == _captureVideoOutput) {
            if (_videoIsDisconnected) {
                _videoIsDisconnected = NO;
                
                if (_videoTimeOffset.value == 0) {
                    _videoTimeOffset = CMTimeSubtract(currentSampleTime, _lastVideoSampleTime);
                } else {
                    CMTime offset = CMTimeSubtract(currentSampleTime, _lastVideoSampleTime);
                    _videoTimeOffset = CMTimeAdd(_videoTimeOffset, offset);
                }
                
                return;
            }
            
            _lastVideoSampleTime = currentSampleTime;
            
            CVPixelBufferRef nextBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
            CMTime nextSampleTime = CMTimeSubtract(_lastVideoSampleTime, _videoTimeOffset);
            [_videoAdaptor appendPixelBuffer:nextBuffer withPresentationTime:nextSampleTime];
        } else {
            CMTime dur = CMSampleBufferGetDuration(sampleBuffer);
            
            if (dur.value > 0) {
                currentSampleTime = CMTimeAdd(currentSampleTime, dur);
            }
            
            if (_audioIsDisconnected) {
                _audioIsDisconnected = NO;
                
                if (_audioTimeOffset.value == 0) {
                    _audioTimeOffset = CMTimeSubtract(currentSampleTime, _lastAudioSampleTime);
                } else {
                    CMTime offset = CMTimeSubtract(currentSampleTime, _lastAudioSampleTime);
                    _audioTimeOffset = CMTimeAdd(_audioTimeOffset, offset);
                }
                
                return;
            }
            
            _lastAudioSampleTime = currentSampleTime;
            
            if (_audioTimeOffset.value != 0) {
                CFRelease(sampleBuffer);
                sampleBuffer = [self adjustTime:sampleBuffer by:_audioTimeOffset];
            }
            
            [self newAudioSample:sampleBuffer];
        }
        
        CFRelease(sampleBuffer);
    }
    
    if(_isBarcodeStreamEnabled && _isNextFrameToBarcodeScanRequired) {
        _isNextFrameToBarcodeScanRequired = false;
        
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        size_t imageWidth = CVPixelBufferGetWidth(pixelBuffer);
        size_t imageHeight = CVPixelBufferGetHeight(pixelBuffer);
        size_t left = imageWidth * ((float)_barcodeCropLeft / 100);
        size_t right = imageWidth * ((float)_barcodeCropRight / 100);
        size_t top = imageHeight * ((float)_barcodeCropTop / 100);
        size_t bottom = imageHeight * ((float)_barcodeCropBottom / 100);
        
        ZXLuminanceSource *source = [
            [ZXCGImageLuminanceSource alloc]
            initWithBuffer:pixelBuffer
            left: left
            top: top
            width: imageWidth - left - right
            height: imageHeight - top - bottom];
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        [self recognizeBarcode:source];
    }
}

- (void)recognizeBarcode:(ZXLuminanceSource*)source {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if(self->_barcodeReader != nil && self->_barcodeHints != nil && self->_barcodeStreamHandler != nil && self->_barcodeStreamHandler.eventSink != nil) {
            
            ZXBinaryBitmap *bitmap = [ZXBinaryBitmap binaryBitmapWithBinarizer:[ZXHybridBinarizer binarizerWithSource:source]];
            
            NSError *error = nil;
            
            ZXResult *result = [self->_barcodeReader decode:bitmap
                                                      hints:self->_barcodeHints
                                                      error:&error];
            if (result) {
                NSMutableDictionary* dict = [NSMutableDictionary dictionary];
                dict[@"text"] = result.text;
                dict[@"format"] = [self barcodeFormatToString:result.barcodeFormat];
                
                if(self->_barcodeStreamHandler && self->_barcodeStreamHandler.eventSink) {
                    self->_barcodeStreamHandler.eventSink(dict);
                }
            }
            self->_isNextFrameToBarcodeScanRequired = true;
        }
    });
}

- (NSString*)barcodeFormatToString: (ZXBarcodeFormat) barcodeFormat {
    switch(barcodeFormat) {
        case kBarcodeFormatAztec: return @"Aztec";
        case kBarcodeFormatCodabar : return @"Codabar";
        case kBarcodeFormatCode39: return @"Code39";
        case kBarcodeFormatCode93: return @"Code93";
        case kBarcodeFormatCode128: return @"Code128";
        case kBarcodeFormatDataMatrix: return @"DataMatrix";
        case kBarcodeFormatEan8: return @"Ean8";
        case kBarcodeFormatEan13: return @"Ean13";
        case kBarcodeFormatITF: return @"ITF";
        case kBarcodeFormatMaxiCode: return @"MaxiCode";
        case kBarcodeFormatPDF417: return @"PDF417";
        case kBarcodeFormatQRCode: return @"QRCode";
        case kBarcodeFormatRSS14: return @"RSS14";
        case kBarcodeFormatRSSExpanded: return @"RSSExpanded";
        case kBarcodeFormatUPCA: return @"UPCA";
        case kBarcodeFormatUPCE: return @"UPCE";
        case kBarcodeFormatUPCEANExtension: return @"UPCEANExtension";
    }
    
}
- (CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sample by:(CMTime)offset CF_RETURNS_RETAINED {
    CMItemCount count;
    CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
    CMSampleTimingInfo *pInfo = malloc(sizeof(CMSampleTimingInfo) * count);
    CMSampleBufferGetSampleTimingInfoArray(sample, count, pInfo, &count);
    for (CMItemCount i = 0; i < count; i++) {
        pInfo[i].decodeTimeStamp = CMTimeSubtract(pInfo[i].decodeTimeStamp, offset);
        pInfo[i].presentationTimeStamp = CMTimeSubtract(pInfo[i].presentationTimeStamp, offset);
    }
    CMSampleBufferRef sout;
    CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, pInfo, &sout);
    free(pInfo);
    return sout;
}

- (void)newVideoSample:(CMSampleBufferRef)sampleBuffer {
    if (_videoWriter.status != AVAssetWriterStatusWriting) {
        if (_videoWriter.status == AVAssetWriterStatusFailed) {
            [_methodChannel invokeMethod:errorMethod
                               arguments:[NSString stringWithFormat:@"%@", _videoWriter.error]];
        }
        return;
    }
    if (_videoWriterInput.readyForMoreMediaData) {
        if (![_videoWriterInput appendSampleBuffer:sampleBuffer]) {
            [_methodChannel
             invokeMethod:errorMethod
             arguments:[NSString stringWithFormat:@"%@", @"Unable to write to video input"]];
        }
    }
}

- (void)newAudioSample:(CMSampleBufferRef)sampleBuffer {
    if (_videoWriter.status != AVAssetWriterStatusWriting) {
        if (_videoWriter.status == AVAssetWriterStatusFailed) {
            [_methodChannel invokeMethod:errorMethod
                               arguments:[NSString stringWithFormat:@"%@", _videoWriter.error]];
        }
        return;
    }
    if (_audioWriterInput.readyForMoreMediaData) {
        if (![_audioWriterInput appendSampleBuffer:sampleBuffer]) {
            [_methodChannel
             invokeMethod:errorMethod
             arguments:[NSString stringWithFormat:@"%@", @"Unable to write to audio input"]];
        }
    }
}

- (void)close {
    [_captureSession stopRunning];
    for (AVCaptureInput *input in [_captureSession inputs]) {
        [_captureSession removeInput:input];
    }
    for (AVCaptureOutput *output in [_captureSession outputs]) {
        [_captureSession removeOutput:output];
    }
    [_motionManager stopAccelerometerUpdates];
    [_motionManager stopDeviceMotionUpdates];
}

- (void)dealloc {
    if (_latestPixelBuffer) {
        CFRelease(_latestPixelBuffer);
    }
}

- (CVPixelBufferRef)copyPixelBuffer {
    CVPixelBufferRef pixelBuffer = _latestPixelBuffer;
    while (!OSAtomicCompareAndSwapPtrBarrier(pixelBuffer, nil, (void **)&_latestPixelBuffer)) {
        pixelBuffer = _latestPixelBuffer;
    }
    
    return pixelBuffer;
}

- (void)startVideoRecordingWithResult:(FLTThreadSafeFlutterResult *)result {
    if (!_isRecording) {
        NSError *error;
        _videoRecordingPath = [self getTemporaryFilePathWithExtension:@"mp4"
                                                            subfolder:@"videos"
                                                               prefix:@"REC_"
                                                                error:error];
        if (error) {
            [result sendError:error];
            return;
        }
        if (![self setupWriterForPath:_videoRecordingPath]) {
            [result sendErrorWithCode:@"IOError" message:@"Setup Writer Failed" details:nil];
            return;
        }
        _isRecording = YES;
        _isRecordingPaused = NO;
        _videoTimeOffset = CMTimeMake(0, 1);
        _audioTimeOffset = CMTimeMake(0, 1);
        _videoIsDisconnected = NO;
        _audioIsDisconnected = NO;
        [result sendSuccess];
    } else {
        [result sendErrorWithCode:@"Error" message:@"Video is already recording" details:nil];
    }
}

- (void)stopVideoRecordingWithResult:(FLTThreadSafeFlutterResult *)result {
    if (_isRecording) {
        _isRecording = NO;
        
        if (_videoWriter.status != AVAssetWriterStatusUnknown) {
            [_videoWriter finishWritingWithCompletionHandler:^{
                if (self->_videoWriter.status == AVAssetWriterStatusCompleted) {
                    [self updateOrientation];
                    [result sendSuccessWithData:self->_videoRecordingPath];
                    self->_videoRecordingPath = nil;
                } else {
                    [result sendErrorWithCode:@"IOError"
                                      message:@"AVAssetWriter could not finish writing!"
                                      details:nil];
                }
            }];
        }
    } else {
        NSError *error =
        [NSError errorWithDomain:NSCocoaErrorDomain
                            code:NSURLErrorResourceUnavailable
                        userInfo:@{NSLocalizedDescriptionKey : @"Video is not recording!"}];
        [result sendError:error];
    }
}

- (void)pauseVideoRecordingWithResult:(FLTThreadSafeFlutterResult *)result {
    _isRecordingPaused = YES;
    _videoIsDisconnected = YES;
    _audioIsDisconnected = YES;
    [result sendSuccess];
}

- (void)resumeVideoRecordingWithResult:(FLTThreadSafeFlutterResult *)result {
    _isRecordingPaused = NO;
    [result sendSuccess];
}

- (void)setFlashModeWithResult:(FLTThreadSafeFlutterResult *)result mode:(NSString *)modeStr {
    FlashMode mode;
    @try {
        mode = getFlashModeForString(modeStr);
    } @catch (NSError *e) {
        [result sendError:e];
        return;
    }
    if (mode == FlashModeTorch) {
        if (!_captureDevice.hasTorch) {
            [result sendErrorWithCode:@"setFlashModeFailed"
                              message:@"Device does not support torch mode"
                              details:nil];
            return;
        }
        if (!_captureDevice.isTorchAvailable) {
            [result sendErrorWithCode:@"setFlashModeFailed"
                              message:@"Torch mode is currently not available"
                              details:nil];
            return;
        }
        if (_captureDevice.torchMode != AVCaptureTorchModeOn) {
            [_captureDevice lockForConfiguration:nil];
            [_captureDevice setTorchMode:AVCaptureTorchModeOn];
            [_captureDevice unlockForConfiguration];
        }
    } else {
        if (!_captureDevice.hasFlash) {
            [result sendErrorWithCode:@"setFlashModeFailed"
                              message:@"Device does not have flash capabilities"
                              details:nil];
            return;
        }
        AVCaptureFlashMode avFlashMode = getAVCaptureFlashModeForFlashMode(mode);
        if (![_capturePhotoOutput.supportedFlashModes
              containsObject:[NSNumber numberWithInt:((int)avFlashMode)]]) {
            [result sendErrorWithCode:@"setFlashModeFailed"
                              message:@"Device does not support this specific flash mode"
                              details:nil];
            return;
        }
        if (_captureDevice.torchMode != AVCaptureTorchModeOff) {
            [_captureDevice lockForConfiguration:nil];
            [_captureDevice setTorchMode:AVCaptureTorchModeOff];
            [_captureDevice unlockForConfiguration];
        }
    }
    _flashMode = mode;
    [result sendSuccess];
}

- (void)setExposureModeWithResult:(FLTThreadSafeFlutterResult *)result mode:(NSString *)modeStr {
    ExposureMode mode;
    @try {
        mode = getExposureModeForString(modeStr);
    } @catch (NSError *e) {
        [result sendError:e];
        return;
    }
    _exposureMode = mode;
    [self applyExposureMode];
    [result sendSuccess];
}

- (void)applyExposureMode {
    [_captureDevice lockForConfiguration:nil];
    switch (_exposureMode) {
        case ExposureModeLocked:
            [_captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
            break;
        case ExposureModeAuto:
            if ([_captureDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
                [_captureDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            } else {
                [_captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
            }
            break;
    }
    [_captureDevice unlockForConfiguration];
}

- (void)setFocusModeWithResult:(FLTThreadSafeFlutterResult *)result mode:(NSString *)modeStr {
    FocusMode mode;
    @try {
        mode = getFocusModeForString(modeStr);
    } @catch (NSError *e) {
        [result sendError:e];
        return;
    }
    _focusMode = mode;
    [self applyFocusMode];
    [result sendSuccess];
}

- (void)applyFocusMode {
    [self applyFocusMode:_focusMode onDevice:_captureDevice];
}

/**
 * Applies FocusMode on the AVCaptureDevice.
 *
 * If the @c focusMode is set to FocusModeAuto the AVCaptureDevice is configured to use
 * AVCaptureFocusModeContinuousModeAutoFocus when supported, otherwise it is set to
 * AVCaptureFocusModeAutoFocus. If neither AVCaptureFocusModeContinuousModeAutoFocus nor
 * AVCaptureFocusModeAutoFocus are supported focus mode will not be set.
 * If @c focusMode is set to FocusModeLocked the AVCaptureDevice is configured to use
 * AVCaptureFocusModeAutoFocus. If AVCaptureFocusModeAutoFocus is not supported focus mode will not
 * be set.
 *
 * @param focusMode The focus mode that should be applied to the @captureDevice instance.
 * @param captureDevice The AVCaptureDevice to which the @focusMode will be applied.
 */
- (void)applyFocusMode:(FocusMode)focusMode onDevice:(AVCaptureDevice *)captureDevice {
    [captureDevice lockForConfiguration:nil];
    switch (focusMode) {
        case FocusModeLocked:
            if ([captureDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
                [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
            }
            break;
        case FocusModeAuto:
            if ([captureDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
                [captureDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
            } else if ([captureDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
                [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
            }
            break;
    }
    [captureDevice unlockForConfiguration];
}

- (void)pausePreviewWithResult:(FLTThreadSafeFlutterResult *)result {
    _isPreviewPaused = true;
    [result sendSuccess];
}

- (void)resumePreviewWithResult:(FLTThreadSafeFlutterResult *)result {
    _isPreviewPaused = false;
    [result sendSuccess];
}

- (CGPoint)getCGPointForCoordsWithOrientation:(UIDeviceOrientation)orientation
                                            x:(double)x
                                            y:(double)y {
    double oldX = x, oldY = y;
    switch (orientation) {
        case UIDeviceOrientationPortrait:  // 90 ccw
            y = 1 - oldX;
            x = oldY;
            break;
        case UIDeviceOrientationPortraitUpsideDown:  // 90 cw
            x = 1 - oldY;
            y = oldX;
            break;
        case UIDeviceOrientationLandscapeRight:  // 180
            x = 1 - x;
            y = 1 - y;
            break;
        case UIDeviceOrientationLandscapeLeft:
        default:
            // No rotation required
            break;
    }
    return CGPointMake(x, y);
}

- (void)setExposurePointWithResult:(FLTThreadSafeFlutterResult *)result x:(double)x y:(double)y {
    if (!_captureDevice.isExposurePointOfInterestSupported) {
        [result sendErrorWithCode:@"setExposurePointFailed"
                          message:@"Device does not have exposure point capabilities"
                          details:nil];
        return;
    }
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    [_captureDevice lockForConfiguration:nil];
    [_captureDevice setExposurePointOfInterest:[self getCGPointForCoordsWithOrientation:orientation
                                                                                      x:x
                                                                                      y:y]];
    [_captureDevice unlockForConfiguration];
    // Retrigger auto exposure
    [self applyExposureMode];
    [result sendSuccess];
}

- (void)setFocusPointWithResult:(FLTThreadSafeFlutterResult *)result x:(double)x y:(double)y {
    if (!_captureDevice.isFocusPointOfInterestSupported) {
        [result sendErrorWithCode:@"setFocusPointFailed"
                          message:@"Device does not have focus point capabilities"
                          details:nil];
        return;
    }
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    [_captureDevice lockForConfiguration:nil];
    
    [_captureDevice setFocusPointOfInterest:[self getCGPointForCoordsWithOrientation:orientation
                                                                                   x:x
                                                                                   y:y]];
    [_captureDevice unlockForConfiguration];
    // Retrigger auto focus
    [self applyFocusMode];
    [result sendSuccess];
}

- (void)setExposureOffsetWithResult:(FLTThreadSafeFlutterResult *)result offset:(double)offset {
    [_captureDevice lockForConfiguration:nil];
    [_captureDevice setExposureTargetBias:offset completionHandler:nil];
    [_captureDevice unlockForConfiguration];
    [result sendSuccessWithData:@(offset)];
}

- (void)startImageStreamWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    if (!_isStreamingImages) {
        FlutterEventChannel *eventChannel =
        [FlutterEventChannel eventChannelWithName:@"plugins.flutter.io/camera/imageStream"
                                  binaryMessenger:messenger];
        
        _imageStreamHandler = [[FLTImageStreamHandler alloc] init];
        
        if (!NSThread.isMainThread) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [eventChannel setStreamHandler:self->_imageStreamHandler];
            });
        } else {
            [eventChannel setStreamHandler:_imageStreamHandler];
        }
        
        _isStreamingImages = YES;
    } else {
        [_methodChannel invokeMethod:errorMethod
                           arguments:@"Images from camera are already streaming!"];
    }
}

- (void)stopImageStream {
    if (_isStreamingImages) {
        _isStreamingImages = NO;
        _imageStreamHandler = nil;
    } else {
        [_methodChannel invokeMethod:errorMethod arguments:@"Images from camera are not streaming!"];
    }
}

- (void)getMaxZoomLevelWithResult:(FLTThreadSafeFlutterResult *)result {
    CGFloat maxZoomFactor = [self getMaxAvailableZoomFactor];
    
    [result sendSuccessWithData:[NSNumber numberWithFloat:maxZoomFactor]];
}

- (void)getMinZoomLevelWithResult:(FLTThreadSafeFlutterResult *)result {
    CGFloat minZoomFactor = [self getMinAvailableZoomFactor];
    [result sendSuccessWithData:[NSNumber numberWithFloat:minZoomFactor]];
}

- (void)setZoomLevel:(CGFloat)zoom Result:(FLTThreadSafeFlutterResult *)result {
    CGFloat maxAvailableZoomFactor = [self getMaxAvailableZoomFactor];
    CGFloat minAvailableZoomFactor = [self getMinAvailableZoomFactor];
    
    if (maxAvailableZoomFactor < zoom || minAvailableZoomFactor > zoom) {
        NSString *errorMessage = [NSString
                                  stringWithFormat:@"Zoom level out of bounds (zoom level should be between %f and %f).",
                                  minAvailableZoomFactor, maxAvailableZoomFactor];
        
        [result sendErrorWithCode:@"ZOOM_ERROR" message:errorMessage details:nil];
        return;
    }
    
    NSError *error = nil;
    if (![_captureDevice lockForConfiguration:&error]) {
        [result sendError:error];
        return;
    }
    _captureDevice.videoZoomFactor = zoom;
    [_captureDevice unlockForConfiguration];
    
    [result sendSuccess];
}

- (CGFloat)getMinAvailableZoomFactor {
    if (@available(iOS 11.0, *)) {
        return _captureDevice.minAvailableVideoZoomFactor;
    } else {
        return 1.0;
    }
}

- (CGFloat)getMaxAvailableZoomFactor {
    if (@available(iOS 11.0, *)) {
        return _captureDevice.maxAvailableVideoZoomFactor;
    } else {
        return _captureDevice.activeFormat.videoMaxZoomFactor;
    }
}

- (BOOL)setupWriterForPath:(NSString *)path {
    NSError *error = nil;
    NSURL *outputURL;
    if (path != nil) {
        outputURL = [NSURL fileURLWithPath:path];
    } else {
        return NO;
    }
    if (_enableAudio && !_isAudioSetup) {
        [self setUpCaptureSessionForAudio];
    }
    
    _videoWriter = [[AVAssetWriter alloc] initWithURL:outputURL
                                             fileType:AVFileTypeMPEG4
                                                error:&error];
    NSParameterAssert(_videoWriter);
    if (error) {
        [_methodChannel invokeMethod:errorMethod arguments:error.description];
        return NO;
    }
    
    NSDictionary *videoSettings = [_captureVideoOutput
                                   recommendedVideoSettingsForAssetWriterWithOutputFileType:AVFileTypeMPEG4];
    _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                           outputSettings:videoSettings];
    
    _videoAdaptor = [AVAssetWriterInputPixelBufferAdaptor
                     assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput
                     sourcePixelBufferAttributes:@{
        (NSString *)kCVPixelBufferPixelFormatTypeKey : @(videoFormat)
    }];
    
    NSParameterAssert(_videoWriterInput);
    
    _videoWriterInput.expectsMediaDataInRealTime = YES;
    
    // Add the audio input
    if (_enableAudio) {
        AudioChannelLayout acl;
        bzero(&acl, sizeof(acl));
        acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
        NSDictionary *audioOutputSettings = nil;
        // Both type of audio inputs causes output video file to be corrupted.
        audioOutputSettings = @{
            AVFormatIDKey : [NSNumber numberWithInt:kAudioFormatMPEG4AAC],
            AVSampleRateKey : [NSNumber numberWithFloat:44100.0],
            AVNumberOfChannelsKey : [NSNumber numberWithInt:1],
            AVChannelLayoutKey : [NSData dataWithBytes:&acl length:sizeof(acl)],
        };
        _audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                               outputSettings:audioOutputSettings];
        _audioWriterInput.expectsMediaDataInRealTime = YES;
        
        [_videoWriter addInput:_audioWriterInput];
        [_audioOutput setSampleBufferDelegate:self queue:_dispatchQueue];
    }
    
    if (_flashMode == FlashModeTorch) {
        [self.captureDevice lockForConfiguration:nil];
        [self.captureDevice setTorchMode:AVCaptureTorchModeOn];
        [self.captureDevice unlockForConfiguration];
    }
    
    [_videoWriter addInput:_videoWriterInput];
    
    [_captureVideoOutput setSampleBufferDelegate:self queue:_dispatchQueue];
    
    return YES;
}

- (void)setUpCaptureSessionForAudio {
    NSError *error = nil;
    // Create a device input with the device and add it to the session.
    // Setup the audio input.
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice
                                                                             error:&error];
    if (error) {
        [_methodChannel invokeMethod:errorMethod arguments:error.description];
    }
    // Setup the audio output.
    _audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    
    if ([_captureSession canAddInput:audioInput]) {
        [_captureSession addInput:audioInput];
        
        if ([_captureSession canAddOutput:_audioOutput]) {
            [_captureSession addOutput:_audioOutput];
            _isAudioSetup = YES;
        } else {
            [_methodChannel invokeMethod:errorMethod
                               arguments:@"Unable to add Audio input/output to session capture"];
            _isAudioSetup = NO;
        }
    }
}
@end

@interface CameraPlugin ()
@property(readonly, nonatomic) NSObject<FlutterTextureRegistry> *registry;
@property(readonly, nonatomic) NSObject<FlutterBinaryMessenger> *messenger;
@property(readonly, nonatomic) FLTCam *camera;
@property(readonly, nonatomic) FlutterMethodChannel *deviceEventMethodChannel;
@property(readonly, nonatomic) long sessionId;
@end

@implementation CameraPlugin {
    dispatch_queue_t _dispatchQueue;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel =
    [FlutterMethodChannel methodChannelWithName:@"plugins.flutter.io/camera"
                                binaryMessenger:[registrar messenger]];
    CameraPlugin *instance = [[CameraPlugin alloc] initWithRegistry:[registrar textures]
                                                          messenger:[registrar messenger]];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistry:(NSObject<FlutterTextureRegistry> *)registry
                       messenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _registry = registry;
    _messenger = messenger;
    [self initDeviceEventMethodChannel];
    [self startOrientationListener];
    return self;
}

- (void)initDeviceEventMethodChannel {
    _deviceEventMethodChannel =
    [FlutterMethodChannel methodChannelWithName:@"flutter.io/cameraPlugin/device"
                                binaryMessenger:_messenger];
}

- (void)startOrientationListener {
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationChanged:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:[UIDevice currentDevice]];
}

- (void)orientationChanged:(NSNotification *)note {
    UIDevice *device = note.object;
    UIDeviceOrientation orientation = device.orientation;
    
    if (orientation == UIDeviceOrientationFaceUp || orientation == UIDeviceOrientationFaceDown) {
        // Do not change when oriented flat.
        return;
    }
    
    if (_camera) {
        [_camera setUiDeviceOrientation:orientation];
    }
    
    [self sendDeviceOrientation:orientation];
}

- (void)sendDeviceOrientation:(UIDeviceOrientation)orientation {
    [_deviceEventMethodChannel
     invokeMethod:@"orientation_changed"
     arguments:@{@"orientation" : getStringForUIDeviceOrientation(orientation)}];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (_dispatchQueue == nil) {
        _dispatchQueue = dispatch_queue_create("io.flutter.camera.dispatchqueue", NULL);
    }
    
    // Invoke the plugin on another dispatch queue to avoid blocking the UI.
    dispatch_async(_dispatchQueue, ^{
        FLTThreadSafeFlutterResult *threadSafeResult =
        [[FLTThreadSafeFlutterResult alloc] initWithResult:result];
        
        [self handleMethodCallAsync:call result:threadSafeResult];
    });
}

-(void) checkCameraAuthorizationWithSuccessBloc:(void(^)(void)) successBloc
                                       failBloc:(void(^)(void)) failBloc
{
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if(status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted) {
        failBloc();
    } else if (status == AVAuthorizationStatusAuthorized) {
        successBloc();
    } else {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted){
            if(granted) {
                NSObject* observer = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                                       object:nil
                                                                                        queue:NSOperationQueue.mainQueue
                                                                                   usingBlock:
                                      ^(NSNotification* notification){
                    successBloc();
                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                }];
            } else {
                failBloc();
            }
        }];
    }
}

- (void)handleMethodCallAsync:(FlutterMethodCall *)call
                       result:(FLTThreadSafeFlutterResult *)result {
    if ([@"availableCameras" isEqualToString:call.method]) {
        if (@available(iOS 10.0, *)) {
            AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
                                                                 discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera ]
                                                                 mediaType:AVMediaTypeVideo
                                                                 position:AVCaptureDevicePositionUnspecified];
            NSArray<AVCaptureDevice *> *devices = discoverySession.devices;
            NSMutableArray<NSDictionary<NSString *, NSObject *> *> *reply =
            [[NSMutableArray alloc] initWithCapacity:devices.count];
            for (AVCaptureDevice *device in devices) {
                NSString *lensFacing;
                switch ([device position]) {
                    case AVCaptureDevicePositionBack:
                        lensFacing = @"back";
                        break;
                    case AVCaptureDevicePositionFront:
                        lensFacing = @"front";
                        break;
                    case AVCaptureDevicePositionUnspecified:
                        lensFacing = @"external";
                        break;
                }
                [reply addObject:@{
                    @"name" : [device uniqueID],
                    @"lensFacing" : lensFacing,
                    @"sensorOrientation" : @90,
                }];
            }
            [result sendSuccessWithData:reply];
        } else {
            [result sendNotImplemented];
        }
    } else if ([@"create" isEqualToString:call.method]) {
        [self checkCameraAuthorizationWithSuccessBloc:
             ^{
            NSString *cameraName = call.arguments[@"cameraName"];
            NSString *resolutionPreset = call.arguments[@"resolutionPreset"];
            NSNumber *enableAudio = call.arguments[@"enableAudio"];
            NSError *error;
            NSNumber* longSideSize = call.arguments[@"longSideSize"];
            NSNumber* imageQuality = call.arguments[@"imageQuality"];
            NSString* lockedCaptureOrientationStr = call.arguments[@"lockedCaptureOrientation"];
            
            
            FLTCam *cam = [[FLTCam alloc] initWithCameraName:cameraName
                                            resolutionPreset:resolutionPreset
                                                longSideSize:[longSideSize intValue]
                                                imageQuality:[imageQuality intValue]
                                                 enableAudio:[enableAudio boolValue]
                                                 orientation:[[UIDevice currentDevice] orientation]
                                               dispatchQueue:self->_dispatchQueue
                                                       error:&error
                                    deviceEventMethodChannel:self->_deviceEventMethodChannel
                                  lockedCaptureOrientationStr:lockedCaptureOrientationStr];
            if (error) {
                [result sendError:error];
            } else {
                if (self->_camera) {
                    [self->_camera close];
                }
                int64_t textureId = [self.registry registerTexture:cam];
                self->_camera = cam;
                [result sendSuccessWithData:@{
                    @"cameraId" : @(textureId),
                }];
            }
        }
                                             failBloc:
             ^{
            [result sendError:
                 [NSError errorWithDomain:@"CameraPlugin"
                                     code:0
                                 userInfo:@{NSLocalizedDescriptionKey: @"Camera permission is not granted"}
                 ]
            ];
        }
        ];
        
        
    } else if ([@"startImageStream" isEqualToString:call.method]) {
        [_camera startImageStreamWithMessenger:_messenger];
        [result sendSuccess];
    } else if ([@"stopImageStream" isEqualToString:call.method]) {
        [_camera stopImageStream];
        [result sendSuccess];
    } else {
        NSDictionary *argsMap = call.arguments;
        NSUInteger cameraId = ((NSNumber *)argsMap[@"cameraId"]).unsignedIntegerValue;
        if ([@"initialize" isEqualToString:call.method]) {
            NSString *videoFormatValue = ((NSString *)argsMap[@"imageFormatGroup"]);
            _sessionId = [((NSNumber*)argsMap[@"sessionId"]) longValue];
            
            _camera.isBarcodeStreamEnabled = ((BOOL)argsMap[@"isBarcodeStreamEnabled"]);
            if(_camera.isBarcodeStreamEnabled) {
                _camera.barcodeStreamId = [((NSNumber*)argsMap[@"barcodeStreamId"]) longValue];
                
                _camera.barcodeCropLeft = [((NSNumber*)argsMap[@"cropLeft"]) intValue];
                if(_camera.barcodeCropLeft < 0 || _camera.barcodeCropLeft > 100) {
                    _camera.barcodeCropLeft = 0;
                }
                _camera.barcodeCropRight = [((NSNumber*)argsMap[@"cropRight"]) intValue];
                if(_camera.barcodeCropRight < 0 || _camera.barcodeCropRight > 100) {
                    _camera.barcodeCropRight = 0;
                }
                
                _camera.barcodeCropTop = [((NSNumber*)argsMap[@"cropTop"]) intValue];
                if(_camera.barcodeCropTop < 0 || _camera.barcodeCropTop > 100) {
                    _camera.barcodeCropTop = 0;
                }
                
                _camera.barcodeCropBottom = [((NSNumber*)argsMap[@"cropBottom"]) intValue];
                if(_camera.barcodeCropBottom < 0 || _camera.barcodeCropBottom > 100) {
                    _camera.barcodeCropBottom = 0;
                }
                
                if(_camera.barcodeCropLeft + _camera.barcodeCropRight >= 100) {
                    _camera.barcodeCropLeft = 0;
                    _camera.barcodeCropRight = 0;
                }
                
                if(_camera.barcodeCropTop + _camera.barcodeCropBottom >= 100) {
                    _camera.barcodeCropTop = 0;
                    _camera.barcodeCropBottom = 0;
                }
                
                _camera.barcodeEventChannel = [FlutterEventChannel
                                               eventChannelWithName:[NSString stringWithFormat:@"plugins.flutter.io/camera/barcodeStream/%lu",
                                                                     (unsigned long)_camera.barcodeStreamId]
                                               binaryMessenger:_messenger];
            }
            
            videoFormat = getVideoFormatFromString(videoFormatValue);
            
            __weak CameraPlugin *weakSelf = self;
            _camera.onFrameAvailable = ^{
                if (![weakSelf.camera isPreviewPaused]) {
                    [weakSelf.registry textureFrameAvailable:cameraId];
                }
            };
            FlutterMethodChannel *methodChannel = [FlutterMethodChannel
                                                   methodChannelWithName:[NSString stringWithFormat:@"flutter.io/cameraPlugin/camera%lu",
                                                                          (unsigned long)cameraId]
                                                   binaryMessenger:_messenger];
            _camera.methodChannel = methodChannel;
            [methodChannel
             invokeMethod:@"initialized"
             arguments:@{
                @"previewWidth" : @(_camera.previewSize.width),
                @"previewHeight" : @(_camera.previewSize.height),
                @"exposureMode" : getStringForExposureMode([_camera exposureMode]),
                @"focusMode" : getStringForFocusMode([_camera focusMode]),
                @"exposurePointSupported" :
                    @([_camera.captureDevice isExposurePointOfInterestSupported]),
                @"focusPointSupported" : @([_camera.captureDevice isFocusPointOfInterestSupported]),
            }];
            [self sendDeviceOrientation:[UIDevice currentDevice].orientation];
            [_camera start];
            [result sendSuccess];
        } else if ([@"takePicture" isEqualToString:call.method]) {
            if (@available(iOS 10.0, *)) {
                [_camera captureToFile:result];
            } else {
                [result sendNotImplemented];
            }
        } else if ([@"dispose" isEqualToString:call.method]) {
            long sessionId = [((NSNumber*)argsMap[@"sessionId"]) longValue];
            if(sessionId == _sessionId) {
                [_registry unregisterTexture:cameraId];
                [_camera close];
                _dispatchQueue = nil;
                [result sendSuccess];
            }
        } else if ([@"prepareForVideoRecording" isEqualToString:call.method]) {
            [_camera setUpCaptureSessionForAudio];
            [result sendSuccess];
        } else if ([@"startVideoRecording" isEqualToString:call.method]) {
            [_camera startVideoRecordingWithResult:result];
        } else if ([@"stopVideoRecording" isEqualToString:call.method]) {
            [_camera stopVideoRecordingWithResult:result];
        } else if ([@"pauseVideoRecording" isEqualToString:call.method]) {
            [_camera pauseVideoRecordingWithResult:result];
        } else if ([@"resumeVideoRecording" isEqualToString:call.method]) {
            [_camera resumeVideoRecordingWithResult:result];
        } else if ([@"getMaxZoomLevel" isEqualToString:call.method]) {
            [_camera getMaxZoomLevelWithResult:result];
        } else if ([@"getMinZoomLevel" isEqualToString:call.method]) {
            [_camera getMinZoomLevelWithResult:result];
        } else if ([@"setZoomLevel" isEqualToString:call.method]) {
            CGFloat zoom = ((NSNumber *)argsMap[@"zoom"]).floatValue;
            [_camera setZoomLevel:zoom Result:result];
        } else if ([@"setFlashMode" isEqualToString:call.method]) {
            [_camera setFlashModeWithResult:result mode:call.arguments[@"mode"]];
        } else if ([@"setExposureMode" isEqualToString:call.method]) {
            [_camera setExposureModeWithResult:result mode:call.arguments[@"mode"]];
        } else if ([@"setExposurePoint" isEqualToString:call.method]) {
            BOOL reset = ((NSNumber *)call.arguments[@"reset"]).boolValue;
            double x = 0.5;
            double y = 0.5;
            if (!reset) {
                x = ((NSNumber *)call.arguments[@"x"]).doubleValue;
                y = ((NSNumber *)call.arguments[@"y"]).doubleValue;
            }
            [_camera setExposurePointWithResult:result x:x y:y];
        } else if ([@"getMinExposureOffset" isEqualToString:call.method]) {
            [result sendSuccessWithData:@(_camera.captureDevice.minExposureTargetBias)];
        } else if ([@"getMaxExposureOffset" isEqualToString:call.method]) {
            [result sendSuccessWithData:@(_camera.captureDevice.maxExposureTargetBias)];
        } else if ([@"getExposureOffsetStepSize" isEqualToString:call.method]) {
            [result sendSuccessWithData:@(0.0)];
        } else if ([@"setExposureOffset" isEqualToString:call.method]) {
            [_camera setExposureOffsetWithResult:result
                                          offset:((NSNumber *)call.arguments[@"offset"]).doubleValue];
        } else if ([@"setFocusMode" isEqualToString:call.method]) {
            [_camera setFocusModeWithResult:result mode:call.arguments[@"mode"]];
        } else if ([@"setFocusPoint" isEqualToString:call.method]) {
            BOOL reset = ((NSNumber *)call.arguments[@"reset"]).boolValue;
            double x = 0.5;
            double y = 0.5;
            if (!reset) {
                x = ((NSNumber *)call.arguments[@"x"]).doubleValue;
                y = ((NSNumber *)call.arguments[@"y"]).doubleValue;
            }
            [_camera setFocusPointWithResult:result x:x y:y];
        } else if ([@"pausePreview" isEqualToString:call.method]) {
            [_camera pausePreviewWithResult:result];
        } else if ([@"resumePreview" isEqualToString:call.method]) {
            [_camera resumePreviewWithResult:result];
        } else {
            [result sendNotImplemented];
        }
    }
}

@end

@implementation BarcodeStreamHandler
- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
    _eventSink = events;
    return nil;
}
@end
