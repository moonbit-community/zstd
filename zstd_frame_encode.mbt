///|
fn append_frame_header(
  out : Array[Byte],
  src_len : Int,
  checksum : Bool,
) -> Unit {
  append_u32_le(out, zstd_magic_number)
  // FCS flag=2 (4-byte size), single-segment=1, optional checksum, no dict.
  let descriptor = if checksum { (0xA4 : UInt) } else { (0xA0 : UInt) }
  out.push(descriptor.to_byte())
  append_u32_le(out, src_len.reinterpret_as_uint())
}

///|
fn append_frame_checksum(
  out : Array[Byte],
  src : Bytes,
) -> Unit raise ZstdError {
  let checksum32 = (xxh64(src) & (0xFFFF_FFFF : UInt64)).to_uint()
  append_u32_le(out, checksum32)
}

///|
fn append_raw_block(
  out : Array[Byte],
  src : Bytes,
  start : Int,
  block_len : Int,
  last_block : Bool,
) -> Unit {
  let last_block_bit : UInt = if last_block { 1 } else { 0 }
  let block_type_raw : UInt = 0
  let block_header : UInt = (block_len.reinterpret_as_uint() << 3) +
    (block_type_raw << 1) +
    last_block_bit
  append_u24_le(out, block_header)
  append_bytes(out, src, start, block_len)
}

///|
fn append_rle_block(
  out : Array[Byte],
  value : Byte,
  block_len : Int,
  last_block : Bool,
) -> Unit {
  let last_block_bit : UInt = if last_block { 1 } else { 0 }
  let block_type_rle : UInt = 1
  let block_header : UInt = (block_len.reinterpret_as_uint() << 3) +
    (block_type_rle << 1) +
    last_block_bit
  append_u24_le(out, block_header)
  out.push(value)
}

///|
fn is_rle_block(src : Bytes, start : Int, block_len : Int) -> Bool {
  if block_len <= 1 {
    return false
  }
  let first = src[start]
  let mut i = 1
  while i < block_len {
    if src[start + i] != first {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn append_frame_blocks_minimal(
  out : Array[Byte],
  src : Bytes,
  level : Int,
) -> Unit raise ZstdError {
  let src_len = src.length()
  let prev_rle_valid : Ref[Bool] = { val: false }
  let prev_predefined_valid : Ref[Bool] = { val: false }
  let prev_ll_code : Ref[UInt] = { val: 0 }
  let prev_off_code : Ref[UInt] = { val: 0 }
  let prev_ml_code : Ref[UInt] = { val: 0 }
  let mut pos = 0
  while pos < src_len {
    let remaining = src_len - pos
    let block_len = if remaining > 128 << 10 { 128 << 10 } else { remaining }
    let last_block = pos + block_len == src_len
    if is_rle_block(src, pos, block_len) {
      append_rle_block(out, src[pos], block_len, last_block)
    } else if level >= 10 &&
      append_compressed_repeat_block(
        out, src, pos, block_len, last_block, level, prev_rle_valid, prev_ll_code,
        prev_off_code, prev_ml_code, prev_predefined_valid,
      ) {
      ()
    } else {
      append_raw_block(out, src, pos, block_len, last_block)
    }
    pos = pos + block_len
  }
}
