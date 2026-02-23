///|
/// Pinned upstream source:
/// - Repo: https://github.com/facebook/zstd
/// - Tag:  v1.5.7
/// - Commit: f8745da6ff1ad1e7bab384bd1f9d742439278e99
let max_input_size : UInt64 = 0xFF00FF00FF00FF00

///|
let small_input_cutoff : UInt64 = (128 : UInt64) << 10

///|
let zstd_magic_number : UInt = 0xFD2FB528

///|
let skippable_magic_start : UInt = 0x184D2A50

///|
let skippable_magic_mask : UInt = 0xFFFFFFF0

///|
let zstd_block_size_max : UInt64 = (128 : UInt64) << 10

///|
pub suberror ZstdError {
  SrcSizeTooLarge(UInt64)
  SrcSizeWrong
  CorruptionDetected
  BoundOverflow
  DictionaryRequired(UInt)
  UnsupportedFeature(String)
}

///|
/// MoonBit equivalent of `ZSTD_COMPRESSBOUND(srcSize)` in upstream `zstd.h`.
pub fn compress_bound_macro(src_size : UInt64) -> UInt64 {
  if src_size >= max_input_size {
    0
  } else {
    let margin = if src_size < small_input_cutoff {
      (small_input_cutoff - src_size) >> 11
    } else {
      (0 : UInt64)
    }
    src_size + (src_size >> 8) + margin
  }
}

///|
/// MoonBit equivalent of `ZSTD_compressBound(srcSize)`.
/// Upstream C returns an error code for `srcSize >= ZSTD_MAX_INPUT_SIZE`.
/// This port raises a typed error instead.
pub fn compress_bound(src_size : UInt64) -> UInt64 raise ZstdError {
  if src_size >= max_input_size {
    raise SrcSizeTooLarge(src_size)
  }
  compress_bound_macro(src_size)
}

///|
/// Pure MoonBit one-shot compressor.
/// Current subset: emits valid zstd frames with raw/rle blocks and a minimal
/// compressed-block path for periodic payloads at higher levels.
pub fn compress(
  src : Bytes,
  level? : Int = 3,
  checksum? : Bool = false,
) -> Bytes raise ZstdError {
  compress_with_options(src, default_compress_options(level~, checksum~))
}

///|
/// Pure MoonBit one-shot compressor with optional dictionary history.
/// If `dictionary` is a standard zstd dictionary blob, frame header dictID
/// is emitted from dictionary metadata. Raw prefix dictionaries emit no dictID.
pub fn compress_with_dictionary(
  src : Bytes,
  dictionary : Bytes,
  level? : Int = 3,
  checksum? : Bool = false,
) -> Bytes raise ZstdError {
  compress_with_dictionary_and_options(
    src,
    dictionary,
    default_compress_options(level~, checksum~),
  )
}

///|
/// Pure MoonBit one-shot compressor with structured encoding options.
pub fn compress_with_options(
  src : Bytes,
  options : CompressOptions,
) -> Bytes raise ZstdError {
  compress_with_dictionary_and_options(src, b"", options)
}

///|
/// Pure MoonBit one-shot compressor with dictionary history and options.
pub fn compress_with_dictionary_and_options(
  src : Bytes,
  dictionary : Bytes,
  options : CompressOptions,
) -> Bytes raise ZstdError {
  let normalized_options = normalize_compress_options(options)
  let src_len = src.length()
  if src_len.to_uint64() >= max_input_size {
    raise SrcSizeTooLarge(src_len.to_uint64())
  }
  let out : Array[Byte] = Array::new()
  let dictionary_state = parse_dictionary_state(dictionary)
  let use_compact_frame_header = normalized_options.compact_frame_header ||
    (
      dictionary_state.history.length() > 0 &&
      normalized_options.single_segment &&
      normalized_options.write_content_size
    )
  let max_window_size = if normalized_options.single_segment {
    (0 : UInt64)
  } else {
    let descriptor = frame_header_window_descriptor(
      src_len,
      normalized_options.window_log,
    )
    window_size_from_descriptor(descriptor)
  }

  append_frame_header(
    out,
    src_len,
    normalized_options.checksum,
    dictionary_id=dictionary_state.dict_id,
    single_segment=normalized_options.single_segment,
    write_content_size=normalized_options.write_content_size,
    compact_frame_header=use_compact_frame_header,
    window_log=normalized_options.window_log,
  )

  if src_len == 0 {
    // last=1, blockType=raw(0), blockSize=0
    append_u24_le(out, 1)
    if normalized_options.checksum {
      append_frame_checksum(out, src)
    }
    return Bytes::from_array(out)
  }

  append_frame_blocks_minimal(
    out,
    src,
    normalized_options.level,
    dictionary_state~,
    enable_long_distance_matching=normalized_options.enable_long_distance_matching,
    target_compressed_block_size=normalized_options.target_compressed_block_size,
    max_window_size~,
  )
  if normalized_options.checksum {
    append_frame_checksum(out, src)
  }

  Bytes::from_array(out)
}

///|
/// Pure MoonBit one-shot decompressor.
/// Supports concatenated frames and skippable frames.
pub fn decompress(src : Bytes) -> Bytes raise ZstdError {
  let out : Array[Byte] = Array::new()
  let mut pos = 0
  let src_len = src.length()
  while pos < src_len {
    let next = decode_frame_into(src, pos, out)
    if next <= pos {
      raise CorruptionDetected
    }
    pos = next
  }
  Bytes::from_array(out)
}

///|
/// Pure MoonBit one-shot decompressor with raw dictionary/prefix history.
pub fn decompress_with_dictionary(
  src : Bytes,
  dictionary : Bytes,
) -> Bytes raise ZstdError {
  let out : Array[Byte] = Array::new()
  let mut pos = 0
  let src_len = src.length()
  while pos < src_len {
    let next = decode_frame_into_with_dictionary(src, pos, out, dictionary)
    if next <= pos {
      raise CorruptionDetected
    }
    pos = next
  }
  Bytes::from_array(out)
}

///|
/// MoonBit equivalent of `ZSTD_decompressBound(src, srcSize)`.
/// Supports concatenated zstd frames and skippable frames.
pub fn decompress_bound(src : Bytes) -> UInt64 raise ZstdError {
  let src_len = src.length()
  let mut pos = 0
  let mut bound : UInt64 = 0
  while pos < src_len {
    let (frame_size, frame_bound) = parse_frame_size_info(src, pos)
    if frame_size <= 0 {
      raise CorruptionDetected
    }
    let next_bound = bound + frame_bound
    if next_bound < bound {
      raise BoundOverflow
    }
    bound = next_bound
    pos = pos + frame_size
  }
  bound
}
