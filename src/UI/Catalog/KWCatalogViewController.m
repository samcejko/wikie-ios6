#import "KWCatalogViewController.h"
#import "KWArchiveManager.h"
#import "KWCommon.h"

@interface KWCatalogViewController () {
    UITableView *_tableView;
    NSArray *_featuredArchives;
    NSURLConnection *_activeConnection;
    NSFileHandle *_fileHandle;
    NSString *_downloadTempPath;
    NSString *_downloadDestPath;
    long long _totalBytes;
    long long _receivedBytes;
    UIProgressView *_progressView;
    UILabel *_statusLabel;
    UIView *_progressHeader;
}
@end

@implementation KWCatalogViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = L(@"Downloads");
    self.view.backgroundColor = [UIColor whiteColor];

    UIBarButtonItem *customUrlItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                    target:self
                                                                                    action:@selector(customURLTapped:)];
    self.navigationItem.rightBarButtonItem = customUrlItem;

    // Featured offline ZIMs (small, suitable for mobile / iOS 6 storage)
    _featuredArchives = @[
        @{
            @"name": @"Wikipedia (Simple English)",
            @"lang": @"en",
            @"size": @"~250 MB",
            @"url": @"http://download.kiwix.org/zim/wikipedia/wikipedia_en_simple_all_nopic_2024-01.zim"
        },
        @{
            @"name": @"Wikipedie (Čeština mini)",
            @"lang": @"cs",
            @"size": @"~350 MB",
            @"url": @"http://download.kiwix.org/zim/wikipedia/wikipedia_cs_all_mini_2024-01.zim"
        },
        @{
            @"name": @"Wikivoyage (Travel Guide)",
            @"lang": @"en",
            @"size": @"~150 MB",
            @"url": @"http://download.kiwix.org/zim/wikivoyage/wikivoyage_en_all_nopic_2024-01.zim"
        },
        @{
            @"name": @"Wiktionary (Slovník)",
            @"lang": @"cs/en",
            @"size": @"~80 MB",
            @"url": @"http://download.kiwix.org/zim/wiktionary/wiktionary_cs_all_nopic_2024-01.zim"
        }
    ];

    // Download progress header
    _progressHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 70)];
    _progressHeader.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    _progressHeader.hidden = YES;

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, self.view.bounds.size.width - 32, 20)];
    _statusLabel.font = [UIFont systemFontOfSize:14];
    _statusLabel.text = L(@"Downloading");
    _statusLabel.backgroundColor = [UIColor clearColor];
    [_progressHeader addSubview:_statusLabel];

    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressView.frame = CGRectMake(16, 36, self.view.bounds.size.width - 32, 9);
    [_progressHeader addSubview:_progressView];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.tableHeaderView = _progressHeader;
    [self.view addSubview:_tableView];
}

- (void)customURLTapped:(id)sender
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Download ZIM by URL"
                                                    message:@"Enter direct HTTP/HTTPS link to a .zim file:"
                                                   delegate:self
                                          cancelButtonTitle:L(@"Cancel")
                                          otherButtonTitles:L(@"Download"), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alert textFieldAtIndex:0].placeholder = @"http://...";
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1) {
        NSString *urlText = [alertView textFieldAtIndex:0].text;
        if (urlText.length > 0) {
            [self startDownloadURL:[NSURL URLWithString:urlText] fileName:[urlText lastPathComponent]];
        }
    }
}

- (void)startDownloadURL:(NSURL *)url fileName:(NSString *)fileName
{
    if (_activeConnection) {
        UIAlertView *busyAlert = [[UIAlertView alloc] initWithTitle:L(@"Error")
                                                            message:@"A download is already in progress"
                                                           delegate:nil
                                                  cancelButtonTitle:L(@"OK")
                                                  otherButtonTitles:nil];
        [busyAlert show];
        return;
    }

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docsDir = paths.firstObject;

    if (![fileName hasSuffix:@".zim"]) {
        fileName = [fileName stringByAppendingPathExtension:@"zim"];
    }

    _downloadDestPath = [docsDir stringByAppendingPathComponent:fileName];
    _downloadTempPath = [_downloadDestPath stringByAppendingPathExtension:@"tmp"];

    [[NSFileManager defaultManager] removeItemAtPath:_downloadTempPath error:nil];
    [[NSFileManager defaultManager] createFileAtPath:_downloadTempPath contents:nil attributes:nil];
    _fileHandle = [NSFileHandle fileHandleForWritingAtPath:_downloadTempPath];

    _receivedBytes = 0;
    _totalBytes = 0;
    _progressView.progress = 0.0;
    _statusLabel.text = [NSString stringWithFormat:@"Downloading %@...", fileName];
    _progressHeader.hidden = NO;

    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60.0];
    _activeConnection = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    _totalBytes = response.expectedContentLength;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [_fileHandle writeData:data];
    _receivedBytes += data.length;

    if (_totalBytes > 0) {
        float progress = (float)_receivedBytes / (float)_totalBytes;
        _progressView.progress = progress;
        _statusLabel.text = [NSString stringWithFormat:@"%@ / %@", KWFormattedFileSize(_receivedBytes), KWFormattedFileSize(_totalBytes)];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [_fileHandle closeFile];
    _fileHandle = nil;
    _activeConnection = nil;

    [[NSFileManager defaultManager] moveItemAtPath:_downloadTempPath toPath:_downloadDestPath error:nil];
    [[KWArchiveManager sharedManager] rescanArchives];

    _progressHeader.hidden = YES;
    UIAlertView *doneAlert = [[UIAlertView alloc] initWithTitle:L(@"Done")
                                                        message:@"ZIM archive downloaded successfully!"
                                                       delegate:nil
                                              cancelButtonTitle:L(@"OK")
                                              otherButtonTitles:nil];
    [doneAlert show];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [_fileHandle closeFile];
    _fileHandle = nil;
    _activeConnection = nil;

    [[NSFileManager defaultManager] removeItemAtPath:_downloadTempPath error:nil];
    _progressHeader.hidden = YES;

    UIAlertView *errAlert = [[UIAlertView alloc] initWithTitle:L(@"Error")
                                                       message:error.localizedDescription
                                                      delegate:nil
                                             cancelButtonTitle:L(@"OK")
                                             otherButtonTitles:nil];
    [errAlert show];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"Featured Archives (Mobile Friendly)";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _featuredArchives.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellId = @"CatalogCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellId];
    }

    NSDictionary *item = _featuredArchives[indexPath.row];
    cell.textLabel.text = item[@"name"];
    cell.detailTextLabel.text = item[@"size"];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *item = _featuredArchives[indexPath.row];
    NSURL *url = [NSURL URLWithString:item[@"url"]];
    [self startDownloadURL:url fileName:[url lastPathComponent]];
}

@end
