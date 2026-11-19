#import <AVFAudio/AVFAudio.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Turns an Objective-C exception, which Swift can't catch, into a thrown error.
@interface ObjCExceptionCatcher : NSObject

/// Runs `block`. If it raises, returns NO with the exception's name as the error domain and its reason as the
/// description. A raise that unwinds through Swift frames skips their releases, so wrap AVFAudio calls here instead.
+ (BOOL)catchException:(NS_NOESCAPE void (^)(void))block error:(NSError **)error;

/// Installs a tap, returning NO with an error where AVFAudio raises, such as a format that no longer matches the
/// device. Calling it from here keeps Swift frames out of the unwind, which would skip their releases.
+ (BOOL)installTapOnNode:(AVAudioNode *)node
                     bus:(AVAudioNodeBus)bus
              bufferSize:(AVAudioFrameCount)bufferSize
                  format:(nullable AVAudioFormat *)format
                   block:(AVAudioNodeTapBlock)block
                   error:(NSError **)error;

/// Turns voice processing on or off on the engine's input node and, when turning it on, keeps ducking of other audio
/// to the minimum. Returns NO with an error where AVFAudio throws or raises, with no Swift frames in the unwind.
+ (BOOL)setVoiceProcessingOnEngine:(AVAudioEngine *)engine enabled:(BOOL)enabled error:(NSError **)error
    NS_SWIFT_NAME(setVoiceProcessing(on:enabled:));

/// Whether the engine's input node has voice processing on; NO where AVFAudio raises.
+ (BOOL)isVoiceProcessingEnabledOnEngine:(AVAudioEngine *)engine NS_SWIFT_NAME(isVoiceProcessingEnabled(on:));

@end

NS_ASSUME_NONNULL_END
