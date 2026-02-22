///|
pub struct CompressOptions {
  level : Int
  checksum : Bool
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
  {
    ..options,
    target_compressed_block_size: if options.target_compressed_block_size > 0 {
      options.target_compressed_block_size
    } else {
      0
    },
  }
}
