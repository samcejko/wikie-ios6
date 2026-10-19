#import <Foundation/Foundation.h>
#import "ZIMFile.h"
#import "KWZIMURLProtocol.h"
#import "KWArchiveManager.h"

// URL construction is tested without an application or archive-library scan.
@implementation KWArchiveManager
+ (instancetype)sharedManager { return nil; }
- (ZIMFile *)archiveForId:(NSString *)archiveId { return nil; }
@end

static void check(BOOL ok, NSString *message) {
    if (!ok) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        check(argc == 2, @"fixture directory argument");
        NSString *dir = [NSString stringWithUTF8String:argv[1]];
        for (NSString *name in @[@"legacy.zim", @"modern.zim"]) {
            NSError *error = nil;
            ZIMFile *zim = [[ZIMFile alloc] initWithPath:[dir stringByAppendingPathComponent:name] error:&error];
            check(zim != nil, [NSString stringWithFormat:@"open %@: %@", name, error]);
            check([[zim mainPageEntry].title isEqualToString:@"Москва"], @"Cyrillic main page");
            for (NSString *title in @[@"Zebra", @"apple", @"Москва", @"中文", @"Článek #1?"]) {
                ZIMEntry *entry = [zim entryForTitle:title];
                check(entry != nil, [@"title lookup: " stringByAppendingString:title]);
                check([zim dataForEntry:entry error:&error].length > 0, @"article data");
                check([zim searchEntriesWithPrefix:title maxResults:10].count == 1, @"prefix lookup");
            }
            check([zim searchEntriesWithPrefix:@"моск" maxResults:10].count == 1, @"lowercase Cyrillic prefix");
            check([zim searchEntriesWithPrefix:@" " maxResults:10].count == 0, @"blank search");
            check([zim entryForPath:@"dir/Článek #1?"] != nil, @"nested raw path");
            check([zim entryForPath:@"中文"] != nil, @"namespace fallback");
        }
        NSURL *url = [KWZIMURLProtocol URLForArchiveId:@"test" path:@"C/dir/Článek #1?"];
        check(url != nil && url.query == nil && url.fragment == nil, @"escaped URL");
        check([url.path isEqualToString:@"/C/dir/Článek #1?"], @"URL path roundtrip");
        NSLog(@"PASS: legacy/modern ZIM, title order, Russian/Chinese/Czech, URL escaping");
    }
    return 0;
}
