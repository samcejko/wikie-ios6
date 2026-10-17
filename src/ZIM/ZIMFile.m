#import "ZIMFile.h"
#import "ZIMCluster.h"
#import "KWCommon.h"
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#define KW_MAX_REDIRECT_HOPS 5
#define KW_CLUSTER_CACHE_SIZE 8

@interface ZIMFile () {
    FILE *_fileHandle;
    ZIMHeaderRaw _header;
    NSMutableArray *_mimeTypes;
    NSMutableDictionary *_clusterCache; // clusterIndex -> ZIMCluster
    NSMutableArray *_clusterLRU;        // clusterIndex in access order
    dispatch_queue_t _ioQueue;
}
@end

@implementation ZIMFile

- (instancetype)initWithPath:(NSString *)filePath error:(NSError **)error
{
    self = [super init];
    if (!self) return nil;

    _filePath = [filePath copy];
    _archiveId = [[[filePath lastPathComponent] stringByDeletingPathExtension] copy];
    _clusterCache = [NSMutableDictionary dictionaryWithCapacity:KW_CLUSTER_CACHE_SIZE];
    _clusterLRU = [NSMutableArray arrayWithCapacity:KW_CLUSTER_CACHE_SIZE];
    _mimeTypes = [NSMutableArray array];
    _ioQueue = dispatch_queue_create("com.samcejko.kiwix.io", DISPATCH_QUEUE_SERIAL);

    struct stat st;
    if (stat([filePath UTF8String], &st) == 0) {
        _fileSize = (uint64_t)st.st_size;
    }

    _fileHandle = fopen([filePath UTF8String], "rb");
    if (!_fileHandle) {
        if (error) *error = KWMakeError(KWErrorIO, [NSString stringWithFormat:@"Cannot open file: %@", filePath]);
        return nil;
    }

    // Read full 80-byte header
    if (fread(&_header, 1, ZIM_HEADER_SIZE, _fileHandle) != ZIM_HEADER_SIZE) {
        fclose(_fileHandle);
        _fileHandle = NULL;
        if (error) *error = KWMakeError(KWErrorCorruptHeader, @"Failed to read ZIM header");
        return nil;
    }

    if (_header.magicNumber != ZIM_MAGIC) {
        fclose(_fileHandle);
        _fileHandle = NULL;
        if (error) *error = KWMakeError(KWErrorInvalidMagic, [NSString stringWithFormat:@"Invalid magic number 0x%08X", _header.magicNumber]);
        return nil;
    }

    _majorVersion = _header.majorVersion;
    _minorVersion = _header.minorVersion;
    _articleCount = _header.articleCount;
    _clusterCount = _header.clusterCount;

    if (_majorVersion != 5 && _majorVersion != 6) {
        KWLog(@"Warning: ZIM major version is %u (expected 5 or 6)", _majorVersion);
    }

    [self parseMimeTypes];
    [self parseMetadata];

    KWLog(@"Opened ZIM archive '%@': ver %u.%u, %u articles, %u clusters, size %@",
          _title ? _title : _archiveId, _majorVersion, _minorVersion, _articleCount, _clusterCount, KWFormattedFileSize(_fileSize));

    return self;
}

- (void)dealloc
{
    [self close];
}

- (void)close
{
    if (_fileHandle) {
        fclose(_fileHandle);
        _fileHandle = NULL;
    }
}

#pragma mark - MIME & Metadata Parsing

- (void)parseMimeTypes
{
    if (_header.mimeListPos == 0 || _header.mimeListPos >= _fileSize) return;

    if (fseeko(_fileHandle, (off_t)_header.mimeListPos, SEEK_SET) != 0) return;

    char buffer[8192];
    size_t readBytes = fread(buffer, 1, sizeof(buffer), _fileHandle);
    size_t offset = 0;

    while (offset < readBytes) {
        size_t len = strnlen(buffer + offset, readBytes - offset);
        if (len == 0) break; // empty string terminates MIME list

        NSString *mime = [[NSString alloc] initWithBytes:buffer + offset length:len encoding:NSUTF8StringEncoding];
        if (mime) {
            [_mimeTypes addObject:mime];
        }
        offset += len + 1;
    }
}

