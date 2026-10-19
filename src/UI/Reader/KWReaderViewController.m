#import "KWReaderViewController.h"
#import "KWSearchViewController.h"
#import "KWBookmarkManager.h"
#import "KWArchiveManager.h"
#import "KWZIMURLProtocol.h"
#import "KWCommon.h"

@interface KWReaderViewController () {
    UIBarButtonItem *_backItem;
    UIBarButtonItem *_forwardItem;
    UIBarButtonItem *_bookmarkItem;
    UIBarButtonItem *_themeItem;
    NSInteger _currentThemeIndex; // 0 = Light, 1 = Sepia, 2 = Dark
    NSInteger _fontSizePercent;   // 100% default
}
@end

@implementation KWReaderViewController

- (UIImage *)navigationArrowForward:(BOOL)forward
{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22, 22), NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat edge = forward ? 7 : 15, tip = forward ? 15 : 7;
    [path moveToPoint:CGPointMake(edge, 4)];
    [path addLineToPoint:CGPointMake(tip, 11)];
    [path addLineToPoint:CGPointMake(edge, 18)];
    path.lineWidth = 2;
    path.lineCapStyle = kCGLineCapRound;
    path.lineJoinStyle = kCGLineJoinRound;
    [[UIColor blackColor] setStroke];
    [path stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = L(@"Library");
    _fontSizePercent = 100;
    _currentThemeIndex = 0;

    self.view.backgroundColor = [UIColor whiteColor];

    // Create UIWebView
    self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.delegate = self;
    self.webView.scalesPageToFit = YES;
    [self.view addSubview:self.webView];

    // Navigation Bar items
    UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch
                                                                                target:self
                                                                                action:@selector(searchTapped:)];
    self.navigationItem.rightBarButtonItem = searchItem;

    // Bottom Toolbar items
    _backItem = [[UIBarButtonItem alloc] initWithImage:[self navigationArrowForward:NO] style:UIBarButtonItemStylePlain target:self action:@selector(goBackTapped:)];
    _backItem.accessibilityLabel = L(@"Back");
    _backItem.enabled = NO;

    _forwardItem = [[UIBarButtonItem alloc] initWithImage:[self navigationArrowForward:YES] style:UIBarButtonItemStylePlain target:self action:@selector(goForwardTapped:)];
    _forwardItem.accessibilityLabel = L(@"Forward");
    _forwardItem.enabled = NO;

    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

    _bookmarkItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemBookmarks target:self action:@selector(bookmarkTapped:)];
    _themeItem = [[UIBarButtonItem alloc] initWithTitle:@"Aa" style:UIBarButtonItemStyleBordered target:self action:@selector(themeTapped:)];

    self.toolbarItems = @[_backItem, flex, _forwardItem, flex, _bookmarkItem, flex, _themeItem];
    self.navigationController.toolbarHidden = NO;

    // Load initial entry if active and not already loaded
    if (_currentEntry && _currentArchive) {
        [self loadEntry:_currentEntry archive:_currentArchive];
    } else {
        if (!_currentArchive) {
            _currentArchive = [KWArchiveManager sharedManager].activeArchive;
        }
        if (_currentArchive) {
            ZIMEntry *mainPage = [_currentArchive mainPageEntry];
            if (mainPage) {
                [self loadEntry:mainPage archive:_currentArchive];
            }
        }
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = NO;
    [self updateToolbarButtons];
}

- (void)loadEntry:(ZIMEntry *)entry archive:(ZIMFile *)archive
{
    _currentEntry = entry;
    _currentArchive = archive;

    if (!entry || !archive) return;
    // The library assigns the entry before pushing this controller. Defer
    // the request until viewDidLoad has created the web view.
    if (![self isViewLoaded]) return;

    NSURL *url = [KWZIMURLProtocol URLForArchiveId:archive.archiveId path:[entry fullPath]];
    [self loadURL:url];
}

- (void)loadURL:(NSURL *)url
{
    if (!url) return;
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:req];
}

