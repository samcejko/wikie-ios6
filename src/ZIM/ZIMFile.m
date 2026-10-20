#import "ZIMFile.h"
#import "ZIMCluster.h"
#import "KWCommon.h"
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <stdint.h>

#define KW_MAX_REDIRECT_HOPS 5
#define KW_CLUSTER_CACHE_SIZE 8

@interface ZIMFile () {
    FILE *_fileHandle;
    ZIMHeaderRaw _header;
    NSMutableArray *_mimeTypes;
    NSMutableDictionary *_clusterCache; // clusterIndex -> ZIMCluster
    NSMutableArray *_clusterLRU;        // clusterIndex in access order
    dispatch_queue_t _ioQueue;
    NSData *_titleIndex;
    uint32_t _titleCount;
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
    // Modern archives store the article-only title index as a listing blob.
    ZIMEntry *listing = [self binarySearchURL:@"X/listing/titleOrdered/v1"];
    if (listing) _titleIndex = [self dataForEntry:listing error:nil];
    if (_titleIndex.length % 4 != 0) _titleIndex = nil;
    _titleCount = _titleIndex ? (uint32_t)(_titleIndex.length / 4) :
        (_header.titlePtrPos ? _articleCount : 0);
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
    if (!_ioQueue) return;
    // Wait for readers before closing their FILE; also used during deallocation.
    __unsafe_unretained ZIMFile *file = self;
    dispatch_sync(_ioQueue, ^{
        if (file->_fileHandle) {
            fclose(file->_fileHandle);
            file->_fileHandle = NULL;
        }
    });
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
    if (index >= _titleCount) return nil;
    if (_titleIndex) {
        uint32_t urlIdx;
        memcpy(&urlIdx, (const uint8_t *)_titleIndex.bytes + (size_t)index * 4, 4);
        return [self entryAtURLIndex:urlIdx];
    }

    __block uint32_t urlIdx = ZIM_INVALID_INDEX;
    dispatch_sync(_ioQueue, ^{
        if (!_fileHandle) return;
        off_t offset = (off_t)(_header.titlePtrPos + (uint64_t)index * 4);
        if (fseeko(_fileHandle, offset, SEEK_SET) == 0) {
            if (fread(&urlIdx, 1, sizeof(uint32_t), _fileHandle) != sizeof(uint32_t))
                urlIdx = ZIM_INVALID_INDEX;
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
                entry.mimeType = [_mimeTypes objectAtIndex:mimeType];
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
        int cmp = strcmp(targetPath.UTF8String, midPath.UTF8String);

        if (cmp == NSOrderedSame) {
            return midEntry.isRedirect ? [self resolveRedirect:midEntry hopCount:0] : midEntry;
        } else if (cmp < 0) {
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
    // NSURL.path already excludes the query/fragment. Literal # and ? belong
    // to article names and must survive a lookup.

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

    // Both version 5 and 6 keep namespaces in the directory. Modern content
    // lives in C/, including paths containing subdirectories.
    for (NSString *ns in @[@"C/", @"A/"]) {
        for (NSString *candidate in @[cleanPath, decoded ?: cleanPath]) {
            entry = [self binarySearchURL:[ns stringByAppendingString:candidate]];
            if (entry) return entry;
        }
    }

    return nil;
}

// The on-disk index is ordered by namespace and UTF-8 bytes, not by
// Foundation's case-insensitive/linguistic collation.
- (uint32_t)titleLowerBound:(NSString *)title namespace:(char)ns
{
    uint32_t low = 0, high = _titleCount;
    while (low < high) {
        uint32_t mid = low + (high - low) / 2;
        ZIMEntry *entry = [self entryAtTitleIndex:mid];
        if (!entry) return _titleCount;
        int cmp = (unsigned char)entry.namespaceChar - (unsigned char)ns;
        if (!cmp) cmp = strcmp(entry.title.UTF8String ?: "", title.UTF8String);
        if (cmp < 0) low = mid + 1;
        else high = mid;
    }
    return low;
}

- (ZIMEntry *)entryForTitle:(NSString *)title
{
    if (!title.length) return nil;
    const char namespaces[] = {'C', 'A', 0};
    for (NSUInteger n = 0; n < sizeof(namespaces); n++) {
        ZIMEntry *entry = [self entryAtTitleIndex:[self titleLowerBound:title namespace:namespaces[n]]];
        if (entry.namespaceChar == namespaces[n] && [entry.title isEqualToString:title])
            return entry.isRedirect ? [self resolveRedirect:entry hopCount:0] : entry;
    }
    return nil;
}

- (NSArray *)searchEntriesWithPrefix:(NSString *)prefix maxResults:(NSUInteger)maxResults
{
    NSString *query = [prefix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!query.length || !_titleCount || !maxResults) return @[];
    NSMutableArray *results = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    // Wikipedia capitalizes the first letter; also search the spelling typed
    // by the reader and lowercase titles, without changing index ordering.
    NSRange first = [query rangeOfComposedCharacterSequenceAtIndex:0];
    NSString *capitalized = [[[query substringWithRange:first] uppercaseString]
        stringByAppendingString:[query substringFromIndex:NSMaxRange(first)]];
    NSArray *variants = @[query, capitalized, query.lowercaseString];
    const char namespaces[] = {'C', 'A', 0};
    for (NSString *variant in variants) {
        for (NSUInteger n = 0; n < sizeof(namespaces); n++) {
            uint32_t start = [self titleLowerBound:variant namespace:namespaces[n]];
            for (uint32_t i = start; i < _titleCount && results.count < maxResults; i++) {
                ZIMEntry *entry = [self entryAtTitleIndex:i];
                if (!entry || entry.namespaceChar != namespaces[n] || ![entry.title hasPrefix:variant]) break;
                NSNumber *key = @(entry.entryIndex);
                if (![seen containsObject:key]) {
                    [seen addObject:key];
                    [results addObject:entry];
                }
            }
        }
        if (results.count >= maxResults) break;
    }
    return results;
}

#pragma mark - Content Retrieval & Cluster Caching

- (ZIMCluster *)clusterAtIndex:(uint32_t)clusterIndex error:(NSError **)error
{
    NSNumber *key = @(clusterIndex);

    @synchronized(_clusterCache) {
        ZIMCluster *cached = [_clusterCache objectForKey:key];
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

    uint64_t clusterSize = clusterEnd - clusterStart;
    if (clusterSize > SIZE_MAX) {
        if (error) *error = KWMakeError(KWErrorCorruptHeader, @"Cluster exceeds addressable size");
        return nil;
    }
    size_t rawSize = (size_t)clusterSize;
    NSMutableData *rawData = [NSMutableData dataWithLength:rawSize];
    if (!rawData) {
        if (error) *error = KWMakeError(KWErrorIO, @"Cannot allocate cluster buffer");
        return nil;
    }

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
        // Another reader may have populated this cluster while we decompressed it.
        ZIMCluster *existing = [_clusterCache objectForKey:key];
        if (existing) {
            [_clusterLRU removeObject:key];
            [_clusterLRU addObject:key];
            return existing;
        }
        if (_clusterLRU.count >= KW_CLUSTER_CACHE_SIZE) {
            NSNumber *oldestKey = [_clusterLRU objectAtIndex:0];
            [_clusterCache removeObjectForKey:oldestKey];
            [_clusterLRU removeObjectAtIndex:0];
        }
        [_clusterCache setObject:cluster forKey:key];
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
