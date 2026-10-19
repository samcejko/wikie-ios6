#import "KWAppDelegate.h"
#import "KWClassicAppearance.h"
#import "KWLibraryViewController.h"
#import "KWReaderViewController.h"
#import "KWArchiveManager.h"
#import "KWZIMURLProtocol.h"
#import "KWWiFiUploadServer.h"
#import "KWCommon.h"

@interface KWAppDelegate ()
@property (nonatomic, copy) NSString *pendingArchivePath;
@end

@implementation KWAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    signal(SIGPIPE, SIG_IGN);

    // Register custom zim:// protocol for UIWebView
    [KWZIMURLProtocol registerProtocol];

    // Modern iOS restyles UIKit's legacy controls; reapply the app's iOS 6 chrome.
    [KWClassicAppearance apply];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];

    KWLibraryViewController *libraryVC = [[KWLibraryViewController alloc] init];
    self.navigationController = [[UINavigationController alloc] initWithRootViewController:libraryVC];

    NSString *systemVersion = [UIDevice currentDevice].systemVersion;
    BOOL modernSystem = [systemVersion compare:@"7.0" options:NSNumericSearch] != NSOrderedAscending;
    UIColor *barTint = modernSystem ? [UIColor whiteColor] : [UIColor colorWithRed:0.25 green:0.35 blue:0.48 alpha:1.0];
    self.navigationController.navigationBar.tintColor = barTint;
    self.navigationController.toolbar.tintColor = barTint;
    if (@available(iOS 7.0, *)) {
        self.navigationController.navigationBar.translucent = NO;
        self.navigationController.toolbar.translucent = NO;
    }

    self.window.rootViewController = self.navigationController;
    [self.window makeKeyAndVisible];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryDidChange:) name:KWLibraryDidChangeNotification object:nil];

    // Asynchronously scan for archives in background so launch is instant
    [[KWArchiveManager sharedManager] rescanArchives];

    // Handle initial launch URL if any
    NSURL *launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
    if (launchURL) {
        [self handleOpenURL:launchURL];
    }

    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    return [self handleOpenURL:url];
}

- (BOOL)handleOpenURL:(NSURL *)url
{
    if (!url) return NO;

    if ([url isFileURL]) {
        NSString *path = [url path];
        if ([[[path pathExtension] lowercaseString] isEqualToString:@"zim"]) {
            // Move from Inbox to Documents
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *docsDir = [paths count] > 0 ? [paths objectAtIndex:0] : nil;
            NSString *destPath = [docsDir stringByAppendingPathComponent:[path lastPathComponent]];

            if (!docsDir.length) return NO;
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![[path stringByStandardizingPath] isEqualToString:[destPath stringByStandardizingPath]]) {
                NSString *base = [[path lastPathComponent] stringByDeletingPathExtension];
                NSUInteger suffix = 1;
                while ([fm fileExistsAtPath:destPath]) {
                    destPath = [docsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%lu.zim", base, (unsigned long)suffix++]];
                }
                NSError *error = nil;
                if (![fm moveItemAtPath:path toPath:destPath error:&error]) {
                    [[[UIAlertView alloc] initWithTitle:L(@"ImportFailed") message:error.localizedDescription delegate:nil cancelButtonTitle:L(@"OK") otherButtonTitles:nil] show];
                    return NO;
                }
            }
            self.pendingArchivePath = destPath;
            [[KWArchiveManager sharedManager] rescanArchives];

            return YES;
        }
    }
    return NO;
}

- (void)libraryDidChange:(NSNotification *)notification
{
    if (!self.pendingArchivePath) return;
    for (ZIMFile *opened in [KWArchiveManager sharedManager].archives) {
        if (![opened.filePath isEqualToString:self.pendingArchivePath]) continue;
        self.pendingArchivePath = nil;
        [KWArchiveManager sharedManager].activeArchive = opened;
        KWReaderViewController *reader = [[KWReaderViewController alloc] init];
        [reader loadEntry:[opened mainPageEntry] archive:opened];
        [self.navigationController pushViewController:reader animated:YES];
        break;
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [[KWArchiveManager sharedManager] rescanArchives];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [[KWWiFiUploadServer sharedServer] stop];
}

@end
