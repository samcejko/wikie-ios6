#import "KWCommon.h"

NSString * const KWLibraryDidChangeNotification = @"KWLibraryDidChangeNotification";
NSString * const KWActiveArchiveDidChangeNotification = @"KWActiveArchiveDidChangeNotification";
NSString * const KWThemeDidChangeNotification = @"KWThemeDidChangeNotification";
NSString * const KWFontSizeDidChangeNotification = @"KWFontSizeDidChangeNotification";

NSString * const KWErrorDomain = @"com.samcejko.wikie";

NSError *KWMakeError(NSInteger code, NSString *description)
{
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: description ? description : @"Unknown error"
    };
    return [NSError errorWithDomain:KWErrorDomain code:code userInfo:userInfo];
}

NSString *KWFormattedFileSize(uint64_t bytes)
{
    if (bytes >= 1024ULL * 1024ULL * 1024ULL) {
        double gb = (double)bytes / (1024.0 * 1024.0 * 1024.0);
        return [NSString stringWithFormat:L(@"SizeFormatGB"), gb];
    } else {
        double mb = (double)bytes / (1024.0 * 1024.0);
        return [NSString stringWithFormat:L(@"SizeFormat"), mb];
    }
}

@implementation NSArray (KWCompatibility)
- (id)firstObject
{
    return [self count] > 0 ? [self objectAtIndex:0] : nil;
}
@end
