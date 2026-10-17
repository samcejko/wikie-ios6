#import <Foundation/Foundation.h>
#import "ZIMTypes.h"

@interface ZIMCluster : NSObject

@property (nonatomic, readonly) uint32_t clusterIndex;
@property (nonatomic, readonly) ZIMCompressionType compressionType;
@property (nonatomic, readonly) BOOL isExtended;
@property (nonatomic, readonly) uint32_t blobCount;

- (instancetype)initWithClusterIndex:(uint32_t)index
                             rawData:(NSData *)rawData
                               error:(NSError **)error;

- (NSData *)blobAtIndex:(uint32_t)blobIndex;

@end
