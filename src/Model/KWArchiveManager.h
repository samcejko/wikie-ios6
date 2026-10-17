#import <Foundation/Foundation.h>
#import "ZIMFile.h"

@interface KWArchiveManager : NSObject

@property (nonatomic, readonly) NSArray *archives; // Array of ZIMFile
@property (nonatomic, strong) ZIMFile *activeArchive;

+ (instancetype)sharedManager;

- (void)rescanArchives;
- (ZIMFile *)archiveForId:(NSString *)archiveId;
- (BOOL)deleteArchive:(ZIMFile *)file error:(NSError **)error;

@end
