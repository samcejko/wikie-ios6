#import "KWLibraryViewController.h"
#import "KWReaderViewController.h"
#import "KWCatalogViewController.h"
#import "KWWiFiUploadServer.h"
#import "KWArchiveManager.h"
#import "KWCommon.h"

@interface KWLibraryViewController () {
    UITableView *_tableView;
    UIRefreshControl *_refreshControl;
    UILabel *_emptyStateLabel;
}
@end

@implementation KWLibraryViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = L(@"Library");
    self.view.backgroundColor = [UIColor whiteColor];

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

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 64;
    [self.view addSubview:_tableView];

    // iOS 6 UIRefreshControl!
    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
    [_tableView addSubview:_refreshControl];

    // Empty state label
    _emptyStateLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 30, 80)];
    _emptyStateLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _emptyStateLabel.numberOfLines = 0;
    _emptyStateLabel.textAlignment = NSTextAlignmentCenter;
    _emptyStateLabel.textColor = [UIColor grayColor];
    _emptyStateLabel.font = [UIFont systemFontOfSize:15];
    _emptyStateLabel.text = [NSString stringWithFormat:@"%@\n\n%@", L(@"NoArchivesTitle"), L(@"NoArchivesMessage")];
    _emptyStateLabel.hidden = YES;
    [self.view addSubview:_emptyStateLabel];

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
    [_tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState
{
    BOOL empty = ([KWArchiveManager sharedManager].archives.count == 0);
    _emptyStateLabel.hidden = !empty;
    _tableView.backgroundView = empty ? _emptyStateLabel : nil;
}

- (void)libraryChanged:(NSNotification *)note
{
    [_refreshControl endRefreshing];
    [_tableView reloadData];
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
        [server startWithPort:8080 error:&err];
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

    ZIMFile *archive = [KWArchiveManager sharedManager].archives[indexPath.row];
    cell.textLabel.text = archive.title ? archive.title : archive.archiveId;
    cell.textLabel.font = [UIFont boldSystemFontOfSize:16];

    NSString *countStr = [NSString stringWithFormat:L(@"ArticlesCount"), archive.articleCount];
    NSString *sizeStr = KWFormattedFileSize(archive.fileSize);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", countStr, sizeStr];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];

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

    ZIMFile *archive = [KWArchiveManager sharedManager].archives[indexPath.row];
    [KWArchiveManager sharedManager].activeArchive = archive;
    [_tableView reloadData];

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
        ZIMFile *archive = [KWArchiveManager sharedManager].archives[indexPath.row];
        [[KWArchiveManager sharedManager] deleteArchive:archive error:nil];
    }
}

@end
