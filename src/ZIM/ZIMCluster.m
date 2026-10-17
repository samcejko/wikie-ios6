#import "ZIMCluster.h"
#import "KWCommon.h"
#import <zlib.h>
#import <string.h>

// Forward declaration of Zstd C API functions (linked via zstddeclib.c)
extern size_t ZSTD_decompress(void* dst, size_t dstCapacity, const void* src, size_t srcSize) __attribute__((weak));
extern unsigned long long ZSTD_getFrameContentSize(const void *src, size_t srcSize) __attribute__((weak));
extern unsigned ZSTD_isError(size_t code) __attribute__((weak));
extern const char* ZSTD_getErrorName(size_t code) __attribute__((weak));

@interface ZIMCluster () {
    NSData *_decompressedData;
}
@end

@implementation ZIMCluster

- (instancetype)initWithClusterIndex:(uint32_t)index
                             rawData:(NSData *)rawData
                               error:(NSError **)error
{
    self = [super init];
    if (!self) return nil;

    _clusterIndex = index;

    if (rawData.length < 1) {
        if (error) *error = KWMakeError(KWErrorCorruptHeader, @"Cluster raw data is empty");
        return nil;
    }

    const uint8_t *bytes = (const uint8_t *)rawData.bytes;
    uint8_t headerByte = bytes[0];
    _compressionType = (ZIMCompressionType)(headerByte & 0x0F);
    _isExtended = ((headerByte & 0x10) != 0);

    const void *payloadBytes = bytes + 1;
    size_t payloadLength = rawData.length - 1;

    NSData *decompressed = nil;

    if (_compressionType == ZIMCompressionTypeDefault || _compressionType == ZIMCompressionTypeNone) {
        decompressed = [NSData dataWithBytes:payloadBytes length:payloadLength];
    } else if (_compressionType == ZIMCompressionTypeZlib) {
        decompressed = [self decompressZlib:payloadBytes length:payloadLength error:error];
    } else if (_compressionType == ZIMCompressionTypeZstd) {
        decompressed = [self decompressZstd:payloadBytes length:payloadLength error:error];
    } else {
        NSString *msg = [NSString stringWithFormat:@"Unsupported cluster compression type %u", _compressionType];
        if (error) *error = KWMakeError(KWErrorDecompression, msg);
        return nil;
    }

    if (!decompressed || decompressed.length == 0) {
        if (error && !*error) {
            *error = KWMakeError(KWErrorDecompression, @"Decompression resulted in empty buffer");
        }
        return nil;
    }

    _decompressedData = decompressed;

    // Parse blob offsets table inside decompressed cluster using safe memcpy for ARMv7
    const uint8_t *decBytes = (const uint8_t *)_decompressedData.bytes;

    if (_isExtended) {
        if (_decompressedData.length < 8) {
            if (error) *error = KWMakeError(KWErrorCorruptHeader, @"Extended cluster too small for offsets");
            return nil;
        }
        uint64_t firstOffset = 0;
        memcpy(&firstOffset, decBytes, sizeof(uint64_t));
        if (firstOffset < 8 || (firstOffset % 8) != 0 || firstOffset > _decompressedData.length) {
            if (error) *error = KWMakeError(KWErrorCorruptHeader, @"Invalid extended cluster first offset");
            return nil;
        }
        _blobCount = (uint32_t)(firstOffset / 8 - 1);
    } else {
        if (_decompressedData.length < 4) {
            if (error) *error = KWMakeError(KWErrorCorruptHeader, @"Standard cluster too small for offsets");
            return nil;
        }
        uint32_t firstOffset = 0;
        memcpy(&firstOffset, decBytes, sizeof(uint32_t));
        if (firstOffset < 4 || (firstOffset % 4) != 0 || firstOffset > _decompressedData.length) {
            if (error) *error = KWMakeError(KWErrorCorruptHeader, @"Invalid standard cluster first offset");
            return nil;
        }
        _blobCount = firstOffset / 4 - 1;
    }

    return self;
}

