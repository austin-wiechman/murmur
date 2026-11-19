#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)catchException:(NS_NOESCAPE void (^)(void))block error:(NSError **)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:exception.name code:0 userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: exception.name,
            }];
        }
        return NO;
    }
}

+ (BOOL)installTapOnNode:(AVAudioNode *)node
                     bus:(AVAudioNodeBus)bus
              bufferSize:(AVAudioFrameCount)bufferSize
                  format:(AVAudioFormat *)format
                   block:(AVAudioNodeTapBlock)block
                   error:(NSError **)error {
    return [self catchException:^{
        [node installTapOnBus:bus bufferSize:bufferSize format:format block:block];
    } error:error];
}

+ (BOOL)setVoiceProcessingOnEngine:(AVAudioEngine *)engine enabled:(BOOL)enabled error:(NSError **)error {
    __block BOOL succeeded = YES;
    BOOL returned = [self catchException:^{
        AVAudioInputNode *input = engine.inputNode;
        if (![input setVoiceProcessingEnabled:enabled error:error]) {
            succeeded = NO;
            return;
        }
        if (!enabled) return;
        AVAudioVoiceProcessingOtherAudioDuckingConfiguration ducking = {
            .enableAdvancedDucking = NO,
            .duckingLevel = AVAudioVoiceProcessingOtherAudioDuckingLevelMin,
        };
        input.voiceProcessingOtherAudioDuckingConfiguration = ducking;
    } error:error];
    return returned && succeeded;
}

+ (BOOL)isVoiceProcessingEnabledOnEngine:(AVAudioEngine *)engine {
    __block BOOL enabled = NO;
    [self catchException:^{
        enabled = engine.inputNode.voiceProcessingEnabled;
    } error:nil];
    return enabled;
}

@end
