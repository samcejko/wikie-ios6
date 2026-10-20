#import "KWWiFiUploadServer.h"
#import "KWArchiveManager.h"
#import "KWCommon.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <ifaddrs.h>
#include <fcntl.h>
#include <string.h>
#include <stdio.h>
#include <sys/time.h>
#include <errno.h>

@interface KWWiFiUploadServer () {
    int _listenSocket;
    dispatch_queue_t _serverQueue;
}
@end

@implementation KWWiFiUploadServer

+ (instancetype)sharedServer
{
    static KWWiFiUploadServer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[KWWiFiUploadServer alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _listenSocket = -1;
        _serverQueue = dispatch_queue_create("com.samcejko.kiwix.wifi", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (BOOL)startWithPort:(UInt16)port error:(NSError **)error
{
    if (_isRunning) return YES;

    _port = port;
    _listenSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (_listenSocket < 0) {
        if (error) *error = KWMakeError(KWErrorNetwork, @"Failed to create socket");
        return NO;
    }

    int opt = 1;
    setsockopt(_listenSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(_port);

    if (bind(_listenSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(_listenSocket);
        _listenSocket = -1;
        if (error) *error = KWMakeError(KWErrorNetwork, @"Failed to bind socket");
        return NO;
    }

    if (listen(_listenSocket, 5) < 0) {
        close(_listenSocket);
        _listenSocket = -1;
        if (error) *error = KWMakeError(KWErrorNetwork, @"Failed to listen on socket");
        return NO;
    }

    _isRunning = YES;
    KWLog(@"Wi-Fi upload server started on %@", [self serverURL]);

    // The loop owns a separate descriptor, so restarting cannot reuse its fd.
    int listener = dup(_listenSocket);
    if (listener < 0) {
        [self stop];
        if (error) *error = KWMakeError(KWErrorNetwork, @"Failed to start listener");
        return NO;
    }
    dispatch_async(_serverQueue, ^{
        [self acceptLoop:listener];
        close(listener);
    });

    return YES;
}

- (void)stop
{
    if (!_isRunning) return;
    _isRunning = NO;
    if (_listenSocket >= 0) {
        shutdown(_listenSocket, SHUT_RDWR);
        close(_listenSocket);
        _listenSocket = -1;
    }
    KWLog(@"Wi-Fi upload server stopped");
}

- (NSString *)localIPAddress
{
    NSString *address = @"127.0.0.1";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr && temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name isEqualToString:@"en0"] || [name isEqualToString:@"en1"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

- (NSString *)serverURL
{
    return [NSString stringWithFormat:@"http://%@:%u", [self localIPAddress], _port];
}

- (void)acceptLoop:(int)listener
{
    while (YES) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientSock = accept(listener, (struct sockaddr *)&clientAddr, &clientLen);
        if (clientSock < 0) {
            if (errno == EINTR) continue;
            break;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self handleClient:clientSock];
        });
    }
}

- (void)respondToClient:(int)sock status:(NSInteger)status body:(NSString *)body html:(BOOL)html
{
    NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\nContent-Type: %@; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
        (long)status, status == 200 ? @"OK" : @"Error", html ? @"text/html" : @"text/plain", (unsigned long)data.length];
    NSMutableData *response = [[header dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [response appendData:data];
    NSUInteger sent = 0;
    while (sent < response.length) {
        ssize_t n = send(sock, (const char *)response.bytes + sent, response.length - sent, 0);
        if (n <= 0) break;
        sent += (NSUInteger)n;
    }
    close(sock);
}

- (void)handleClient:(int)sock
{
    int noSignal = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
    struct timeval timeout = {30, 0};
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    NSMutableData *received = [NSMutableData data];
    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange end = NSMakeRange(NSNotFound, 0);
    char chunk[32768];
    while (end.location == NSNotFound && received.length < 65536) {
        ssize_t n = recv(sock, chunk, sizeof(chunk), 0);
        if (n <= 0) break;
        [received appendBytes:chunk length:(NSUInteger)n];
        end = [received rangeOfData:separator options:0 range:NSMakeRange(0, received.length)];
    }
    if (end.location == NSNotFound || end.location > 65536) {
        [self respondToClient:sock status:400 body:L(@"UploadInvalidRequest") html:NO]; return;
    }
    NSString *header = [[NSString alloc] initWithBytes:received.bytes length:end.location encoding:NSISOLatin1StringEncoding];
    NSArray *lines = [header componentsSeparatedByString:@"\r\n"];
    NSString *request = lines.count ? lines[0] : @"";
    if ([request isEqualToString:@"GET / HTTP/1.1"] || [request isEqualToString:@"GET / HTTP/1.0"]) {
        NSString *page = @"<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width'>"
            "<title>Wikie</title><style>body{font:18px sans-serif;max-width:40em;margin:3em auto;padding:1em}</style>"
            "<h1>Wikie</h1><p>Nahrát archiv / Upload archive (.zim)</p>"
            "<input id='file' type='file' accept='.zim'><button id='upload'>Nahrát / Upload</button><p id='status'></p>"
            "<script>document.getElementById('upload').onclick=function(){var f=document.getElementById('file').files[0];"
            "if(!f)return;var b=this,s=document.getElementById('status'),x=new XMLHttpRequest();b.disabled=true;"
            "x.open('POST','/upload');x.setRequestHeader('Content-Type','application/octet-stream');"
            "x.setRequestHeader('X-Filename',encodeURIComponent(f.name));"
            "x.upload.onprogress=function(e){if(e.lengthComputable)s.textContent=Math.round(e.loaded/e.total*100)+'%';};"
            "x.onload=function(){s.textContent=x.responseText;b.disabled=false;};"
            "x.onerror=function(){s.textContent='Chyba přenosu / Transfer failed';b.disabled=false;};x.send(f);};</script>";
        [self respondToClient:sock status:200 body:page html:YES]; return;
    }
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i]; NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *fieldName = [[line substringToIndex:colon.location] lowercaseString];
        fieldName = [fieldName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *fieldValue = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        fields[fieldName] = fieldValue;
    }
    NSString *lengthText = fields[@"content-length"];
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    long long length = [lengthText longLongValue];
    NSString *filename = [[fields[@"x-filename"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] lastPathComponent];
    if (![request hasPrefix:@"POST /upload HTTP/1."] || length < 80 || !lengthText.length ||
        [lengthText rangeOfCharacterFromSet:nonDigits].location != NSNotFound || fields[@"transfer-encoding"] ||
        ![[filename.pathExtension lowercaseString] isEqualToString:@"zim"] || ![fields[@"content-type"] isEqualToString:@"application/octet-stream"]) {
        [self respondToClient:sock status:400 body:L(@"UploadInvalidRequest") html:NO]; return;
    }
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *temporary = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.upload", KWUniqueIdentifier()]];
    FILE *file = fopen(temporary.fileSystemRepresentation, "wb");
    BOOL ok = file != NULL;
    uint64_t remaining = (uint64_t)length;
    NSUInteger bodyStart = NSMaxRange(end), initial = received.length - bodyStart;
    if (ok && initial) {
        size_t count = (size_t)MIN((uint64_t)initial, remaining);
        ok = fwrite((const char *)received.bytes + bodyStart, 1, count, file) == count;
        remaining -= count;
    }
    while (ok && remaining) {
        ssize_t n = recv(sock, chunk, (size_t)MIN(remaining, (uint64_t)sizeof(chunk)), 0);
        if (n <= 0) { ok = NO; break; }
        ok = fwrite(chunk, 1, (size_t)n, file) == (size_t)n;
        remaining -= (uint64_t)n;
    }
    if (file && fclose(file) != 0) ok = NO;
    if (ok) {
        unsigned char magic[4] = {0};
        FILE *check = fopen(temporary.fileSystemRepresentation, "rb");
        ok = check && fread(magic, 1, sizeof(magic), check) == sizeof(magic) &&
            magic[0] == 0x5a && magic[1] == 0x49 && magic[2] == 0x4d && magic[3] == 0x04;
        if (check) fclose(check);
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *target = [docs stringByAppendingPathComponent:filename];
    if ([fm fileExistsAtPath:target]) target = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.zim", filename.stringByDeletingPathExtension, KWUniqueIdentifier()]];
    if (ok) ok = [fm moveItemAtPath:temporary toPath:target error:nil];
    if (!ok) [fm removeItemAtPath:temporary error:nil];
    if (ok) [[KWArchiveManager sharedManager] rescanArchives];
    [self respondToClient:sock status:ok ? 200 : 400 body:L(ok ? @"UploadComplete" : @"UploadFailed") html:NO];
}

@end
