///|
fn hash4_bytes(src : Bytes, pos : Int) -> Int {
  let v : UInt = src[pos].to_uint() +
    (src[pos + 1].to_uint() << 8) +
    (src[pos + 2].to_uint() << 16) +
    (src[pos + 3].to_uint() << 24)
  let x = v * (2654435761 : UInt)
  ((x >> 17) & (((1 : UInt) << 15) - (1 : UInt))).reinterpret_as_int()
}

///|
fn try_encode_common_offset_symbol(
  values : Array[Int],
) -> (Bool, UInt, Array[UInt], Int) raise ZstdError {
  let mut code = 2
  while code <= 31 {
    let base = offset_base_from_code(code.reinterpret_as_uint())
    let base_u = base.to_uint64()
    let span = ((1 : UInt64) << code) - (1 : UInt64)
    let limit = base_u + span
    let extras : Array[UInt] = Array::new()
    let mut ok = true
    let mut i = 0
    while i < values.length() {
      let v = values[i]
      if v <= 0 {
        ok = false
        i = values.length()
      } else {
        let vu = v.to_uint64()
        if vu < base_u || vu > limit {
          ok = false
          i = values.length()
        } else {
          extras.push((vu - base_u).to_uint())
          i = i + 1
        }
      }
    }
    if ok {
      return (true, code.reinterpret_as_uint(), extras, code)
    }
    code = code + 1
  }
  (false, 0, Array::new(), 0)
}

