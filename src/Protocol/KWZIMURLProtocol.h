#import <Foundation/Foundation.h>

@interface KWZIMURLProtocol : NSURLProtocol

+ (void)registerProtocol;
+ (NSURL *)URLForArchiveId:(NSString *)archiveId path:(NSString *)path;

@end
