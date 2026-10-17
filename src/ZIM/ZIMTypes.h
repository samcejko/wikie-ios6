// OpenZIM Binary Format Definitions
#ifndef ZIM_TYPES_H
#define ZIM_TYPES_H

#import <Foundation/Foundation.h>

#define ZIM_MAGIC 0x044D495A
#define ZIM_HEADER_SIZE 80
#define ZIM_REDIRECT_MIMETYPE 0xFFFF
#define ZIM_INVALID_INDEX 0xFFFFFFFF

typedef NS_ENUM(uint8_t, ZIMCompressionType) {
    ZIMCompressionTypeDefault = 0,
    ZIMCompressionTypeNone    = 1,
    ZIMCompressionTypeZlib    = 2,
    ZIMCompressionTypeBzip2   = 3,
    ZIMCompressionTypeLzma    = 4,
    ZIMCompressionTypeZstd    = 5
};

#pragma pack(push, 1)
typedef struct {
    uint32_t magicNumber;     // offset 0  (4 bytes) 0x044D495A
    uint16_t majorVersion;    // offset 4  (2 bytes) 5 or 6
    uint16_t minorVersion;    // offset 6  (2 bytes)
    uint8_t  uuid[16];        // offset 8  (16 bytes)
    uint32_t articleCount;    // offset 24 (4 bytes)
    uint32_t clusterCount;    // offset 28 (4 bytes)
    uint64_t urlPtrPos;       // offset 32 (8 bytes) pointer to 64-bit URL directory offsets
    uint64_t titlePtrPos;     // offset 40 (8 bytes) pointer to 32-bit URL indices ordered by title
    uint64_t clusterPtrPos;   // offset 48 (8 bytes) pointer to 64-bit cluster offsets
    uint64_t mimeListPos;     // offset 56 (8 bytes) pointer to MIME table strings
    uint32_t mainPage;        // offset 64 (4 bytes) index of main page in URL list (or 0xFFFFFFFF)
    uint32_t layoutPage;      // offset 68 (4 bytes) index of layout page (or 0xFFFFFFFF)
    uint64_t checksumPos;     // offset 72 (8 bytes) pointer to 16-byte MD5 checksum near EOF
} ZIMHeaderRaw;
#pragma pack(pop)

#endif // ZIM_TYPES_H
