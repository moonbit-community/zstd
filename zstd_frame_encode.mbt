///|
fn append_frame_header(
  out : Array[Byte],
  src_len : Int,
  checksum : Bool,
  dictionary_id? : UInt = 0,
  single_segment? : Bool = true,
  write_content_size? : Bool = true,
  compact_frame_header? : Bool = false,
  window_log? : Int = 0,
) -> Unit {
  append_u32_le(out, zstd_magic_number)
  let checksum_bit : UInt = if checksum { 0x04 } else { 0 }
  let dict_flag = frame_header_dict_id_flag(dictionary_id)
  let (fcs_flag, fcs_size) = frame_header_fcs_layout(
    src_len, single_segment, write_content_size, compact_frame_header,
  )
  let descriptor = if single_segment {
    (fcs_flag << 6) + ((1 : UInt) << 5) + checksum_bit + dict_flag
  } else {
    (fcs_flag << 6) + checksum_bit + dict_flag
  }
  out.push(descriptor.to_byte())
  if !single_segment {
    out.push(frame_header_window_descriptor(src_len, window_log).to_byte())
  }
  append_frame_header_dict_id(out, dictionary_id, dict_flag)
  append_frame_content_size(out, src_len.to_uint64(), fcs_size)
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
fn frame_header_window_descriptor(src_len : Int, window_log : Int) -> UInt {
  let target = if window_log > 0 {
    let clamped_log = if window_log < 10 {
      10
    } else if window_log > 41 {
      41
    } else {
      window_log
    }
    (1 : UInt64) << clamped_log
  } else {
    let src_u = src_len.to_uint64()
    if src_u < (1 : UInt64) << 10 {
      (1 : UInt64) << 10
    } else {
      src_u
    }
  }
  let mut exp = 0
  while exp <= 31 {
    let base = (1 : UInt64) << (10 + exp)
    let step = base >> 3
    let mut mant = 0
    while mant <= 7 {
      let window_size = base + step * mant.to_uint64()
      if window_size >= target {
        return (exp.reinterpret_as_uint() << 3) + mant.reinterpret_as_uint()
      }
      mant = mant + 1
    }
    exp = exp + 1
  }
  0xFF
}

///|
fn frame_header_fcs_layout(
  src_len : Int,
  single_segment : Bool,
  write_content_size : Bool,
  compact_frame_header : Bool,
) -> (UInt, Int) {
  let src_len_u = src_len.to_uint64()
  if single_segment {
    if compact_frame_header {
      if src_len_u <= 0xFF {
        (0, 1)
      } else if src_len_u <= 0x101FF {
        (1, 2)
      } else {
        (2, 4)
      }
    } else {
      (2, 4)
    }
  } else if !write_content_size {
    (0, 0)
  } else if compact_frame_header && src_len_u >= 0x100 && src_len_u <= 0x101FF {
    (1, 2)
  } else {
    (2, 4)
  }
}

///|
fn append_frame_content_size(
  out : Array[Byte],
  src_len : UInt64,
  fcs_size : Int,
) -> Unit {
  if fcs_size == 0 {
    return
  }
  if fcs_size == 1 {
    out.push(src_len.to_uint().to_byte())
    return
  }
  if fcs_size == 2 {
    let adjusted = src_len - (256 : UInt64)
    out.push((adjusted.to_uint() & 0xFF).to_byte())
    out.push(((adjusted.to_uint() >> 8) & 0xFF).to_byte())
    return
  }
  append_u32_le(out, src_len.to_uint())
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
  let sim_out : Array[Byte] = Array::new()
  let mut sim_rep1 = dictionary_state.rep1
  let mut sim_rep2 = dictionary_state.rep2
  let mut sim_rep3 = dictionary_state.rep3
  let sim_prev_huf_valid : Ref[Bool] = { val: dictionary_state.huf_valid }
  let sim_prev_huf_max_bits : Ref[Int] = { val: dictionary_state.huf_max_bits }
  let sim_prev_huf_left : Ref[Array[Int]] = { val: dictionary_state.huf_left }
  let sim_prev_huf_right : Ref[Array[Int]] = { val: dictionary_state.huf_right }
  let sim_prev_huf_symbol : Ref[Array[Int]] = {
    val: dictionary_state.huf_symbol,
  }
  let sim_prev_ll_valid : Ref[Bool] = { val: dictionary_state.ll_valid }
  let sim_prev_ll_kind : Ref[Int] = { val: dictionary_state.ll_kind }
  let sim_prev_ll_code : Ref[UInt] = { val: dictionary_state.ll_code }
  let sim_prev_ll_table_log : Ref[Int] = { val: dictionary_state.ll_table_log }
  let sim_prev_ll_table_next_state : Ref[Array[Int]] = {
    val: dictionary_state.ll_table_next_state,
  }
  let sim_prev_ll_table_nb_add_bits : Ref[Array[Int]] = {
    val: dictionary_state.ll_table_nb_add_bits,
  }
  let sim_prev_ll_table_nb_bits : Ref[Array[Int]] = {
    val: dictionary_state.ll_table_nb_bits,
  }
  let sim_prev_ll_table_base_values : Ref[Array[Int]] = {
    val: dictionary_state.ll_table_base_values,
  }
  let sim_prev_off_valid : Ref[Bool] = { val: dictionary_state.off_valid }
  let sim_prev_off_kind : Ref[Int] = { val: dictionary_state.off_kind }
  let sim_prev_off_code : Ref[UInt] = { val: dictionary_state.off_code }
  let sim_prev_off_table_log : Ref[Int] = {
    val: dictionary_state.off_table_log,
  }
  let sim_prev_off_table_next_state : Ref[Array[Int]] = {
    val: dictionary_state.off_table_next_state,
  }
  let sim_prev_off_table_nb_add_bits : Ref[Array[Int]] = {
    val: dictionary_state.off_table_nb_add_bits,
  }
  let sim_prev_off_table_nb_bits : Ref[Array[Int]] = {
    val: dictionary_state.off_table_nb_bits,
  }
  let sim_prev_off_table_base_values : Ref[Array[Int]] = {
    val: dictionary_state.off_table_base_values,
  }
  let sim_prev_ml_valid : Ref[Bool] = { val: dictionary_state.ml_valid }
  let sim_prev_ml_kind : Ref[Int] = { val: dictionary_state.ml_kind }
  let sim_prev_ml_code : Ref[UInt] = { val: dictionary_state.ml_code }
  let sim_prev_ml_table_log : Ref[Int] = { val: dictionary_state.ml_table_log }
  let sim_prev_ml_table_next_state : Ref[Array[Int]] = {
    val: dictionary_state.ml_table_next_state,
  }
  let sim_prev_ml_table_nb_add_bits : Ref[Array[Int]] = {
    val: dictionary_state.ml_table_nb_add_bits,
  }
  let sim_prev_ml_table_nb_bits : Ref[Array[Int]] = {
    val: dictionary_state.ml_table_nb_bits,
  }
  let sim_prev_ml_table_base_values : Ref[Array[Int]] = {
    val: dictionary_state.ml_table_base_values,
  }
  let mut pos = 0
  while pos < src_len {
    let remaining = src_len - pos
    let block_len = if remaining > 128 << 10 { 128 << 10 } else { remaining }
    let last_block = pos + block_len == src_len
    let selected_payload : Ref[Bytes] = { val: b"" }
    let frame_history = if pos > 0 { src[:pos].to_bytes() } else { b"" }
    let compression_history = if dictionary_state.history.length() == 0 {
      frame_history
    } else if frame_history.length() == 0 {
      dictionary_state.history
    } else {
      dictionary_state.history + frame_history
    }
    if is_rle_block(src, pos, block_len) {
      append_rle_block(out, src[pos], block_len, last_block)
      let mut i = 0
      while i < block_len {
        sim_out.push(src[pos + i])
        i = i + 1
      }
    } else if level >= 10 &&
      append_compressed_repeat_block(
        out, src, pos, block_len, last_block, level, compression_history, sim_rep1,
        sim_rep2, sim_rep3, enable_long_distance_matching, target_compressed_block_size,
        prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
        prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header, prev_lit_huf_valid,
        prev_lit_huf_tree_desc, selected_payload,
      ) {
      let (next_pos, produced, next_rep1, next_rep2, next_rep3) = decode_compressed_block_minimal(
        selected_payload.val,
        0,
        selected_payload.val.length(),
        sim_out,
        0,
        dictionary_state.history,
        sim_rep1,
        sim_rep2,
        sim_rep3,
        sim_prev_huf_valid,
        sim_prev_huf_max_bits,
        sim_prev_huf_left,
        sim_prev_huf_right,
        sim_prev_huf_symbol,
        sim_prev_ll_valid,
        sim_prev_ll_kind,
        sim_prev_ll_code,
        sim_prev_ll_table_log,
        sim_prev_ll_table_next_state,
        sim_prev_ll_table_nb_add_bits,
        sim_prev_ll_table_nb_bits,
        sim_prev_ll_table_base_values,
        sim_prev_off_valid,
        sim_prev_off_kind,
        sim_prev_off_code,
        sim_prev_off_table_log,
        sim_prev_off_table_next_state,
        sim_prev_off_table_nb_add_bits,
        sim_prev_off_table_nb_bits,
        sim_prev_off_table_base_values,
        sim_prev_ml_valid,
        sim_prev_ml_kind,
        sim_prev_ml_code,
        sim_prev_ml_table_log,
        sim_prev_ml_table_next_state,
        sim_prev_ml_table_nb_add_bits,
        sim_prev_ml_table_nb_bits,
        sim_prev_ml_table_base_values,
      )
      if next_pos != selected_payload.val.length() ||
        produced != block_len.to_uint64() {
        raise CorruptionDetected
      }
      let mut i = 0
      while i < block_len {
        if sim_out[sim_out.length() - block_len + i] != src[pos + i] {
          raise CorruptionDetected
        }
        i = i + 1
      }
      sim_rep1 = next_rep1
      sim_rep2 = next_rep2
      sim_rep3 = next_rep3
    } else {
      append_raw_block(out, src, pos, block_len, last_block)
      append_bytes(sim_out, src, pos, block_len)
    }
    pos = pos + block_len
  }
}
