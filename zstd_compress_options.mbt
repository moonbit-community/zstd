///|
pub struct CompressOptions {
  level : Int
  checksum : Bool
  single_segment : Bool
  write_content_size : Bool
  compact_frame_header : Bool
  window_log : Int
  enable_long_distance_matching : Bool
  target_compressed_block_size : Int
}

///|
pub fn default_compress_options(
  level? : Int = 3,
  checksum? : Bool = false,
) -> CompressOptions {
  {
    level,
    checksum,
    single_segment: true,
    write_content_size: true,
    compact_frame_header: false,
    window_log: 0,
    enable_long_distance_matching: false,
    target_compressed_block_size: 0,
  }
}

///|
pub fn CompressOptions::with_level(
  self : CompressOptions,
  level : Int,
) -> CompressOptions {
  { ..self, level, }
}

///|
pub fn CompressOptions::with_checksum(
  self : CompressOptions,
  checksum : Bool,
) -> CompressOptions {
  { ..self, checksum, }
}

///|
pub fn CompressOptions::with_single_segment(
  self : CompressOptions,
  enabled : Bool,
) -> CompressOptions {
  { ..self, single_segment: enabled }
}

///|
pub fn CompressOptions::with_content_size(
  self : CompressOptions,
  enabled : Bool,
) -> CompressOptions {
  { ..self, write_content_size: enabled }
}

///|
pub fn CompressOptions::with_compact_frame_header(
  self : CompressOptions,
  enabled : Bool,
) -> CompressOptions {
  { ..self, compact_frame_header: enabled }
}

///|
pub fn CompressOptions::with_window_log(
  self : CompressOptions,
  log : Int,
) -> CompressOptions {
  { ..self, window_log: log }
}

///|
pub fn CompressOptions::with_long_distance_matching(
  self : CompressOptions,
  enabled : Bool,
) -> CompressOptions {
  { ..self, enable_long_distance_matching: enabled }
}

///|
pub fn CompressOptions::with_target_compressed_block_size(
  self : CompressOptions,
  size : Int,
) -> CompressOptions {
  { ..self, target_compressed_block_size: size }
}

///|
fn normalize_compress_options(options : CompressOptions) -> CompressOptions {
  let single_segment = options.single_segment
  let write_content_size = if single_segment {
    true
  } else {
    options.write_content_size
  }
  {
    ..options,
    single_segment,
    write_content_size,
    window_log: if options.window_log > 0 {
      options.window_log
    } else {
      0
    },
    target_compressed_block_size: if options.target_compressed_block_size > 0 {
      options.target_compressed_block_size
    } else {
      0
    },
  }
}
