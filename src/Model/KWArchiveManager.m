#import "KWArchiveManager.h"
#import "KWCommon.h"

@interface KWArchiveManager () {
    NSMutableArray *_archives;
    BOOL _isScanning;
}
@end

@implementation KWArchiveManager

@synthesize activeArchive = _activeArchive;

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
        _isScanning = NO;
    }
    return self;
}

- (NSArray *)archives
{
    @synchronized(self) {
        return [_archives copy];
    }
}

- (ZIMFile *)activeArchive
{
    @synchronized(self) {
        return _activeArchive;
    }
}

- (void)setActiveArchive:(ZIMFile *)activeArchive
{
    @synchronized(self) {
        if (_activeArchive != activeArchive) {
            _activeArchive = activeArchive;
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:KWActiveArchiveDidChangeNotification object:self];
    });
}

- (ZIMFile *)archiveForId:(NSString *)archiveId
{
    if (!archiveId) return nil;
    @synchronized(self) {
        for (ZIMFile *f in _archives) {
            if ([f.archiveId isEqualToString:archiveId]) {
                return f;
            }
        }
    }
    return nil;
}

- (void)rescanArchives
{
    @synchronized(self) {
        if (_isScanning) return;
        _isScanning = YES;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *foundPaths = [NSMutableArray array];

        // 1. App Documents directory
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docsDir = [paths count] > 0 ? [paths objectAtIndex:0] : nil;
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

        // Close removed archives and open new ones
        NSMutableArray *newArchives = [NSMutableArray arrayWithCapacity:foundPaths.count];
        NSArray *oldArchives = nil;
        @synchronized(self) {
            oldArchives = [_archives copy];
        }

        for (NSString *filePath in foundPaths) {
            // Check if already open
            ZIMFile *existing = nil;
            for (ZIMFile *f in oldArchives) {
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

        // Close removed archives
        for (ZIMFile *f in oldArchives) {
            if (![newArchives containsObject:f]) {
                [f close];
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
            _isScanning = NO;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:KWLibraryDidChangeNotification object:self];
        });
    });
}

- (BOOL)deleteArchive:(ZIMFile *)file error:(NSError **)error
{
    if (!file) return NO;

    NSString *path = file.filePath;
    [file close];

    @synchronized(self) {
        [_archives removeObject:file];
        if (_activeArchive == file) {
            _activeArchive = _archives.count > 0 ? _archives[0] : nil;
        }
    }

    BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:path error:error];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:KWLibraryDidChangeNotification object:self];
    });
    return removed;
}

@end
