#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Turns an Objective-C exception, which Swift can't catch, into a thrown error.
@interface ObjCExceptionCatcher : NSObject

/// Runs `block`. If it raises, returns NO with the exception's name as the error domain and its reason as the
/// description; Swift sees this as `try ObjCExceptionCatcher.catchException { ... }`.
+ (BOOL)catchException:(NS_NOESCAPE void (^)(void))block error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
