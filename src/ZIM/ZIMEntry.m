#import "ZIMEntry.h"

@implementation ZIMEntry

- (NSString *)fullPath
{
    if (_namespaceChar != 0 && _namespaceChar != ' ') {
        return [NSString stringWithFormat:@"%c/%@", _namespaceChar, _url ? _url : @""];
    }
    return _url ? _url : @"";
}

- (NSString *)description
{
    if (_isRedirect) {
        return [NSString stringWithFormat:@"<ZIMEntry (Redirect): url='%@' -> idx=%u>", [self fullPath], _redirectIndex];
    }
    return [NSString stringWithFormat:@"<ZIMEntry: url='%@' title='%@' cluster=%u blob=%u mime='%@'>",
            [self fullPath], _title, _clusterNumber, _blobNumber, _mimeType];
}

@end
