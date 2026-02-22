# zstd Migration Notes

## Scope

This project migrates `facebook/zstd` to MoonBit incrementally.

Pinned upstream:

- Repo: `https://github.com/facebook/zstd`
- Tag: `v1.5.7`
- Commit: `f8745da6ff1ad1e7bab384bd1f9d742439278e99`

## Compatibility Goal

- Long-term: behavioral parity for core frame compression/decompression APIs.
- Near-term: pure MoonBit core subset first, driven by upstream tests/vectors.

## Implemented (Pure MoonBit)

- `compress_bound_macro` and `compress_bound` behavior.
- `decompress_bound(Bytes)` with:
  - zstd frame parsing
  - skippable frame handling
  - concatenated frame accumulation
  - unknown content-size upper-bound logic
- One-shot codec subset:
  - `compress(Bytes)` writing raw/rle-block zstd frames
  - high-level (`level >= 10`) pure-MoonBit path can emit minimal compressed
    blocks for repeated-prefix payloads with period `2..64` using one-sequence
    RLE-table encoding, and may keep a literal tail in the same block
    (no C dependency).
  - very-high-level (`level >= 18`) path can emit multi-sequence (`2..4`)
    variants of this periodic-prefix subset.
  - `decompress(Bytes)` supporting:
    - raw and rle block decoding
    - compressed blocks with literals:
      - raw/rle
      - compressed literals with direct Huffman weights
      - compressed literals with FSE-compressed Huffman weights
      - treeless literals reusing previous Huffman tree
      - single-stream and 4-stream Huffman literals
    - sequence modes:
      - RLE
      - Predefined
      - FSE compressed
      - Repeat (reusing previous sequence tables)
    - reverse bitstream parsing for sequence extra bits
    - frame checksum validation (XXH64 low 32 bits)
- Streaming decode subset:
  - `new_decompressor()` / `push()` / `pull()` / `finish()` for incremental
    one-shot-equivalent decompression over chunked input.
  - Supports concatenated frames and skippable frames in streamed input.
- Streaming encode subset:
  - `new_compressor()` / `push()` / `pull()` / `finish()` for incremental
    chunk collection and pure-MoonBit frame emission.
- Dictionary-backed decode subset:
  - `decompress_with_dictionary(src, dictionary)` and
    `new_decompressor_with_dictionary(dictionary)` support:
    - raw dictionary/prefix history
    - standard zstd dictionary blobs (`magic + dictID + entropy prelude +
      rep offsets + content`) in pure MoonBit.
  - reverse sequence bitstream decoding now matches real zstd vector behavior
    for dictionary-compressed frames.
  - repcode handling for the `ofBits == 1` path is aligned with upstream
    semantics (improves high-compression dictionary vector compatibility).
- Added real non-dictionary zstd CLI vectors (`-1`, `-19`, `--long=27`,
  `--no-check -9`) to continuously validate decompression parity.

## Intentional Delta / Remaining Gaps

- Upstream C error-code style is mapped to MoonBit typed errors via `raise`.
- Full upstream dictionary compatibility remains incremental; some
  dictionary-compressed frames may still be rejected in this subset.

## Next Slices

1. Port more golden vectors and fuzz-derived regression cases for FSE-compressed sequence sections.
2. Expand dictionary-compressed frame compatibility with more upstream/fuzzer vectors.
