#import <Foundation/Foundation.h>
#import "ZIMTypes.h"

@interface ZIMEntry : NSObject

@property (nonatomic, assign) uint32_t entryIndex;
@property (nonatomic, assign) uint16_t mimeTypeIndex;
@property (nonatomic, assign) BOOL isRedirect;
@property (nonatomic, assign) char namespaceChar;
@property (nonatomic, assign) uint32_t revision;
@property (nonatomic, assign) uint32_t clusterNumber;
@property (nonatomic, assign) uint32_t blobNumber;
@property (nonatomic, assign) uint32_t redirectIndex;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *mimeType;

- (NSString *)fullPath;

@end
