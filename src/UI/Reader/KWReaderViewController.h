#import <UIKit/UIKit.h>
#import "ZIMFile.h"
#import "ZIMEntry.h"

@interface KWReaderViewController : UIViewController <UIWebViewDelegate, UIActionSheetDelegate>

@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) ZIMFile *currentArchive;
@property (nonatomic, strong) ZIMEntry *currentEntry;

- (void)loadEntry:(ZIMEntry *)entry archive:(ZIMFile *)archive;
- (void)loadURL:(NSURL *)url;

@end
