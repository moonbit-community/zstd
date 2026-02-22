///|
fn parse_frame_size_info(
  src : Bytes,
  start : Int,
) -> (Int, UInt64) raise ZstdError {
  let src_len = src.length()
  ensure_range(src_len, start, 4)
  let magic = read_u32_le(src, start)
  if (magic & skippable_magic_mask) == skippable_magic_start {
    ensure_range(src_len, start, 8)
    let user_size = read_u32_le(src, start + 4).to_uint64()
    let frame_size = user_size + (8 : UInt64)
    let remaining = (src_len - start).to_uint64()
    if frame_size > remaining {
      raise SrcSizeWrong
    }
    (frame_size.to_int(), (0 : UInt64))
  } else if magic != zstd_magic_number {
    raise CorruptionDetected
  } else {
    ensure_range(src_len, start, 5)
    let descriptor = src[start + 4].to_uint()
    if ((descriptor >> 3) & 1) == 1 {
      raise CorruptionDetected
    }

    let frame_content_size_flag = descriptor >> 6
    let single_segment = ((descriptor >> 5) & 1) == 1
    let checksum_flag = ((descriptor >> 2) & 1) == 1
    let dict_id_flag = descriptor & 0x3

    let mut pos = start + 5
    let mut block_size_max = zstd_block_size_max
    if !single_segment {
      ensure_range(src_len, pos, 1)
      let window_size = window_size_from_descriptor(src[pos].to_uint())
      block_size_max = min_u64(window_size, zstd_block_size_max)
      pos = pos + 1
    }

    let dict_size = dict_id_size(dict_id_flag)
    ensure_range(src_len, pos, dict_size)
    pos = pos + dict_size

    let fcs_size = frame_content_size_size(
      frame_content_size_flag, single_segment,
    )
    ensure_range(src_len, pos, fcs_size)

    let mut has_content_size = false
    let mut content_size : UInt64 = 0
    match fcs_size {
      0 => ()
      1 => {
        has_content_size = true
        content_size = src[pos].to_uint().to_uint64()
      }
      2 => {
        has_content_size = true
        content_size = src[pos].to_uint().to_uint64() +
          (src[pos + 1].to_uint().to_uint64() << 8) +
          (256 : UInt64)
      }
      4 => {
        has_content_size = true
        content_size = read_u32_le(src, pos).to_uint64()
      }
      8 => {
        has_content_size = true
        content_size = read_u64_le(src, pos)
      }
      _ => raise CorruptionDetected
    }
    pos = pos + fcs_size

    if single_segment {
      if !has_content_size {
        raise CorruptionDetected
      }
      block_size_max = min_u64(content_size, zstd_block_size_max)
    }

    let mut nb_blocks : UInt64 = 0
    let mut last_block = false
    while !last_block {
      ensure_range(src_len, pos, 3)
      let block_header : UInt = src[pos].to_uint() +
        (src[pos + 1].to_uint() << 8) +
        (src[pos + 2].to_uint() << 16)
      pos = pos + 3

      last_block = (block_header & 1) == 1
      let block_type = (block_header >> 1) & 0x3
      let block_size = (block_header >> 3).to_uint64()
      let c_block_size = match block_type {
        0 => block_size
        1 => (1 : UInt64)
        2 => block_size
        _ => raise CorruptionDetected
      }

      let remaining = (src_len - pos).to_uint64()
      if c_block_size > remaining {
        raise SrcSizeWrong
      }
      pos = pos + c_block_size.to_int()
      nb_blocks = nb_blocks + 1
    }

    if checksum_flag {
      ensure_range(src_len, pos, 4)
      pos = pos + 4
    }

    let frame_bound = if has_content_size {
      content_size
    } else {
      nb_blocks * block_size_max
    }
    (pos - start, frame_bound)
  }
}

///|
fn window_size_from_descriptor(descriptor : UInt) -> UInt64 {
  let exponent = descriptor >> 3
  let mantissa = descriptor & 0x7
  let window_log = 10 + exponent.reinterpret_as_int()
  let window_base = (1 : UInt64) << window_log
  let window_add = (window_base >> 3) * mantissa.to_uint64()
  window_base + window_add
}

///|
fn frame_content_size_size(flag : UInt, single_segment : Bool) -> Int {
  if flag == 0 {
    if single_segment {
      1
    } else {
      0
    }
  } else if flag == 1 {
    2
  } else if flag == 2 {
    4
  } else {
    8
  }
}

///|
fn dict_id_size(flag : UInt) -> Int {
  if flag == 0 {
    0
  } else if flag == 1 {
    1
  } else if flag == 2 {
    2
  } else {
    4
  }
}
