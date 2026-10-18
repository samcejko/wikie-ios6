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

    dispatch_async(_serverQueue, ^{
        [self acceptLoop];
    });

    return YES;
}

- (void)stop
{
    if (!_isRunning) return;
    _isRunning = NO;
    if (_listenSocket >= 0) {
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
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
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

- (void)acceptLoop
{
    while (_isRunning && _listenSocket >= 0) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientSock = accept(_listenSocket, (struct sockaddr *)&clientAddr, &clientLen);
        if (clientSock < 0) {
            if (!_isRunning) break;
            continue;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self handleClient:clientSock];
        });
    }
}

- (void)handleClient:(int)sock
{
    char initialBuf[8192];
    ssize_t bytesRead = recv(sock, initialBuf, sizeof(initialBuf) - 1, 0);
    if (bytesRead <= 0) {
        close(sock);
        return;
    }
    initialBuf[bytesRead] = '\0';

    NSString *headerString = [NSString stringWithCString:initialBuf encoding:NSISOLatin1StringEncoding];

    if ([headerString hasPrefix:@"GET / "] || [headerString hasPrefix:@"GET /index.html"]) {
        NSString *html = @"<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        "<title>Kiwix iOS 6 - File Transfer</title>"
        "<style>body{font-family:sans-serif;max-width:600px;margin:40px auto;padding:20px;text-align:center;background:#f5f5f7}"
        ".box{background:white;padding:30px;border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.1)}"
        "h1{color:#333;margin-bottom:10px}p{color:#666;font-size:15px}"
        "input[type=file]{margin:20px 0;padding:12px;border:2px dashed #ccc;width:90%;border-radius:8px}"
        "button{background:#0b57d0;color:white;border:none;padding:12px 28px;font-size:16px;border-radius:6px;cursor:pointer}"
        "</style></head><body><div class='box'>"
        "<h1>Kiwix for iOS 6</h1>"
        "<p>Upload <b>.zim</b> Wikipedia files directly to your device:</p>"
        "<form method='POST' action='/upload' enctype='multipart/form-data'>"
        "<input type='file' name='zimfile' accept='.zim' required><br>"
        "<button type='submit'>Upload to Device</button>"
        "</form></div></body></html>";

        NSString *headers = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)[html lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
        send(sock, [headers UTF8String], [headers lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
        send(sock, [html UTF8String], [html lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
        close(sock);
        return;
    }

    if ([headerString hasPrefix:@"POST /upload"]) {
        // Parse Content-Length
        long long contentLength = 0;
        NSRange clRange = [headerString rangeOfString:@"Content-Length: " options:NSCaseInsensitiveSearch];
        if (clRange.location != NSNotFound) {
            NSUInteger start = clRange.location + clRange.length;
            NSUInteger end = [headerString rangeOfString:@"\r\n" options:0 range:NSMakeRange(start, headerString.length - start)].location;
            if (end != NSNotFound) {
                contentLength = [[headerString substringWithRange:NSMakeRange(start, end - start)] longLongValue];
            }
        }

        // Parse filename
        NSString *filename = @"upload.zim";
        NSRange fnRange = [headerString rangeOfString:@"filename=\"" options:NSCaseInsensitiveSearch];
        if (fnRange.location != NSNotFound) {
            NSUInteger start = fnRange.location + fnRange.length;
            NSUInteger end = [headerString rangeOfString:@"\"" options:0 range:NSMakeRange(start, headerString.length - start)].location;
            if (end != NSNotFound) {
                filename = [headerString substringWithRange:NSMakeRange(start, end - start)];
            }
        }

        filename = [[filename lastPathComponent] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        if (![[[filename pathExtension] lowercaseString] isEqualToString:@"zim"]) {
            filename = [filename stringByAppendingPathExtension:@"zim"];
        }

        // Find boundary and start of body
        char *headerEnd = strstr(initialBuf, "\r\n\r\n");
        if (headerEnd) {
            // Locate secondary multipart header boundary if multipart
            char *fileStart = strstr(headerEnd + 4, "\r\n\r\n");
            if (fileStart) {
                fileStart += 4;
            } else {
                fileStart = headerEnd + 4;
            }

            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *docsDir = [paths count] > 0 ? [paths objectAtIndex:0] : nil;
            NSString *targetPath = [docsDir stringByAppendingPathComponent:filename];

            FILE *outFile = fopen([targetPath UTF8String], "wb");
            if (outFile) {
                size_t headerBytes = (size_t)(fileStart - initialBuf);
                size_t initialDataBytes = (size_t)(bytesRead - headerBytes);

                if (initialDataBytes > 0) {
                    fwrite(fileStart, 1, initialDataBytes, outFile);
                }

                long long totalWritten = initialDataBytes;
                char chunk[32768];

                while (totalWritten < contentLength - 1000) { // approximate boundary padding
                    ssize_t n = recv(sock, chunk, sizeof(chunk), 0);
                    if (n <= 0) break;
                    fwrite(chunk, 1, n, outFile);
                    totalWritten += n;
                }

                fclose(outFile);
                KWLog(@"Successfully uploaded %@ (%lld bytes)", filename, totalWritten);

                [[KWArchiveManager sharedManager] rescanArchives];

                NSString *successHTML = [NSString stringWithFormat:@"<!DOCTYPE html><html><head><meta charset='utf-8'>"
                "<meta name='viewport' content='width=device-width, initial-scale=1'>"
                "<title>Upload Successful</title>"
                "<style>body{font-family:sans-serif;max-width:600px;margin:40px auto;padding:20px;text-align:center;background:#f5f5f7}"
                ".box{background:white;padding:30px;border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.1)}"
                "h1{color:#2e7d32;margin-bottom:10px}a{display:inline-block;margin-top:20px;color:#0b57d0;text-decoration:none;font-weight:bold}"
                "</style></head><body><div class='box'>"
                "<h1>Upload Complete!</h1>"
                "<p>Successfully saved <b>%@</b> to your library.</p>"
                "<a href='/'>Upload Another File</a>"
                "</div></body></html>", filename];

                NSString *respHeaders = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)[successHTML lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
                send(sock, [respHeaders UTF8String], [respHeaders lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
                send(sock, [successHTML UTF8String], [successHTML lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
                close(sock);
                return;
            }
        }
    }

    NSString *resp = @"HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nBad Request";
    send(sock, [resp UTF8String], [resp lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
    close(sock);
}

@end
