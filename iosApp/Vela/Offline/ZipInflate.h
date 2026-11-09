#ifndef VELA_ZIP_INFLATE_H
#define VELA_ZIP_INFLATE_H

#include <stdint.h>

/** Streams one stored or raw-deflate ZIP entry and checks its size and CRC-32. */
int VelaInflateZipEntry(
    const char *archivePath,
    uint64_t dataOffset,
    uint64_t compressedSize,
    uint64_t uncompressedSize,
    uint32_t expectedCrc32,
    int method,
    const char *outputPath);

#endif
