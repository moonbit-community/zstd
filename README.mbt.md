# Milky2018/zstd

Pure MoonBit Zstandard library (incremental implementation).

## Import

```moonbit nocheck
// moon.pkg
import "Milky2018/zstd" @zstd
```

## Quick Start

```moonbit nocheck
let input = b"hello zstd"
let compressed = @zstd.compress(input)
let restored = @zstd.decompress(compressed)
assert_eq(restored, input)
```

## API

- `compress(src : Bytes, level? : Int = 3) -> Bytes raise ZstdError`
- `compress(src : Bytes, level? : Int = 3, checksum? : Bool = false) -> Bytes raise ZstdError`
- `compress_with_dictionary(src : Bytes, dictionary : Bytes, level? : Int = 3, checksum? : Bool = false) -> Bytes raise ZstdError`
- `decompress(src : Bytes) -> Bytes raise ZstdError`
- `decompress_with_dictionary(src : Bytes, dictionary : Bytes) -> Bytes raise ZstdError`
- `new_compressor(level? : Int = 3) -> Compressor`
- `new_compressor_with_dictionary(dictionary : Bytes, level? : Int = 3) -> Compressor`
- `Compressor::push(self, chunk : Bytes) -> Unit`
- `Compressor::pull(self) -> Bytes raise ZstdError`
- `Compressor::finish(self) -> Bytes raise ZstdError`
- `Compressor::pending_input(self) -> Int`
- `new_decompressor() -> Decompressor`
- `new_decompressor_with_dictionary(dictionary : Bytes) -> Decompressor`
- `Decompressor::push(self, chunk : Bytes) -> Unit`
- `Decompressor::pull(self) -> Bytes raise ZstdError`
- `Decompressor::finish(self) -> Bytes raise ZstdError`
- `Decompressor::pending_input(self) -> Int`
- `compress_bound_macro(src_size : UInt64) -> UInt64`
- `compress_bound(src_size : UInt64) -> UInt64 raise ZstdError`
- `decompress_bound(src : Bytes) -> UInt64 raise ZstdError`

## Current Support

- Compression:
  - emits valid zstd frames using raw/rle blocks
  - at higher levels (`level >= 10`), can emit compressed blocks for repeated-window payloads with short periods (`2..64`), including literal prefixes and tails (pure MoonBit subset)
  - at very high levels (`level >= 18`), may emit multi-sequence variants (`2..4` sequences) for this periodic-window subset
  - for prefixed periodic windows, multi-sequence encoding is attempted when symbols are representable; otherwise it falls back automatically
  - includes a generic non-periodic single-match compressed-block path (selected when periodic encoding is unavailable or not preferred)
  - supports dictionary-aware compression entrypoints:
    - `compress_with_dictionary` / `new_compressor_with_dictionary`
    - emits frame `dictID` for standard zstd dictionaries
    - can use dictionary history for first-block single-match encoding
- Decompression:
  - supports raw blocks and rle blocks
  - supports compressed blocks where:
    - literals section:
      - raw/rle
      - compressed literals with direct Huffman weights
      - compressed literals with FSE-compressed Huffman weights
      - treeless literals reusing previous Huffman tree
      - both single-stream and 4-stream Huffman literals
    - sequence modes are `RLE_Mode`, `Predefined_Mode`, `FSE_Compressed_Mode`, and `Repeat_Mode`
    - repeat mode reuses previously established RLE/predefined/FSE sequence tables
    - sequence bitstream is parsed in reverse for extra bits
    - offset code `<= 31`
    - literal length code `<= 35`, match length code `<= 52`
- Frame handling: supports concatenated frames and skippable frames.
- Frame checksum: validates XXH64-based 32-bit checksum when present.
- Streaming encode: stateful `Compressor` supports chunked input.
- Streaming decode: stateful `Decompressor` supports chunked input.
- Dictionary-backed decode:
  - raw dictionary/prefix history
  - standard zstd dictionary blobs (`magic + dictID + entropy prelude + rep offsets + content`)
  - verified against real `zstd` CLI dictionary-compressed vectors
  - verified across multiple compression modes (`-1/-9/-19`, check/no-check, long mode)

## Current Limitations

- Full upstream dictionary compatibility is still incremental; some complex dictionary-compressed frames may still be rejected.

## Error Handling

All fallible APIs raise `ZstdError`:

- `SrcSizeTooLarge(UInt64)`
- `SrcSizeWrong`
- `CorruptionDetected`
- `BoundOverflow`
- `UnsupportedFeature(String)`
