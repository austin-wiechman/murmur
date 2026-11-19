#import <AVFAudio/AVFAudio.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Turns an Objective-C exception, which Swift can't catch, into a thrown error.
@interface ObjCExceptionCatcher : NSObject

/// Runs `block`. If it raises, returns NO with the exception's name as the error domain and its reason as the
/// description; Swift sees this as `try ObjCExceptionCatcher.catchException { ... }`.
+ (BOOL)catchException:(NS_NOESCAPE void (^)(void))block error:(NSError **)error;

/// Installs a tap, returning NO with an error where AVFAudio raises, such as a format that no longer matches the
/// device. Calling it from here keeps Swift frames out of the unwind, which would skip their releases.
+ (BOOL)installTapOnNode:(AVAudioNode *)node
                     bus:(AVAudioNodeBus)bus
              bufferSize:(AVAudioFrameCount)bufferSize
                  format:(nullable AVAudioFormat *)format
                   block:(AVAudioNodeTapBlock)block
                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
