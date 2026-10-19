#import "KWSearchViewController.h"
#import "KWReaderViewController.h"
#import "KWArchiveManager.h"
#import "KWCommon.h"

@interface KWSearchViewController () {
    UISearchBar *_searchBar;
    UITableView *_tableView;
    NSArray *_searchResults;
    dispatch_queue_t _searchQueue;
}
@end

@implementation KWSearchViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = L(@"Search");
    self.view.backgroundColor = [UIColor whiteColor];

    _searchQueue = dispatch_queue_create("com.samcejko.kiwix.search", DISPATCH_QUEUE_SERIAL);
    _searchResults = @[];

    if (!_archive) {
        _archive = [KWArchiveManager sharedManager].activeArchive;
    }

    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    _searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _searchBar.placeholder = L(@"SearchPlaceholder");
    _searchBar.delegate = self;
    _searchBar.tintColor = [UIColor colorWithRed:0.25 green:0.35 blue:0.48 alpha:1.0];
    [self.view addSubview:_searchBar];

    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 44, self.view.bounds.size.width, self.view.bounds.size.height - 44) style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:_tableView];

    [_searchBar becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [_searchBar resignFirstResponder];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    if (searchText.length == 0) {
        _searchResults = @[];
        [_tableView reloadData];
        return;
    }

    NSString *query = [searchText copy];
    dispatch_async(_searchQueue, ^{
        NSArray *results = [self.archive searchEntriesWithPrefix:query maxResults:60];
        KWMain(^{
            // Ensure search text hasn't changed
            if ([_searchBar.text isEqualToString:query]) {
                _searchResults = results;
                [_tableView reloadData];
            }
        });
    });
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _searchResults.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellId = @"SearchCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.backgroundColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:16];
    cell.detailTextLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:12];

    ZIMEntry *entry = _searchResults[indexPath.row];
    cell.textLabel.text = entry.title;
    cell.detailTextLabel.text = [entry fullPath];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    ZIMEntry *entry = _searchResults[indexPath.row];
    if (self.readerVC) {
        [self.readerVC loadEntry:entry archive:self.archive];
        [self.navigationController popViewControllerAnimated:YES];
    }
}

@end
