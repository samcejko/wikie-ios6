#import <Foundation/Foundation.h>

@interface KWWiFiUploadServer : NSObject

@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) UInt16 port;
@property (nonatomic, readonly, copy) NSString *serverURL;

+ (instancetype)sharedServer;

- (BOOL)startWithPort:(UInt16)port error:(NSError **)error;
- (void)stop;

@end
