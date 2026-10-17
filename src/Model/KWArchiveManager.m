#import "KWArchiveManager.h"
#import "KWCommon.h"

@interface KWArchiveManager () {
    NSMutableArray *_archives;
}
@end

@implementation KWArchiveManager

+ (instancetype)sharedManager
{
    static KWArchiveManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[KWArchiveManager alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _archives = [NSMutableArray array];
        [self rescanArchives];
    }
    return self;
}

- (NSArray *)archives
{
    @synchronized(self) {
        return [_archives copy];
    }
}

- (void)rescanArchives
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *foundPaths = [NSMutableArray array];

    // 1. App Documents directory
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docsDir = paths.firstObject;
    if (docsDir) {
        NSArray *items = [fm contentsOfDirectoryAtPath:docsDir error:nil];
        for (NSString *item in items) {
            if ([[[item pathExtension] lowercaseString] isEqualToString:@"zim"]) {
                [foundPaths addObject:[docsDir stringByAppendingPathComponent:item]];
            }
        }
    }

    // 2. /var/mobile/Documents (jailbreak common folder)
    NSString *jailbreakDocs = @"/var/mobile/Documents";
    if ([fm fileExistsAtPath:jailbreakDocs]) {
        NSArray *items = [fm contentsOfDirectoryAtPath:jailbreakDocs error:nil];
        for (NSString *item in items) {
            if ([[[item pathExtension] lowercaseString] isEqualToString:@"zim"]) {
                NSString *full = [jailbreakDocs stringByAppendingPathComponent:item];
                if (![foundPaths containsObject:full]) {
                    [foundPaths addObject:full];
                }
            }
        }
    }

    // Close removed archives
    NSMutableArray *newArchives = [NSMutableArray arrayWithCapacity:foundPaths.count];
    for (NSString *filePath in foundPaths) {
        // Check if already open
        ZIMFile *existing = nil;
        for (ZIMFile *f in _archives) {
            if ([f.filePath isEqualToString:filePath]) {
                existing = f;
                break;
            }
        }

        if (existing) {
            [newArchives addObject:existing];
        } else {
            NSError *error = nil;
            ZIMFile *newFile = [[ZIMFile alloc] initWithPath:filePath error:&error];
            if (newFile) {
                [newArchives addObject:newFile];
            } else {
                KWLog(@"Failed to open ZIM archive at %@: %@", filePath, error.localizedDescription);
            }
        }
    }

    @synchronized(self) {
        _archives = newArchives;

        // Maintain or set active archive
        if (_archives.count > 0) {
            if (!_activeArchive || ![_archives containsObject:_activeArchive]) {
                _activeArchive = _archives[0];
            }
        } else {
            _activeArchive = nil;
        }
    }

    KWMain(^{
        [[NSNotificationCenter defaultCenter] postNotificationName:KWLibraryDidChangeNotification object:self];
    });
}

- (void)setActiveArchive:(ZIMFile *)activeArchive
{
    if (_activeArchive != activeArchive) {
        _activeArchive = activeArchive;
        KWMain(^{
            [[NSNotificationCenter defaultCenter] postNotificationName:KWActiveArchiveDidChangeNotification object:self];
        });
    }
}

- (ZIMFile *)archiveForId:(NSString *)archiveId
{
    for (ZIMFile *f in _archives) {
        if ([f.archiveId isEqualToString:archiveId]) {
            return f;
        }
    }
    return nil;
}

- (BOOL)deleteArchive:(ZIMFile *)file error:(NSError **)error
{
    if (!file) return NO;

    NSString *path = file.filePath;
    [file close];
    [_archives removeObject:file];

    if (_activeArchive == file) {
        self.activeArchive = _archives.count > 0 ? _archives[0] : nil;
    }

    BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:path error:error];
    KWMain(^{
        [[NSNotificationCenter defaultCenter] postNotificationName:KWLibraryDidChangeNotification object:self];
    });
    return removed;
}

@end
