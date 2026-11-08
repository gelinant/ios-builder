#include "ZipInflate.h"

#include <stdio.h>
#include <sys/types.h>
#include <string.h>
#include <zlib.h>

#define CHUNK 65536

static int copyStored(FILE *input, FILE *output, uint64_t remaining, uint32_t *crc) {
    unsigned char buffer[CHUNK];
    while (remaining > 0) {
        size_t want = remaining > CHUNK ? CHUNK : (size_t)remaining;
        size_t got = fread(buffer, 1, want, input);
        if (got == 0) return 10;
        if (fwrite(buffer, 1, got, output) != got) return 11;
        *crc = crc32(*crc, buffer, (uInt)got);
        remaining -= got;
    }
    return 0;
}

static int inflateEntry(FILE *input, FILE *output, uint64_t compressedSize,
                        uint64_t uncompressedSize, uint32_t *crc) {
    unsigned char in[CHUNK];
    unsigned char out[CHUNK];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -15) != Z_OK) return 20;

    uint64_t remaining = compressedSize;
    uint64_t written = 0;
    int status = Z_OK;
    int result = 0;
    while (status != Z_STREAM_END) {
        if (stream.avail_in == 0 && remaining > 0) {
            size_t want = remaining > CHUNK ? CHUNK : (size_t)remaining;
            size_t got = fread(in, 1, want, input);
            if (got == 0) { result = 21; break; }
            stream.next_in = in;
            stream.avail_in = (uInt)got;
            remaining -= got;
        }
        stream.next_out = out;
        stream.avail_out = CHUNK;
        status = inflate(&stream, Z_NO_FLUSH);
        if (status != Z_OK && status != Z_STREAM_END) { result = 22; break; }
        size_t produced = CHUNK - stream.avail_out;
        if (produced > 0) {
            if (written + produced > uncompressedSize) { result = 23; break; }
            if (fwrite(out, 1, produced, output) != produced) { result = 24; break; }
            *crc = crc32(*crc, out, (uInt)produced);
            written += produced;
        } else if (remaining == 0 && stream.avail_in == 0 && status != Z_STREAM_END) {
            result = 25;
            break;
        }
    }
    inflateEnd(&stream);
    if (result == 0 && status != Z_STREAM_END) result = 26;
    if (result == 0 && written != uncompressedSize) result = 27;
    return result;
}

int VelaInflateZipEntry(const char *archivePath, uint64_t dataOffset,
                        uint64_t compressedSize, uint64_t uncompressedSize,
                        uint32_t expectedCrc32, int method, const char *outputPath) {
    FILE *input = fopen(archivePath, "rb");
    if (input == NULL) return 1;
    FILE *output = NULL;
    int result = 0;
    uint32_t crc = crc32(0L, Z_NULL, 0);
    if (fseeko(input, (off_t)dataOffset, SEEK_SET) != 0) result = 2;
    if (result == 0) {
        output = fopen(outputPath, "wb");
        if (output == NULL) result = 3;
    }
    if (result == 0 && method == 0) {
        if (compressedSize != uncompressedSize) result = 4;
        else result = copyStored(input, output, compressedSize, &crc);
    } else if (result == 0 && method == 8) {
        result = inflateEntry(input, output, compressedSize, uncompressedSize, &crc);
    } else if (result == 0) {
        result = 5;
    }
    if (output != NULL && fflush(output) != 0 && result == 0) result = 6;
    if (output != NULL) fclose(output);
    fclose(input);
    if (result == 0 && crc != expectedCrc32) result = 7;
    if (result != 0) remove(outputPath);
    return result;
}