///|
fn try_encode_common_offset_symbol_with_repcodes(
  values : Array[Int],
  literal_lengths : Array[Int],
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (Bool, UInt, Array[UInt], Int) raise ZstdError {
  if values.length() != literal_lengths.length() {
    return (false, 0, Array::new(), 0)
  }

  let extras_code0 : Array[UInt] = Array::new()
  let mut ok_code0 = true
  let mut i = 0
  while i < values.length() {
    let ll = literal_lengths[i]
    let off = values[i]
    let expected = if ll == 0 { rep2 } else { rep1 }
    if off != expected {
      ok_code0 = false
      i = values.length()
    } else {
      extras_code0.push((0 : UInt))
      i = i + 1
    }
  }
  if ok_code0 {
    return (true, 0, extras_code0, 0)
  }

  let extras_code1 : Array[UInt] = Array::new()
  let mut ok_code1 = true
  i = 0
  while i < values.length() {
    let ll = literal_lengths[i]
    let off = values[i]
    if ll == 0 {
      if off == rep3 {
        extras_code1.push((0 : UInt))
      } else if rep1 > 1 && off == rep1 - 1 {
        extras_code1.push((1 : UInt))
      } else {
        ok_code1 = false
        i = values.length()
      }
    } else if off == rep2 {
      extras_code1.push((0 : UInt))
    } else if off == rep3 {
      extras_code1.push((1 : UInt))
    } else {
      ok_code1 = false
      i = values.length()
    }
    if ok_code1 {
      i = i + 1
    }
  }
  if ok_code1 {
    return (true, 1, extras_code1, 1)
  }

  try_encode_common_offset_symbol(values)
}

///|
fn collect_greedy_sequences(
  src : Bytes,
  start : Int,
  block_len : Int,
  ll_values : Array[Int],
  off_values : Array[Int],
  ml_values : Array[Int],
  max_sequences : Int,
  history? : Bytes = b"",
  search_depth? : Int = 1,
  max_match_offset? : Int = 0,
) -> Unit {
  let history_len = history.length()
  let virtual_len = history_len + block_len
  let hash_head : Array[Int] = Array::make(1 << 15, -1)
  let chain : Array[Int] = Array::make(virtual_len, -1)
  if history_len >= 4 {
    let mut dict_pos = 0
    while dict_pos + 4 <= history_len {
      let h = hash4_bytes(history, dict_pos)
      chain[dict_pos] = hash_head[h]
      hash_head[h] = dict_pos
      dict_pos = dict_pos + 1
    }
  }
  let depth_limit0 = if search_depth > 0 { search_depth } else { 1 }
  let depth_limit = if depth_limit0 > 0 { depth_limit0 } else { 1 }
  let mut pos = 0
  let mut anchor = 0

  while pos + 4 <= block_len && ll_values.length() < max_sequences {
    let abs_pos = start + pos
    let h = hash4_bytes(src, abs_pos)
    let current_virtual = history_len + pos
    let prev_pos = hash_head[h]
    chain[current_virtual] = prev_pos
    hash_head[h] = current_virtual

    let mut matched = false
    let mut best_ml = 0
    let mut best_offset = 0
    let window_limit = history_len + pos
    let effective_max_offset = if max_match_offset > 0 &&
      max_match_offset < window_limit {
      max_match_offset
    } else {
      window_limit
    }
    let mut cand = prev_pos
    let mut depth = 0
    while cand >= 0 && depth < depth_limit {
      let offset = current_virtual - cand
      if offset > 0 &&
        offset <= effective_max_offset &&
        virtual_match_source_byte(history, src, start, history_len, cand) ==
        src[abs_pos] &&
        virtual_match_source_byte(history, src, start, history_len, cand + 1) ==
        src[abs_pos + 1] &&
        virtual_match_source_byte(history, src, start, history_len, cand + 2) ==
        src[abs_pos + 2] {
        let mut ml = 3
        while pos + ml < block_len &&
              virtual_match_source_byte(
                history,
                src,
                start,
                history_len,
                cand + ml,
              ) ==
              src[start + pos + ml] {
          ml = ml + 1
        }
        if ml > best_ml {
          best_ml = ml
          best_offset = offset
        }
      }
      cand = chain[cand]
      depth = depth + 1
    }
    if best_ml >= 3 {
      ll_values.push(pos - anchor)
      off_values.push(best_offset)
      ml_values.push(best_ml)
      let end_pos = pos + best_ml
      let mut update_pos = pos + 1
      while update_pos + 4 <= end_pos {
        let hu = hash4_bytes(src, start + update_pos)
        let uv = history_len + update_pos
        chain[uv] = hash_head[hu]
        hash_head[hu] = uv
        update_pos = update_pos + 1
      }
      pos = end_pos
      anchor = pos
      matched = true
    }
    if !matched {
      pos = pos + 1
    }
  }
}

///|
fn build_general_rle_payload(
  src : Bytes,
  start : Int,
  block_len : Int,
  level : Int,
  dictionary_history? : Bytes = b"",
  max_match_offset? : Int = 0,
  enable_long_distance_matching? : Bool = false,
  rep1? : Int = 1,
  rep2? : Int = 4,
  rep3? : Int = 8,
) -> Bytes raise ZstdError {
  if level < 11 || block_len < 32 {
    return b""
  }
  let ll_values : Array[Int] = Array::new()
  let off_values : Array[Int] = Array::new()
  let ml_values : Array[Int] = Array::new()
  let max_sequences = general_rle_sequence_cap(level, block_len)
  let search_depth = greedy_sequence_search_depth(
    level,
    block_len,
    enable_long_distance_matching~,
  )
  collect_greedy_sequences(
    src,
    start,
    block_len,
    ll_values,
    off_values,
    ml_values,
    max_sequences,
    history=dictionary_history,
    search_depth~,
    max_match_offset~,
  )
  let seq_count = ll_values.length()
  if seq_count == 0 {
    return b""
  }

  let (ll_ok, ll_code, ll_extras, ll_bits) = try_encode_common_symbol(
    sequence_symbol_literal_length, 35, ll_values,
  )
  if !ll_ok {
    return b""
  }
  let (off_ok, off_code, off_extras, off_bits) = try_encode_common_offset_symbol_with_repcodes(
    off_values, ll_values, rep1, rep2, rep3,
  )
  if !off_ok {
    return b""
  }
  let (ml_ok, ml_code, ml_extras, ml_bits) = try_encode_common_symbol(
    sequence_symbol_match_length, 52, ml_values,
  )
  if !ml_ok {
    return b""
  }

  let literals : Array[Byte] = Array::new()
  let mut consumed = 0
  let mut i = 0
  while i < seq_count {
    let ll = ll_values[i]
    append_bytes(literals, src, start + consumed, ll)
    consumed = consumed + ll + ml_values[i]
    i = i + 1
  }
  if consumed > block_len {
    return b""
  }
  let tail_len = block_len - consumed
  if tail_len > 0 {
    append_bytes(literals, src, start + consumed, tail_len)
  }

  let extra_bits : Array[Int] = Array::new()
  i = 0
  while i < seq_count {
    append_bits_be(extra_bits, off_extras[i], off_bits)
    append_bits_be(extra_bits, ml_extras[i], ml_bits)
    append_bits_be(extra_bits, ll_extras[i], ll_bits)
    i = i + 1
  }
  let bitstream = build_reverse_bitstream(extra_bits)

  let payload : Array[Byte] = Array::new()
  append_best_literals_section(payload, Bytes::from_array(literals))
  append_sequence_count(payload, seq_count)
  payload.push((0x54 : UInt).to_byte()) // all RLE sequence modes
  payload.push(ll_code.to_byte())
  payload.push(off_code.to_byte())
  payload.push(ml_code.to_byte())
  append_bytes(payload, bitstream, 0, bitstream.length())
  Bytes::from_array(payload)
}

///|
fn virtual_match_source_byte(
  history : Bytes,
  src : Bytes,
  start : Int,
  history_len : Int,
  virtual_pos : Int,
) -> Byte {
  if virtual_pos < history_len {
    history[virtual_pos]
  } else {
    src[start + virtual_pos - history_len]
  }
}
