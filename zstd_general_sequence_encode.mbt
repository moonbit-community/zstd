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

  let (ok_code0, extras_code0) = simulate_common_repcode_code0(
    values, literal_lengths, rep1, rep2, rep3,
  )
  if ok_code0 {
    return (true, 0, extras_code0, 0)
  }

  let (ok_code1, extras_code1) = simulate_common_repcode_code1(
    values, literal_lengths, rep1, rep2, rep3,
  )
  if ok_code1 {
    return (true, 1, extras_code1, 1)
  }

  try_encode_common_offset_symbol(values)
}

///|
fn simulate_common_repcode_code0(
  values : Array[Int],
  literal_lengths : Array[Int],
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (Bool, Array[UInt]) {
  let extras : Array[UInt] = Array::new()
  let mut r1 = rep1
  let mut r2 = rep2
  ignore(rep3)
  let mut i = 0
  while i < values.length() {
    let ll0 = literal_lengths[i] == 0
    let expected = if ll0 { r2 } else { r1 }
    let off = values[i]
    if off <= 0 || off != expected {
      return (false, Array::new())
    }
    extras.push((0 : UInt))
    if ll0 {
      let old_r1 = r1
      let old_r2 = r2
      r1 = old_r2
      r2 = old_r1
    } else {
      r1 = expected
    }
    i = i + 1
  }
  (true, extras)
}

///|
fn simulate_common_repcode_code1(
  values : Array[Int],
  literal_lengths : Array[Int],
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (Bool, Array[UInt]) {
  let extras : Array[UInt] = Array::new()
  let mut r1 = rep1
  let mut r2 = rep2
  let mut r3 = rep3
  let mut i = 0
  while i < values.length() {
    let ll0 = literal_lengths[i] == 0
    let target = values[i]
    let mut matched = false
    let mut low = 0
    while low <= 1 && !matched {
      let offset_code = 1 + (if ll0 { 1 } else { 0 }) + low
      let (ok, decoded, nr1, nr2, nr3) = if offset_code == 1 {
        (r2 > 0, r2, r2, r1, r3)
      } else if offset_code == 2 {
        (r3 > 0, r3, r3, r1, r2)
      } else if offset_code == 3 {
        let v = r1 - 1
        (v > 0, v, v, r1, r2)
      } else {
        (false, 0, 0, 0, 0)
      }
      if ok && decoded == target {
        extras.push(low.reinterpret_as_uint())
        r1 = nr1
        r2 = nr2
        r3 = nr3
        matched = true
      } else {
        low = low + 1
      }
    }
    if !matched {
      return (false, Array::new())
    }
    i = i + 1
  }
  (true, extras)
}

///|
fn greedy_match_length_with_offset(
  history : Bytes,
  src : Bytes,
  start : Int,
  history_len : Int,
  pos : Int,
  block_len : Int,
  offset : Int,
) -> Int {
  if offset <= 0 {
    return 0
  }
  let current_virtual = history_len + pos
  let cand = current_virtual - offset
  if cand < 0 {
    return 0
  }
  if virtual_match_source_byte(history, src, start, history_len, cand) !=
    src[start + pos] {
    return 0
  }
  if pos + 1 >= block_len ||
    virtual_match_source_byte(history, src, start, history_len, cand + 1) !=
    src[start + pos + 1] {
    return 0
  }
  if pos + 2 >= block_len ||
    virtual_match_source_byte(history, src, start, history_len, cand + 2) !=
    src[start + pos + 2] {
    return 0
  }
  let mut ml = 3
  while pos + ml < block_len &&
        virtual_match_source_byte(history, src, start, history_len, cand + ml) ==
        src[start + pos + ml] {
    ml = ml + 1
  }
  ml
}

///|
fn update_repcodes_after_greedy_offset(
  ll0 : Bool,
  offset : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (Int, Int, Int) {
  if offset <= 0 {
    return (rep1, rep2, rep3)
  }
  if ll0 && offset == rep2 {
    return (rep2, rep1, rep3)
  }
  if !ll0 && offset == rep1 {
    return (rep1, rep2, rep3)
  }
  if offset == rep3 {
    return (rep3, rep1, rep2)
  }
  if ll0 && rep1 > 1 && offset == rep1 - 1 {
    return (rep1 - 1, rep1, rep2)
  }
  (offset, rep1, rep2)
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
  rep1? : Int = 1,
  rep2? : Int = 4,
  rep3? : Int = 8,
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
  let mut r1 = rep1
  let mut r2 = rep2
  let mut r3 = rep3

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
    let mut best_is_rep = false
    let mut best_rep_rank = 1 << 30
    let window_limit = history_len + pos
    let effective_max_offset = if max_match_offset > 0 &&
      max_match_offset < window_limit {
      max_match_offset
    } else {
      window_limit
    }
    let ll0 = pos == anchor

    let rep0 = if ll0 { r2 } else { r1 }
    if rep0 > 0 && rep0 <= effective_max_offset {
      let ml = greedy_match_length_with_offset(
        history, src, start, history_len, pos, block_len, rep0,
      )
      if ml >= 3 {
        best_ml = ml
        best_offset = rep0
        best_is_rep = true
        best_rep_rank = 0
      }
    }
    if r3 > 0 && r3 <= effective_max_offset {
      let ml = greedy_match_length_with_offset(
        history, src, start, history_len, pos, block_len, r3,
      )
      if ml >= 3 &&
        (ml > best_ml || (ml == best_ml && (!best_is_rep || 1 < best_rep_rank))) {
        best_ml = ml
        best_offset = r3
        best_is_rep = true
        best_rep_rank = 1
      }
    }
    if ll0 && r1 > 1 {
      let r1m1 = r1 - 1
      if r1m1 > 0 && r1m1 <= effective_max_offset {
        let ml = greedy_match_length_with_offset(
          history, src, start, history_len, pos, block_len, r1m1,
        )
        if ml >= 3 &&
          (
            ml > best_ml ||
            (ml == best_ml && (!best_is_rep || 2 < best_rep_rank))
          ) {
          best_ml = ml
          best_offset = r1m1
          best_is_rep = true
          best_rep_rank = 2
        }
      }
    }
    let mut cand = prev_pos
    let mut depth = 0
    while cand >= 0 && depth < depth_limit {
      let offset = current_virtual - cand
      if offset > 0 && offset <= effective_max_offset {
        let ml = greedy_match_length_with_offset(
          history, src, start, history_len, pos, block_len, offset,
        )
        if ml >= 3 &&
          (
            ml > best_ml ||
            (
              ml == best_ml &&
              !best_is_rep &&
              (best_offset == 0 || offset < best_offset)
            )
          ) {
          best_ml = ml
          best_offset = offset
          best_is_rep = false
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
      let (nr1, nr2, nr3) = update_repcodes_after_greedy_offset(
        ll_values[ll_values.length() - 1] == 0,
        best_offset,
        r1,
        r2,
        r3,
      )
      r1 = nr1
      r2 = nr2
      r3 = nr3
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
  if (level < 11 && dictionary_history.length() == 0) || block_len < 32 {
    return b""
  }
  let ll_values : Array[Int] = Array::new()
  let off_values : Array[Int] = Array::new()
  let ml_values : Array[Int] = Array::new()
  let max_sequences_base = general_rle_sequence_cap(level, block_len)
  let max_sequences = if dictionary_history.length() > 0 && level < 10 {
    sequence_cap_by_block(127, block_len)
  } else {
    max_sequences_base
  }
  let search_depth_base = greedy_sequence_search_depth(
    level,
    block_len,
    enable_long_distance_matching~,
  )
  let search_depth = if dictionary_history.length() > 0 &&
    level < 10 &&
    search_depth_base < 24 {
    24
  } else {
    search_depth_base
  }
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
    rep1~,
    rep2~,
    rep3~,
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
