#import <UIKit/UIKit.h>
#import "ZIMFile.h"

@class KWReaderViewController;

@interface KWSearchViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>

@property (nonatomic, weak) KWReaderViewController *readerVC;
@property (nonatomic, strong) ZIMFile *archive;

@end
