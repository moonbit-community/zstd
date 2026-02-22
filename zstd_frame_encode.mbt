///|
fn append_frame_header(
  out : Array[Byte],
  src_len : Int,
  checksum : Bool,
  dictionary_id? : UInt = 0,
) -> Unit {
  append_u32_le(out, zstd_magic_number)
  // FCS flag=2 (4-byte size), single-segment=1, optional checksum, optional dictID.
  let dict_flag = frame_header_dict_id_flag(dictionary_id)
  let descriptor = (0xA0 : UInt) +
    (if checksum { (0x04 : UInt) } else { (0 : UInt) }) +
    dict_flag
  out.push(descriptor.to_byte())
  append_frame_header_dict_id(out, dictionary_id, dict_flag)
  append_u32_le(out, src_len.reinterpret_as_uint())
}

///|
fn frame_header_dict_id_flag(dict_id : UInt) -> UInt {
  if dict_id == 0 {
    0
  } else if dict_id <= 0xFF {
    1
  } else if dict_id <= 0xFFFF {
    2
  } else {
    3
  }
}

///|
fn append_frame_header_dict_id(
  out : Array[Byte],
  dict_id : UInt,
  dict_flag : UInt,
) -> Unit {
  if dict_flag == 1 {
    out.push(dict_id.to_byte())
  } else if dict_flag == 2 {
    out.push((dict_id & 0xFF).to_byte())
    out.push(((dict_id >> 8) & 0xFF).to_byte())
  } else if dict_flag == 3 {
    append_u32_le(out, dict_id)
  }
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
  dictionary_state? : DictionaryState = empty_dictionary_state(),
  enable_long_distance_matching? : Bool = false,
  target_compressed_block_size? : Int = 0,
) -> Unit raise ZstdError {
  let seed_has_sequence_headers = dictionary_state.ll_kind ==
    sequence_table_kind_compressed &&
    dictionary_state.off_kind == sequence_table_kind_compressed &&
    dictionary_state.ml_kind == sequence_table_kind_compressed &&
    dictionary_state.ll_header.length() > 0 &&
    dictionary_state.off_header.length() > 0 &&
    dictionary_state.ml_header.length() > 0
  let src_len = src.length()
  let prev_rle_valid : Ref[Bool] = { val: false }
  let prev_predefined_valid : Ref[Bool] = { val: false }
  let prev_compressed_valid : Ref[Bool] = { val: seed_has_sequence_headers }
  let prev_ll_code : Ref[UInt] = { val: 0 }
  let prev_off_code : Ref[UInt] = { val: 0 }
  let prev_ml_code : Ref[UInt] = { val: 0 }
  let prev_ll_header : Ref[Bytes] = { val: dictionary_state.ll_header }
  let prev_off_header : Ref[Bytes] = { val: dictionary_state.off_header }
  let prev_ml_header : Ref[Bytes] = { val: dictionary_state.ml_header }
  let prev_lit_huf_valid : Ref[Bool] = {
    val: dictionary_state.huf_valid &&
    dictionary_state.huf_tree_desc.length() > 0,
  }
  let prev_lit_huf_tree_desc : Ref[Bytes] = {
    val: dictionary_state.huf_tree_desc,
  }
  let mut pos = 0
  while pos < src_len {
    let remaining = src_len - pos
    let block_len = if remaining > 128 << 10 { 128 << 10 } else { remaining }
    let last_block = pos + block_len == src_len
    if is_rle_block(src, pos, block_len) {
      append_rle_block(out, src[pos], block_len, last_block)
    } else if level >= 10 &&
      append_compressed_repeat_block(
        out,
        src,
        pos,
        block_len,
        last_block,
        level,
        if pos == 0 {
          dictionary_state.history
        } else {
          b""
        },
        if pos == 0 {
          dictionary_state.rep1
        } else {
          1
        },
        if pos == 0 {
          dictionary_state.rep2
        } else {
          4
        },
        if pos == 0 {
          dictionary_state.rep3
        } else {
          8
        },
        enable_long_distance_matching,
        target_compressed_block_size,
        prev_rle_valid,
        prev_ll_code,
        prev_off_code,
        prev_ml_code,
        prev_predefined_valid,
        prev_compressed_valid,
        prev_ll_header,
        prev_off_header,
        prev_ml_header,
        prev_lit_huf_valid,
        prev_lit_huf_tree_desc,
      ) {
      ()
    } else {
      append_raw_block(out, src, pos, block_len, last_block)
    }
    pos = pos + block_len
  }
}
