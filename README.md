# Wikie for iOS 6

Offline Wikipedia and OpenZIM reader for iOS 6.0 – 6.1.6 (ARMv7), crafted for jailbroken legacy devices.

Turn your vintage iPhone, iPod touch, or iPad into a completely self-contained offline encyclopedia.

---

## Features

- **Format Compatibility (v5 & v6)**:
  - Supports legacy ZIM archives (namespaced `A/`, `I/`, `-`) as well as modern unified path archives (openZIM v6).
  - Decompresses **Zstandard (`zstd`)**, **Deflate (`zlib`)**, and uncompressed clusters.
- **Blazingly Fast Offline Search**:
  - Direct binary search ($O(\log N)$) through the ZIM title index table.
  - Live prefix autocomplete suggestions as you type, with zero background indexing required.
- **Clean UIWebView Reader**:
  - Seamless offline rendering using a custom `zim://` `NSURLProtocol` handler.
  - Injected responsive reader stylesheet (`reader.css`) for readability on 3.5" and 4" Retina screens and iPads.
  - Reader appearance controls: **Light**, **Sepia**, and **Dark** night mode, with dynamic font resizing.
  - Bookmarks and reading history.
- **Adding Your Personal Collection**:
  - **iTunes File Sharing**: Drop `.zim` files directly into Kiwix via iTunes or Finder.
  - **Wi-Fi Transfer Server**: Built-in HTTP server allows uploading `.zim` files from any desktop browser on your local Wi-Fi network without cables.
  - **Jailbreak Storage**: Automatically discovers `.zim` files in `/var/mobile/Documents` and app documents.
- **In-App Downloader**:
  - Download featured mobile-friendly ZIM packages (Simple English, Czech mini, Wiktionary, Wikivoyage) or any direct HTTP/HTTPS `.zim` link.

---

## Supported Devices

- **iPhone**: iPhone 3GS, iPhone 4, iPhone 4S, iPhone 5
- **iPad**: iPad 1, iPad 2, iPad 3, iPad 4, iPad mini 1
- **iPod touch**: iPod touch 4th gen, iPod touch 5th gen
- **OS**: iOS 6.0 – 6.1.6 (jailbroken with Cydia / AppSync / Nitro JIT entitlement)

---

## Project Structure

```
kiwix-ios6/
├── Makefile                # Theos build configuration (target: iphone:clang:9.3:6.0)
├── control                 # Cydia deb package metadata
├── Resources/
│   ├── Info.plist          # Enables UIFileSharingEnabled, file associations
│   ├── entitlements.plist  # Enables dynamic-codesigning (Nitro JIT in UIWebView)
│   ├── reader.css          # Injected typography and Light/Sepia/Dark theme styles
│   └── *.lproj/            # English and Czech localizations
├── src/
│   ├── KWCommon.h / .m     # Shared utilities, logging and helpers
│   ├── KWAppDelegate.h / .m
│   ├── ZIM/
│   │   ├── ZIMTypes.h      # Binary format specification and structs
│   │   ├── ZIMEntry.h / .m  # Directory entry (content and redirects)
│   │   ├── ZIMCluster.h / .m # Cluster reader with zstd/zlib decompression
│   │   └── ZIMFile.h / .m   # 64-bit random access, binary search & LRU caching
│   ├── Protocol/
│   │   └── KWZIMURLProtocol.h / .m # Custom zim:// protocol for UIWebView
│   ├── Model/
│   │   ├── KWArchiveManager.h / .m # Scans Documents & handles active archive
│   │   └── KWBookmarkManager.h / .m # Bookmarks persistence
│   └── UI/
│       ├── Library/        # Archive list & empty state
│       ├── Search/         # Fast title prefix search with autocomplete
│       ├── Reader/         # Article viewing with toolbar and themes
│       ├── Catalog/        # In-app archive downloader
│       └── Server/         # Built-in Wi-Fi upload HTTP server
├── vendor/
│   ├── mbedtls_config_ios6.h # TLS 1.2/1.3 client config for iOS 6
│   └── mbedtls_glue.c      # Platform time & entropy glue
└── tools/
    ├── ipad.ps1            # Automated SSH installation to test iPad
    └── gh-build.ps1        # GitHub Actions build trigger
```

---

## Building

### Automated via GitHub Actions
Pushes and pull requests automatically trigger `.github/workflows/build.yml`, which compiles the armv7 `.deb` and `.ipa` packages.

### Local Build (with Theos)
```bash
export THEOS=/path/to/theos
make package FINALPACKAGE=1
```

### Deploying to Device
```powershell
. .\tools\ipad.ps1
Install-IPadDeb .\packages\com.samcejko.kiwix_1.0.0_iphoneos-arm.deb
```