- (void)updateToolbarButtons
{
    _backItem.enabled = [self.webView canGoBack];
    _forwardItem.enabled = [self.webView canGoForward];

    if (_currentEntry && _currentArchive) {
        BOOL isBookmarked = [[KWBookmarkManager sharedManager] isBookmarkedUrl:[_currentEntry fullPath] archiveId:_currentArchive.archiveId];
        _bookmarkItem.style = isBookmarked ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain;
    }
}

#pragma mark - Actions

- (void)goBackTapped:(id)sender
{
    if ([self.webView canGoBack]) {
        [self.webView goBack];
    }
}

- (void)goForwardTapped:(id)sender
{
    if ([self.webView canGoForward]) {
        [self.webView goForward];
    }
}

- (void)searchTapped:(id)sender
{
    KWSearchViewController *searchVC = [[KWSearchViewController alloc] init];
    searchVC.readerVC = self;
    searchVC.archive = _currentArchive;
    [self.navigationController pushViewController:searchVC animated:YES];
}

- (void)bookmarkTapped:(id)sender
{
    if (!_currentEntry || !_currentArchive) return;

    KWBookmarkManager *bm = [KWBookmarkManager sharedManager];
    NSString *path = [_currentEntry fullPath];
    if ([bm isBookmarkedUrl:path archiveId:_currentArchive.archiveId]) {
        [bm removeBookmarkWithUrl:path archiveId:_currentArchive.archiveId];
    } else {
        [bm addBookmarkWithTitle:_currentEntry.title url:path archiveId:_currentArchive.archiveId];
    }
    [self updateToolbarButtons];
}

- (void)themeTapped:(id)sender
{
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Appearance")
                                                       delegate:self
                                              cancelButtonTitle:L(@"Cancel")
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:L(@"Light"), L(@"Sepia"), L(@"Dark"), L(@"LargerText"), L(@"SmallerText"), nil];
    [sheet showFromToolbar:self.navigationController.toolbar];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 0) { // Light
        _currentThemeIndex = 0;
        [self applyTheme];
    } else if (buttonIndex == 1) { // Sepia
        _currentThemeIndex = 1;
        [self applyTheme];
    } else if (buttonIndex == 2) { // Dark
        _currentThemeIndex = 2;
        [self applyTheme];
    } else if (buttonIndex == 3) { // Font +
        if (_fontSizePercent < 200) _fontSizePercent += 15;
        [self applyFontSize];
    } else if (buttonIndex == 4) { // Font -
        if (_fontSizePercent > 60) _fontSizePercent -= 15;
        [self applyFontSize];
    }
}

- (void)applyTheme
{
    NSString *themeClass = @"";
    if (_currentThemeIndex == 1) themeClass = @"theme-sepia";
    else if (_currentThemeIndex == 2) themeClass = @"theme-dark";

    NSString *js = [NSString stringWithFormat:@"document.body.className = '%@';", themeClass];
    [self.webView stringByEvaluatingJavaScriptFromString:js];
}

- (void)applyFontSize
{
    NSString *js = [NSString stringWithFormat:@"document.body.style.fontSize = '%ld%%';", (long)_fontSizePercent];
    [self.webView stringByEvaluatingJavaScriptFromString:js];
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    [self updateToolbarButtons];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;

    NSURL *currentURL = webView.request.URL;
    if ([[currentURL scheme] isEqualToString:@"zim"]) {
        NSString *path = currentURL.path;
        while ([path hasPrefix:@"/"]) {
            path = [path substringFromIndex:1];
        }
        ZIMEntry *entry = [_currentArchive entryForPath:path];
        if (entry) {
            _currentEntry = entry;
        }
    }

    [self updateToolbarButtons];

    NSString *pageTitle = [webView stringByEvaluatingJavaScriptFromString:@"document.title"];
    if (pageTitle && pageTitle.length > 0) {
        self.title = pageTitle;
    }

    [self applyTheme];
    [self applyFontSize];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    [self updateToolbarButtons];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSURL *url = request.URL;
    if ([[url scheme] isEqualToString:@"zim"]) {
        return YES;
    }
    // Handle external links (http/https) in Safari or alert
    if ([[url scheme] isEqualToString:@"http"] || [[url scheme] isEqualToString:@"https"]) {
        [[UIApplication sharedApplication] openURL:url];
        return NO;
    }
    return YES;
}

@end
