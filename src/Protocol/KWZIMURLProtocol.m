#import "KWZIMURLProtocol.h"
#import "KWArchiveManager.h"
#import "KWCommon.h"

static NSString * const KWZIMProtocolHandledKey = @"KWZIMProtocolHandledKey";

@implementation KWZIMURLProtocol

+ (void)registerProtocol
{
    [NSURLProtocol registerClass:self];
}

+ (NSURL *)URLForArchiveId:(NSString *)archiveId path:(NSString *)path
{
    NSString *cleanPath = path;
    while ([cleanPath hasPrefix:@"/"]) {
        cleanPath = [cleanPath substringFromIndex:1];
    }
    // Entry names are raw UTF-8 paths, not URLs. Escape reserved characters too:
    // a literal # or ? in a title must not become a fragment or query.
    NSString *escapedPath = CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
        kCFAllocatorDefault, (__bridge CFStringRef)(cleanPath ?: @""), CFSTR("/"),
        CFSTR("?#%"), kCFStringEncodingUTF8));
    NSString *escapedId = CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
        kCFAllocatorDefault, (__bridge CFStringRef)(archiveId ?: @"current"), NULL,
        CFSTR("/?#%:@"), kCFStringEncodingUTF8));
    NSString *urlString = [NSString stringWithFormat:@"zim://%@/%@", escapedId, escapedPath];
    return [NSURL URLWithString:urlString];
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    if ([NSURLProtocol propertyForKey:KWZIMProtocolHandledKey inRequest:request]) {
        return NO;
    }

    NSString *scheme = [[request.URL scheme] lowercaseString];
    if ([scheme isEqualToString:@"zim"]) {
        return YES;
    }

    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:KWZIMProtocolHandledKey inRequest:newRequest];

    NSURL *url = self.request.URL;
    NSString *host = [url.host stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *path = url.path;

    while ([path hasPrefix:@"/"]) {
        path = [path substringFromIndex:1];
    }

    // Special case: internal reader stylesheet
    if ([host isEqualToString:@"local"] && [path isEqualToString:@"reader.css"]) {
        NSString *cssPath = [[NSBundle mainBundle] pathForResource:@"reader" ofType:@"css"];
        NSData *cssData = [NSData dataWithContentsOfFile:cssPath];
        if (cssData) {
            NSURLResponse *response = [[NSURLResponse alloc] initWithURL:url
                                                                MIMEType:@"text/css"
                                                   expectedContentLength:cssData.length
                                                        textEncodingName:@"utf-8"];
            [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:cssData];
            [self.client URLProtocolDidFinishLoading:self];
            return;
        }
    }

    KWArchiveManager *manager = [KWArchiveManager sharedManager];
    ZIMFile *file = nil;

    if (host && ![host isEqualToString:@"current"]) {
        file = [manager archiveForId:host];
    }
    if (!file) {
        file = manager.activeArchive;
    }

    if (!file) {
        NSError *err = KWMakeError(KWErrorEntryNotFound, @"No active ZIM archive found");
        [self.client URLProtocol:self didFailWithError:err];
        return;
    }

    NSString *mime = nil;
    NSError *error = nil;
    NSData *data = [file dataForPath:path mimeType:&mime error:&error];

    if (!data) {
        [self.client URLProtocol:self didFailWithError:error ? error : KWMakeError(KWErrorEntryNotFound, @"Item not found")];
        return;
    }

    if (!mime || mime.length == 0) {
        // Guess MIME from extension
        NSString *ext = [[path pathExtension] lowercaseString];
        if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) mime = @"text/html";
        else if ([ext isEqualToString:@"css"]) mime = @"text/css";
        else if ([ext isEqualToString:@"js"]) mime = @"application/javascript";
        else if ([ext isEqualToString:@"png"]) mime = @"image/png";
        else if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) mime = @"image/jpeg";
        else if ([ext isEqualToString:@"gif"]) mime = @"image/gif";
        else if ([ext isEqualToString:@"svg"]) mime = @"image/svg+xml";
        else mime = @"application/octet-stream";
    }

    // If HTML: inject viewport and custom reader.css link if needed
    if ([mime hasPrefix:@"text/html"]) {
        NSString *htmlString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (htmlString) {
            BOOL modified = NO;
            // Inject viewport if missing
            if ([htmlString rangeOfString:@"viewport" options:NSCaseInsensitiveSearch].location == NSNotFound) {
                NSRange headRange = [htmlString rangeOfString:@"<head>" options:NSCaseInsensitiveSearch];
                if (headRange.location != NSNotFound) {
                    NSString *vpTag = @"<head>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, user-scalable=yes\">\n<link rel=\"stylesheet\" href=\"zim://local/reader.css\">\n";
                    htmlString = [htmlString stringByReplacingCharactersInRange:headRange withString:vpTag];
                    modified = YES;
                }
            } else {
                // Just add reader stylesheet
                NSRange headRange = [htmlString rangeOfString:@"<head>" options:NSCaseInsensitiveSearch];
                if (headRange.location != NSNotFound) {
                    NSString *cssTag = @"<head>\n<link rel=\"stylesheet\" href=\"zim://local/reader.css\">\n";
                    htmlString = [htmlString stringByReplacingCharactersInRange:headRange withString:cssTag];
                    modified = YES;
                }
            }

            if (modified) {
                data = [htmlString dataUsingEncoding:NSUTF8StringEncoding];
            }
        }
    }

    NSURLResponse *response = [[NSURLResponse alloc] initWithURL:url
                                                        MIMEType:mime
                                           expectedContentLength:data.length
                                                textEncodingName:@"utf-8"];

    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading
{
    // No-op for synchronous in-memory response
}

@end