- (void)parseMetadata
{
    _title = [self readMetadataString:@"Title"];
    if (!_title || _title.length == 0) {
        _title = [_archiveId stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    }

    _archiveDescription = [self readMetadataString:@"Description"];
    _language = [self readMetadataString:@"Language"];
    _date = [self readMetadataString:@"Date"];
    _creator = [self readMetadataString:@"Creator"];

    _faviconData = [self readMetadataData:@"Favicon"];
    if (!_faviconData) {
        _faviconData = [self readMetadataData:@"favicon.png"];
    }
}

- (NSString *)readMetadataString:(NSString *)key
{
    NSData *data = [self readMetadataData:key];
    if (data && data.length > 0) {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (NSData *)readMetadataData:(NSString *)key
{
    NSString *pathWithPrefix = [NSString stringWithFormat:@"M/%@", key];
    ZIMEntry *entry = [self entryForPath:pathWithPrefix];
    if (!entry) {
        entry = [self entryForPath:key];
    }
    if (entry) {
        return [self dataForEntry:entry error:nil];
    }
    return nil;
}

#pragma mark - Entry Reading

- (ZIMEntry *)entryAtURLIndex:(uint32_t)index
{
    if (index >= _articleCount) return nil;
    uint64_t entryOffset = [self readPointerAtBase:_header.urlPtrPos index:index];
    if (entryOffset == 0) return nil;
    return [self readEntryAtOffset:entryOffset index:index];
}

// In openZIM spec: titlePtrPos is an array of 32-bit indices pointing into urlPtrPos
- (ZIMEntry *)entryAtTitleIndex:(uint32_t)index
{
    if (index >= _articleCount) return nil;

    if (_header.titlePtrPos == 0) {
        // Obsolete in some v6 archives: fallback to URL index directly
        return [self entryAtURLIndex:index];
    }

    __block uint32_t urlIdx = 0;
    dispatch_sync(_ioQueue, ^{
        if (!_fileHandle) return;
        off_t offset = (off_t)(_header.titlePtrPos + (uint64_t)index * 4);
        if (fseeko(_fileHandle, offset, SEEK_SET) == 0) {
            fread(&urlIdx, 1, sizeof(uint32_t), _fileHandle);
        }
    });

    if (urlIdx >= _articleCount) return nil;
    return [self entryAtURLIndex:urlIdx];
}

- (uint64_t)readPointerAtBase:(uint64_t)basePos index:(uint32_t)index
{
    __block uint64_t ptr = 0;
    dispatch_sync(_ioQueue, ^{
        if (!_fileHandle) return;
        off_t offset = (off_t)(basePos + (uint64_t)index * 8);
        if (fseeko(_fileHandle, offset, SEEK_SET) == 0) {
            fread(&ptr, 1, sizeof(uint64_t), _fileHandle);
        }
    });
    return ptr;
}

- (ZIMEntry *)readEntryAtOffset:(uint64_t)offset index:(uint32_t)index
{
    __block ZIMEntry *entry = nil;
    dispatch_sync(_ioQueue, ^{
        if (!_fileHandle) return;
        if (fseeko(_fileHandle, (off_t)offset, SEEK_SET) != 0) return;

        uint8_t headerBuf[16];
        if (fread(headerBuf, 1, 16, _fileHandle) < 16) return;

        uint16_t mimeType = *(uint16_t *)(headerBuf + 0);
        uint8_t paramLen = headerBuf[2];
        char ns = (char)headerBuf[3];
        uint32_t revision = *(uint32_t *)(headerBuf + 4);

        entry = [[ZIMEntry alloc] init];
        entry.entryIndex = index;
        entry.mimeTypeIndex = mimeType;
        entry.namespaceChar = ns;
        entry.revision = revision;

        off_t stringsOffset = 0;
        if (mimeType == ZIM_REDIRECT_MIMETYPE) {
            entry.isRedirect = YES;
            entry.redirectIndex = *(uint32_t *)(headerBuf + 8);
            stringsOffset = (off_t)(offset + 12);
        } else {
            entry.isRedirect = NO;
            entry.clusterNumber = *(uint32_t *)(headerBuf + 8);
            entry.blobNumber = *(uint32_t *)(headerBuf + 12);
            if (mimeType < _mimeTypes.count) {
                entry.mimeType = _mimeTypes[mimeType];
            }
            stringsOffset = (off_t)(offset + 16);
        }

        if (fseeko(_fileHandle, stringsOffset, SEEK_SET) != 0) return;

        char stringBuf[2048];
        size_t bytesRead = fread(stringBuf, 1, sizeof(stringBuf) - 1, _fileHandle);
        stringBuf[bytesRead] = '\0';

        size_t urlLen = strnlen(stringBuf, bytesRead);
        entry.url = [[NSString alloc] initWithBytes:stringBuf length:urlLen encoding:NSUTF8StringEncoding];
        if (!entry.url) {
            entry.url = [[NSString alloc] initWithBytes:stringBuf length:urlLen encoding:NSISOLatin1StringEncoding];
        }

        if (urlLen + 1 < bytesRead) {
            size_t titleLen = strnlen(stringBuf + urlLen + 1, bytesRead - (urlLen + 1));
            if (titleLen > 0) {
                entry.title = [[NSString alloc] initWithBytes:stringBuf + urlLen + 1 length:titleLen encoding:NSUTF8StringEncoding];
                if (!entry.title) {
                    entry.title = [[NSString alloc] initWithBytes:stringBuf + urlLen + 1 length:titleLen encoding:NSISOLatin1StringEncoding];
                }
            }
        }

        if (!entry.title || entry.title.length == 0) {
            entry.title = entry.url;
        }
    });

    return entry;
}

#pragma mark - Main Page

- (ZIMEntry *)mainPageEntry
{
    if (_header.mainPage != ZIM_INVALID_INDEX && _header.mainPage < _articleCount) {
        ZIMEntry *entry = [self entryAtURLIndex:_header.mainPage];
        if (entry.isRedirect) {
            return [self resolveRedirect:entry hopCount:0];
        }
        return entry;
    }

    // Standard fallback paths
    NSArray *candidates = @[@"main.html", @"index.html", @"A/main.html", @"A/index.html", @"A/Main_Page.html", @"Main_Page.html"];
    for (NSString *cand in candidates) {
        ZIMEntry *e = [self entryForPath:cand];
        if (e) return e;
    }

    if (_articleCount > 0) {
        return [self entryAtURLIndex:0];
    }
    return nil;
}

#pragma mark - Binary Searches

- (ZIMEntry *)resolveRedirect:(ZIMEntry *)redirectEntry hopCount:(int)hop
{
    if (hop > KW_MAX_REDIRECT_HOPS) return nil;
    if (!redirectEntry || !redirectEntry.isRedirect) return redirectEntry;

    ZIMEntry *target = [self entryAtURLIndex:redirectEntry.redirectIndex];
    if (target.isRedirect) {
        return [self resolveRedirect:target hopCount:hop + 1];
    }
    return target;
}

- (ZIMEntry *)binarySearchURL:(NSString *)targetPath
{
    int64_t low = 0;
    int64_t high = (int64_t)_articleCount - 1;

    while (low <= high) {
        int64_t mid = low + (high - low) / 2;
        ZIMEntry *midEntry = [self entryAtURLIndex:(uint32_t)mid];
        if (!midEntry) break;

        NSString *midPath = [midEntry fullPath];
        NSComparisonResult cmp = [targetPath compare:midPath options:NSLiteralSearch];

        if (cmp == NSOrderedSame) {
            return midEntry.isRedirect ? [self resolveRedirect:midEntry hopCount:0] : midEntry;
        } else if (cmp == NSOrderedAscending) {
            high = mid - 1;
        } else {
            low = mid + 1;
        }
    }
    return nil;
}

- (ZIMEntry *)entryForPath:(NSString *)path
{
    if (!path || path.length == 0 || _articleCount == 0) return nil;

    NSString *cleanPath = path;
    // Strip query parameters and anchors if any
    NSRange hashRange = [cleanPath rangeOfString:@"#"];
    if (hashRange.location != NSNotFound) {
        cleanPath = [cleanPath substringToIndex:hashRange.location];
    }
    NSRange qRange = [cleanPath rangeOfString:@"?"];
    if (qRange.location != NSNotFound) {
        cleanPath = [cleanPath substringToIndex:qRange.location];
    }

    while ([cleanPath hasPrefix:@"/"]) {
        cleanPath = [cleanPath substringFromIndex:1];
    }

    // 1. Direct path lookup
    ZIMEntry *entry = [self binarySearchURL:cleanPath];
    if (entry) return entry;

    // 2. Percent-decoded lookup
    NSString *decoded = [cleanPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (decoded && ![decoded isEqualToString:cleanPath]) {
        entry = [self binarySearchURL:decoded];
        if (entry) return entry;
    }

    // 3. Percent-encoded lookup
    NSString *encoded = [cleanPath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (encoded && ![encoded isEqualToString:cleanPath]) {
        entry = [self binarySearchURL:encoded];
        if (entry) return entry;
    }

    // 4. In v5: if no namespace prefix, try prepending "A/"
    if (_majorVersion == 5 && [cleanPath rangeOfString:@"/"].location == NSNotFound) {
        NSString *prefixed = [NSString stringWithFormat:@"A/%@", cleanPath];
        entry = [self binarySearchURL:prefixed];
        if (entry) return entry;
    }

    return nil;
}

- (ZIMEntry *)entryForTitle:(NSString *)title
{
    if (!title || title.length == 0 || _articleCount == 0) return nil;

    int64_t low = 0;
    int64_t high = (int64_t)_articleCount - 1;

    while (low <= high) {
        int64_t mid = low + (high - low) / 2;
        ZIMEntry *midEntry = [self entryAtTitleIndex:(uint32_t)mid];
        if (!midEntry) break;

        NSComparisonResult cmp = [title compare:midEntry.title options:NSCaseInsensitiveSearch];

        if (cmp == NSOrderedSame) {
            return midEntry.isRedirect ? [self resolveRedirect:midEntry hopCount:0] : midEntry;
        } else if (cmp == NSOrderedAscending) {
            high = mid - 1;
        } else {
            low = mid + 1;
        }
    }

    return nil;
}

- (NSArray *)searchEntriesWithPrefix:(NSString *)prefix maxResults:(NSUInteger)maxResults
{
    if (!prefix || prefix.length == 0 || _articleCount == 0 || maxResults == 0) {
        return @[];
    }

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:maxResults];
    NSString *cleanPrefix = [prefix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    int64_t low = 0;
    int64_t high = (int64_t)_articleCount - 1;
    int64_t startIndex = -1;

    while (low <= high) {
        int64_t mid = low + (high - low) / 2;
        ZIMEntry *entry = [self entryAtTitleIndex:(uint32_t)mid];
        if (!entry) break;

        if ([entry.title compare:cleanPrefix options:NSCaseInsensitiveSearch] != NSOrderedAscending) {
            startIndex = mid;
            high = mid - 1;
        } else {
            low = mid + 1;
        }
    }

    if (startIndex < 0 || startIndex >= _articleCount) return results;

    for (uint32_t i = (uint32_t)startIndex; i < _articleCount && results.count < maxResults; i++) {
        ZIMEntry *entry = [self entryAtTitleIndex:i];
        if (!entry) break;

        if ([entry.title rangeOfString:cleanPrefix options:NSCaseInsensitiveSearch | NSAnchoredSearch].location != NSNotFound) {
            if (entry.namespaceChar == 'A' || entry.namespaceChar == 0 || entry.namespaceChar == 'C') {
                [results addObject:entry];
            }
        } else {
            break;
        }
    }

    return results;
}

#pragma mark - Content Retrieval & Cluster Caching

- (ZIMCluster *)clusterAtIndex:(uint32_t)clusterIndex error:(NSError **)error
{
    NSNumber *key = @(clusterIndex);

    @synchronized(_clusterCache) {
        ZIMCluster *cached = _clusterCache[key];
        if (cached) {
            [_clusterLRU removeObject:key];
            [_clusterLRU addObject:key];
            return cached;
        }
    }

    if (clusterIndex >= _clusterCount) {
        if (error) *error = KWMakeError(KWErrorCorruptHeader, [NSString stringWithFormat:@"Cluster index %u >= count %u", clusterIndex, _clusterCount]);
        return nil;
    }

    uint64_t clusterStart = [self readPointerAtBase:_header.clusterPtrPos index:clusterIndex];
    uint64_t clusterEnd = 0;

    if (clusterIndex + 1 < _clusterCount) {
        clusterEnd = [self readPointerAtBase:_header.clusterPtrPos index:clusterIndex + 1];
    } else {
        // Last cluster ends at checksumPos or 16 bytes before EOF
        clusterEnd = (_header.checksumPos > clusterStart && _header.checksumPos <= _fileSize) ? _header.checksumPos : (_fileSize > 16 ? _fileSize - 16 : _fileSize);
    }

    if (clusterStart >= clusterEnd || clusterEnd > _fileSize) {
        if (error) *error = KWMakeError(KWErrorCorruptHeader, @"Invalid cluster boundaries");
        return nil;
    }

    size_t rawSize = (size_t)(clusterEnd - clusterStart);
    NSMutableData *rawData = [NSMutableData dataWithLength:rawSize];

    __block BOOL readSuccess = NO;
    dispatch_sync(_ioQueue, ^{
        if (!_fileHandle) return;
        if (fseeko(_fileHandle, (off_t)clusterStart, SEEK_SET) == 0) {
            if (fread(rawData.mutableBytes, 1, rawSize, _fileHandle) == rawSize) {
                readSuccess = YES;
            }
        }
    });

    if (!readSuccess) {
        if (error) *error = KWMakeError(KWErrorIO, @"Failed to read cluster raw data");
        return nil;
    }

    ZIMCluster *cluster = [[ZIMCluster alloc] initWithClusterIndex:clusterIndex rawData:rawData error:error];
    if (!cluster) return nil;

    @synchronized(_clusterCache) {
        if (_clusterLRU.count >= KW_CLUSTER_CACHE_SIZE) {
            NSNumber *oldestKey = _clusterLRU[0];
            [_clusterCache removeObjectForKey:oldestKey];
            [_clusterLRU removeObjectAtIndex:0];
        }
        _clusterCache[key] = cluster;
        [_clusterLRU addObject:key];
    }

    return cluster;
}

- (NSData *)dataForEntry:(ZIMEntry *)entry error:(NSError **)error
{
    if (!entry) {
        if (error) *error = KWMakeError(KWErrorEntryNotFound, @"Null entry provided");
        return nil;
    }

    if (entry.isRedirect) {
        ZIMEntry *resolved = [self resolveRedirect:entry hopCount:0];
        if (!resolved) {
            if (error) *error = KWMakeError(KWErrorRedirectLoop, @"Redirect resolution failed");
            return nil;
        }
        return [self dataForEntry:resolved error:error];
    }

    ZIMCluster *cluster = [self clusterAtIndex:entry.clusterNumber error:error];
    if (!cluster) return nil;

    NSData *blob = [cluster blobAtIndex:entry.blobNumber];
    if (!blob && error) {
        *error = KWMakeError(KWErrorCorruptHeader, [NSString stringWithFormat:@"Blob %u missing in cluster %u", entry.blobNumber, entry.clusterNumber]);
    }

    return blob;
}

- (NSData *)dataForPath:(NSString *)path mimeType:(NSString **)outMime error:(NSError **)error
{
    ZIMEntry *entry = [self entryForPath:path];
    if (!entry) {
        if (error) *error = KWMakeError(KWErrorEntryNotFound, [NSString stringWithFormat:@"Entry not found for path: %@", path]);
        return nil;
    }

    if (outMime) {
        *outMime = entry.mimeType;
    }

    return [self dataForEntry:entry error:error];
}

@end
