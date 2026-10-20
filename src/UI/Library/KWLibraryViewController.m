#import "KWLibraryViewController.h"
#import "KWReaderViewController.h"
#import "KWCatalogViewController.h"
#import "KWWiFiUploadServer.h"
#import "KWArchiveManager.h"
#import "KWCommon.h"

@interface KWLibraryViewController () {
    UILabel *_emptyStateLabel;
    UIControl *_archiveRefreshControl;
}
@end

@implementation KWLibraryViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = L(@"Library");

    // Navigation bar items
    UIBarButtonItem *wifiItem = [[UIBarButtonItem alloc] initWithTitle:L(@"WiFiUpload")
                                                                 style:UIBarButtonItemStyleBordered
                                                                target:self
                                                                action:@selector(wifiTapped:)];
    self.navigationItem.leftBarButtonItem = wifiItem;

    UIBarButtonItem *downloadItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                  target:self
                                                                                  action:@selector(catalogTapped:)];
    self.navigationItem.rightBarButtonItem = downloadItem;

    self.tableView.rowHeight = 64;

    // iOS 5 has neither UIRefreshControl nor UITableViewController.refreshControl.
    Class refreshClass = NSClassFromString(@"UIRefreshControl");
    if (refreshClass && [self respondsToSelector:@selector(setRefreshControl:)]) {
        _archiveRefreshControl = [[refreshClass alloc] init];
        [_archiveRefreshControl addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
        [self performSelector:@selector(setRefreshControl:) withObject:_archiveRefreshControl];
    } else {
        UIButton *refreshButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        refreshButton.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, 44);
        refreshButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [refreshButton setTitle:L(@"RefreshLibrary") forState:UIControlStateNormal];
        [refreshButton addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventTouchUpInside];
        self.tableView.tableHeaderView = refreshButton;
    }

    // Empty state label
    _emptyStateLabel = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    _emptyStateLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _emptyStateLabel.numberOfLines = 0;
    _emptyStateLabel.textAlignment = NSTextAlignmentCenter;
    _emptyStateLabel.textColor = [UIColor grayColor];
    _emptyStateLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:15];
    _emptyStateLabel.text = [NSString stringWithFormat:@"%@\n\n%@", L(@"NoArchivesTitle"), L(@"NoArchivesMessage")];
    _emptyStateLabel.hidden = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(libraryChanged:)
                                                 name:KWLibraryDidChangeNotification
                                               object:nil];

    [self updateEmptyState];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = YES;
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState
{
    BOOL empty = ([KWArchiveManager sharedManager].archives.count == 0);
    _emptyStateLabel.hidden = !empty;
    self.tableView.backgroundView = empty ? _emptyStateLabel : nil;
}

- (void)libraryChanged:(NSNotification *)note
{
    if ([_archiveRefreshControl respondsToSelector:@selector(endRefreshing)]) {
        [_archiveRefreshControl performSelector:@selector(endRefreshing)];
    }
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)pullToRefresh:(id)sender
{
    [[KWArchiveManager sharedManager] rescanArchives];
}

#pragma mark - Actions

- (void)wifiTapped:(id)sender
{
    KWWiFiUploadServer *server = [KWWiFiUploadServer sharedServer];
    if (!server.isRunning) {
        NSError *err = nil;
        if (![server startWithPort:8080 error:&err]) {
            [[[UIAlertView alloc] initWithTitle:L(@"Error")
                                       message:L(@"WiFiServerStartFailed")
                                      delegate:nil
                             cancelButtonTitle:L(@"OK")
                             otherButtonTitles:nil] show];
            return;
        }
    }

    NSString *msg = [NSString stringWithFormat:@"%@\n%@\n\n%@", L(@"WiFiServerRunning"), server.serverURL, L(@"WiFiServerHint")];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:L(@"WiFiUpload")
                                                    message:msg
                                                   delegate:self
                                          cancelButtonTitle:L(@"Done")
                                          otherButtonTitles:L(@"StopServer"), nil];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1) { // Stop Server
        [[KWWiFiUploadServer sharedServer] stop];
    }
}

- (void)catalogTapped:(id)sender
{
    KWCatalogViewController *catalogVC = [[KWCatalogViewController alloc] init];
    [self.navigationController pushViewController:catalogVC animated:YES];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [KWArchiveManager sharedManager].archives.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellId = @"ArchiveCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
    }

    ZIMFile *archive = [[KWArchiveManager sharedManager].archives objectAtIndex:indexPath.row];
    cell.textLabel.text = archive.title ? archive.title : archive.archiveId;
    cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:16];

    NSString *countStr = [NSString stringWithFormat:L(@"ArticlesCount"), archive.articleCount];
    NSString *sizeStr = KWFormattedFileSize(archive.fileSize);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", countStr, sizeStr];
    cell.detailTextLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:13];
    cell.backgroundColor = [UIColor whiteColor];

    if (archive.faviconData) {
        cell.imageView.image = [UIImage imageWithData:archive.faviconData];
    } else {
        cell.imageView.image = nil;
    }

    BOOL isActive = ([KWArchiveManager sharedManager].activeArchive == archive);
    cell.accessoryType = isActive ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    ZIMFile *archive = [[KWArchiveManager sharedManager].archives objectAtIndex:indexPath.row];
    [KWArchiveManager sharedManager].activeArchive = archive;
    [self.tableView reloadData];

    KWReaderViewController *readerVC = [[KWReaderViewController alloc] init];
    readerVC.currentArchive = archive;
    [readerVC loadEntry:[archive mainPageEntry] archive:archive];
    [self.navigationController pushViewController:readerVC animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        ZIMFile *archive = [[KWArchiveManager sharedManager].archives objectAtIndex:indexPath.row];
        [[KWArchiveManager sharedManager] deleteArchive:archive error:nil];
    }
}

@end
