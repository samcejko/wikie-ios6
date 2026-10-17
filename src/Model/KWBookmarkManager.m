#import "KWBookmarkManager.h"
#import "KWCommon.h"

@interface KWBookmarkManager () {
    NSMutableArray *_bookmarksList;
    NSString *_filePath;
}
@end

@implementation KWBookmarkManager

+ (instancetype)sharedManager
{
    static KWBookmarkManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[KWBookmarkManager alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
        _filePath = [paths.firstObject stringByAppendingPathComponent:@"KiwixBookmarks.plist"];
        NSArray *saved = [NSArray arrayWithContentsOfFile:_filePath];
        if (saved) {
            _bookmarksList = [saved mutableCopy];
        } else {
            _bookmarksList = [NSMutableArray array];
        }
    }
    return self;
}

- (NSArray *)bookmarks
{
    return [_bookmarksList copy];
}

- (void)addBookmarkWithTitle:(NSString *)title url:(NSString *)url archiveId:(NSString *)archiveId
{
    if (!url || !archiveId) return;

    [self removeBookmarkWithUrl:url archiveId:archiveId];

    NSDictionary *item = @{
        @"title": title ? title : url,
        @"url": url,
        @"archiveId": archiveId,
        @"date": [NSDate date]
    };
    [_bookmarksList insertObject:item atIndex:0];
    [_bookmarksList writeToFile:_filePath atomically:YES];
}

- (void)removeBookmarkWithUrl:(NSString *)url archiveId:(NSString *)archiveId
{
    NSIndexSet *toRemove = [_bookmarksList indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
        return [obj[@"url"] isEqualToString:url] && [obj[@"archiveId"] isEqualToString:archiveId];
    }];
    if (toRemove.count > 0) {
        [_bookmarksList removeObjectsAtIndexes:toRemove];
        [_bookmarksList writeToFile:_filePath atomically:YES];
    }
}

- (BOOL)isBookmarkedUrl:(NSString *)url archiveId:(NSString *)archiveId
{
    for (NSDictionary *obj in _bookmarksList) {
        if ([obj[@"url"] isEqualToString:url] && [obj[@"archiveId"] isEqualToString:archiveId]) {
            return YES;
        }
    }
    return NO;
}

@end
