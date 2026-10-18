// Shared macros, helpers, and constants for Kiwix iOS 6.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma clang diagnostic error "-Wunguarded-availability"

#define L(key) NSLocalizedString((key), nil)
#define KWIsPad() (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#define KWLog(fmt, ...) NSLog((@"[Wikie] " fmt), ##__VA_ARGS__)

static inline void KWMain(dispatch_block_t block)
{
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

// Notifications
extern NSString * const KWLibraryDidChangeNotification;
extern NSString * const KWActiveArchiveDidChangeNotification;
extern NSString * const KWThemeDidChangeNotification;
extern NSString * const KWFontSizeDidChangeNotification;

// Error Domain & Codes
extern NSString * const KWErrorDomain;

enum {
    KWErrorInvalidMagic       = -1001,
    KWErrorUnsupportedVersion = -1002,
    KWErrorCorruptHeader      = -1003,
    KWErrorEntryNotFound      = -1004,
    KWErrorDecompression      = -1005,
    KWErrorIO                 = -1006,
    KWErrorRedirectLoop       = -1007,
    KWErrorNetwork            = -1008
};

NSError *KWMakeError(NSInteger code, NSString *description);
NSString *KWFormattedFileSize(uint64_t bytes);

@interface NSArray (KWCompatibility)
- (id)firstObject;
@end
