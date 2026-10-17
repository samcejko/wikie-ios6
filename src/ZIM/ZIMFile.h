#import <Foundation/Foundation.h>
#import "ZIMTypes.h"
#import "ZIMEntry.h"

@interface ZIMFile : NSObject

@property (nonatomic, readonly, copy) NSString *filePath;
@property (nonatomic, readonly, copy) NSString *archiveId;
@property (nonatomic, readonly) uint16_t majorVersion;
@property (nonatomic, readonly) uint16_t minorVersion;
@property (nonatomic, readonly) uint32_t articleCount;
@property (nonatomic, readonly) uint32_t clusterCount;
@property (nonatomic, readonly) uint64_t fileSize;

// Metadata extracted from M/ namespace
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *archiveDescription;
@property (nonatomic, readonly, copy) NSString *language;
@property (nonatomic, readonly, copy) NSString *date;
@property (nonatomic, readonly, copy) NSString *creator;
@property (nonatomic, readonly) NSData *faviconData;

- (instancetype)initWithPath:(NSString *)filePath error:(NSError **)error;

- (ZIMEntry *)mainPageEntry;
- (ZIMEntry *)entryForPath:(NSString *)path;
- (ZIMEntry *)entryForTitle:(NSString *)title;
- (ZIMEntry *)entryAtURLIndex:(uint32_t)index;
- (ZIMEntry *)entryAtTitleIndex:(uint32_t)index;

// Fast binary search + scan for prefix suggestions
- (NSArray *)searchEntriesWithPrefix:(NSString *)prefix maxResults:(NSUInteger)maxResults;

- (NSData *)dataForEntry:(ZIMEntry *)entry error:(NSError **)error;
- (NSData *)dataForPath:(NSString *)path mimeType:(NSString **)outMime error:(NSError **)error;

- (void)close;

@end
