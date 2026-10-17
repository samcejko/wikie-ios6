#import <Foundation/Foundation.h>

@interface KWBookmarkManager : NSObject

@property (nonatomic, readonly) NSArray *bookmarks; // Array of NSDictionary with keys: title, url, archiveId, date

+ (instancetype)sharedManager;

- (void)addBookmarkWithTitle:(NSString *)title url:(NSString *)url archiveId:(NSString *)archiveId;
- (void)removeBookmarkWithUrl:(NSString *)url archiveId:(NSString *)archiveId;
- (BOOL)isBookmarkedUrl:(NSString *)url archiveId:(NSString *)archiveId;

@end