- (NSData *)blobAtIndex:(uint32_t)blobIndex
{
    if (blobIndex >= _blobCount) {
        return nil;
    }

    NSUInteger start = 0;
    NSUInteger end = 0;
    const uint8_t *bytes = (const uint8_t *)_decompressedData.bytes;

    if (_isExtended) {
        uint64_t s64 = 0, e64 = 0;
        memcpy(&s64, bytes + blobIndex * 8, sizeof(uint64_t));
        memcpy(&e64, bytes + (blobIndex + 1) * 8, sizeof(uint64_t));
        start = (NSUInteger)s64;
        end = (NSUInteger)e64;
    } else {
        uint32_t s32 = 0, e32 = 0;
        memcpy(&s32, bytes + blobIndex * 4, sizeof(uint32_t));
        memcpy(&e32, bytes + (blobIndex + 1) * 4, sizeof(uint32_t));
        start = (NSUInteger)s32;
        end = (NSUInteger)e32;
    }

    if (start > end || end > _decompressedData.length) {
        KWLog(@"Error: Blob index %u out of bounds: %lu to %lu (cluster size %lu)",
              blobIndex, (unsigned long)start, (unsigned long)end, (unsigned long)_decompressedData.length);
        return nil;
    }

    return [_decompressedData subdataWithRange:NSMakeRange(start, end - start)];
}

#pragma mark - Decompressors

- (NSData *)decompressZlib:(const void *)bytes length:(size_t)length error:(NSError **)error
{
    if (length == 0) return [NSData data];

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)bytes;
    stream.avail_in = (uInt)length;

    if (inflateInit(&stream) != Z_OK) {
        if (error) *error = KWMakeError(KWErrorDecompression, @"zlib inflateInit failed");
        return nil;
    }

    NSMutableData *decompressed = [NSMutableData dataWithCapacity:length * 3];
    const size_t chunkSize = 64 * 1024;
    Bytef chunk[chunkSize];

    int status = Z_OK;
    while (status == Z_OK) {
        stream.next_out = chunk;
        stream.avail_out = sizeof(chunk);
        status = inflate(&stream, Z_NO_FLUSH);

        size_t written = sizeof(chunk) - stream.avail_out;
        if (written > 0) {
            [decompressed appendBytes:chunk length:written];
        }
    }

    inflateEnd(&stream);

    if (status != Z_STREAM_END && status != Z_OK) {
        if (error) *error = KWMakeError(KWErrorDecompression, @"zlib decompression error");
        return nil;
    }

    return decompressed;
}

- (NSData *)decompressZstd:(const void *)bytes length:(size_t)length error:(NSError **)error
{
    if (!ZSTD_decompress) {
        if (error) *error = KWMakeError(KWErrorDecompression, @"Zstandard decoder is not linked");
        return nil;
    }

    unsigned long long expectedSize = ZSTD_getFrameContentSize ? ZSTD_getFrameContentSize(bytes, length) : 0;
    size_t dstCapacity = 0;

    if (expectedSize == 0 || expectedSize == (unsigned long long)-1 || expectedSize == (unsigned long long)-2) {
        dstCapacity = 2 * 1024 * 1024;
    } else {
        dstCapacity = (size_t)expectedSize;
    }

    void *dst = malloc(dstCapacity);
    if (!dst) {
        if (error) *error = KWMakeError(KWErrorDecompression, @"Out of memory allocating Zstd buffer");
        return nil;
    }

    size_t decompressedSize = ZSTD_decompress(dst, dstCapacity, bytes, length);
    if (ZSTD_isError && ZSTD_isError(decompressedSize)) {
        free(dst);
        dstCapacity = 4 * 1024 * 1024;
        dst = malloc(dstCapacity);
        if (!dst) {
            if (error) *error = KWMakeError(KWErrorDecompression, @"Out of memory allocating retry buffer");
            return nil;
        }
        decompressedSize = ZSTD_decompress(dst, dstCapacity, bytes, length);
        if (ZSTD_isError(decompressedSize)) {
            const char *errStr = ZSTD_getErrorName ? ZSTD_getErrorName(decompressedSize) : "Unknown Zstd error";
            NSString *msg = [NSString stringWithUTF8String:errStr ? errStr : "Unknown Zstd error"];
            free(dst);
            if (error) *error = KWMakeError(KWErrorDecompression, msg);
            return nil;
        }
    }

    return [NSData dataWithBytesNoCopy:dst length:decompressedSize freeWhenDone:YES];
}

@end
