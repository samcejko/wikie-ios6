#import "KWAppDelegate.h"
#import "KWLibraryViewController.h"
#import "KWReaderViewController.h"
#import "KWArchiveManager.h"
#import "KWZIMURLProtocol.h"
#import "KWWiFiUploadServer.h"
#import "KWCommon.h"

@implementation KWAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Register custom zim:// protocol for UIWebView
    [KWZIMURLProtocol registerProtocol];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    KWLibraryViewController *libraryVC = [[KWLibraryViewController alloc] init];
    self.navigationController = [[UINavigationController alloc] initWithRootViewController:libraryVC];

    // Classic iOS 6 navigation bar tint
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.25 green:0.35 blue:0.48 alpha:1.0];
    self.navigationController.toolbar.tintColor = [UIColor colorWithRed:0.25 green:0.35 blue:0.48 alpha:1.0];

    self.window.rootViewController = self.navigationController;
    [self.window makeKeyAndVisible];

    // If archives already exist, auto-push reader with active archive
    ZIMFile *active = [KWArchiveManager sharedManager].activeArchive;
    if (active) {
        KWReaderViewController *readerVC = [[KWReaderViewController alloc] init];
        readerVC.currentArchive = active;
        [readerVC loadEntry:[active mainPageEntry] archive:active];
        [self.navigationController pushViewController:readerVC animated:NO];
    }

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

            [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
            [[NSFileManager defaultManager] moveItemAtPath:path toPath:destPath error:nil];

            [[KWArchiveManager sharedManager] rescanArchives];

            ZIMFile *opened = [[KWArchiveManager sharedManager] archiveForId:[[destPath lastPathComponent] stringByDeletingPathExtension]];
            if (opened) {
                [KWArchiveManager sharedManager].activeArchive = opened;
                KWReaderViewController *readerVC = [[KWReaderViewController alloc] init];
                readerVC.currentArchive = opened;
                [readerVC loadEntry:[opened mainPageEntry] archive:opened];
                [self.navigationController pushViewController:readerVC animated:YES];
            }
            return YES;
        }
    }
    return NO;
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
