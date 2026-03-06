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
  min_match : Int,
) -> Int {
  if offset <= 0 || min_match < 3 {
    return 0
  }
  if pos + min_match > block_len {
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
  let mut pre = 3
  while pre < min_match {
    if virtual_match_source_byte(history, src, start, history_len, cand + pre) !=
      src[start + pos + pre] {
      return 0
    }
    pre = pre + 1
  }
  let mut ml = min_match
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
  let ll0_int = if ll0 { 1 } else { 0 }
  let off_base = if !ll0 && offset == rep1 {
    1
  } else if offset == rep2 {
    2 - ll0_int
  } else if offset == rep3 {
    3 - ll0_int
  } else if ll0 && rep1 > 1 && offset == rep1 - 1 {
    3
  } else {
    offset + 3
  }
  if off_base > 3 {
    return (offset, rep1, rep2)
  }
  let rep_code = off_base - 1 + ll0_int
  if rep_code == 0 {
    return (rep1, rep2, rep3)
  }
  let current = if rep_code == 3 {
    rep1 - 1
  } else if rep_code == 2 {
    rep3
  } else {
    rep2
  }
  let nr3 = if rep_code >= 2 { rep2 } else { rep3 }
  (current, rep1, nr3)
}

///|
fn greedy_best_match_at_position(
  history : Bytes,
  src : Bytes,
  start : Int,
  history_len : Int,
  anchor : Int,
  pos : Int,
  block_len : Int,
  effective_max_offset : Int,
  min_match : Int,
  r1 : Int,
  r2 : Int,
  r3 : Int,
  prev_pos : Int,
  chain : Array[Int],
  depth_limit : Int,
) -> (Int, Int, Bool, Int) {
  let ll0 = pos == anchor
  let mut best_ml = 0
  let mut best_offset = 0
  let mut best_is_rep = false
  let mut best_rep_rank = 1 << 30

  let rep0 = if ll0 { r2 } else { r1 }
  if rep0 > 0 && rep0 <= effective_max_offset {
    let ml = greedy_match_length_with_offset(
      history, src, start, history_len, pos, block_len, rep0, min_match,
    )
    if ml >= min_match {
      best_ml = ml
      best_offset = rep0
      best_is_rep = true
      best_rep_rank = 0
    }
  }
  if !ll0 && r2 > 0 && r2 <= effective_max_offset {
    let ml = greedy_match_length_with_offset(
      history, src, start, history_len, pos, block_len, r2, min_match,
    )
    if ml >= min_match &&
      (ml > best_ml || (ml == best_ml && (!best_is_rep || 1 < best_rep_rank))) {
      best_ml = ml
      best_offset = r2
      best_is_rep = true
      best_rep_rank = 1
    }
  }
  if r3 > 0 && r3 <= effective_max_offset {
    let ml = greedy_match_length_with_offset(
      history, src, start, history_len, pos, block_len, r3, min_match,
    )
    if ml >= min_match &&
      (ml > best_ml || (ml == best_ml && (!best_is_rep || 2 < best_rep_rank))) {
      best_ml = ml
      best_offset = r3
      best_is_rep = true
      best_rep_rank = 2
    }
  }
  if ll0 && r1 > 1 {
    let r1m1 = r1 - 1
    if r1m1 > 0 && r1m1 <= effective_max_offset {
      let ml = greedy_match_length_with_offset(
        history, src, start, history_len, pos, block_len, r1m1, min_match,
      )
      if ml >= min_match &&
        (ml > best_ml || (ml == best_ml && (!best_is_rep || 3 < best_rep_rank))) {
        best_ml = ml
        best_offset = r1m1
        best_is_rep = true
        best_rep_rank = 3
      }
    }
  }

  let mut cand = prev_pos
  let mut depth = 0
  while cand >= 0 && depth < depth_limit {
    let offset = history_len + pos - cand
    if offset > 0 && offset <= effective_max_offset {
      let ml = greedy_match_length_with_offset(
        history, src, start, history_len, pos, block_len, offset, min_match,
      )
      if ml >= min_match &&
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
  (best_ml, best_offset, best_is_rep, best_rep_rank)
}

///|
fn greedy_offset_off_base(
  raw_offset : Int,
  ll0 : Bool,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> Int {
  if !ll0 && raw_offset == rep1 {
    return 1
  }
  if raw_offset == rep2 {
    return if ll0 { 1 } else { 2 }
  }
  if raw_offset == rep3 {
    return if ll0 { 2 } else { 3 }
  }
  if ll0 && rep1 > 1 && raw_offset == rep1 - 1 {
    return 3
  }
  raw_offset + 3
}

///|
fn selected_offset_off_base(
  raw_offset : Int,
  ll0 : Bool,
  selected_rep_match : Bool,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> Int {
  if selected_rep_match {
    greedy_offset_off_base(raw_offset, ll0, rep1, rep2, rep3)
  } else {
    raw_offset + 3
  }
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
  min_match? : Int = 3,
  prefer_offset_stability? : Bool = false,
  off_base_values? : Array[Int] = Array::new(),
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
        history, src, start, history_len, pos, block_len, rep0, min_match,
      )
      if ml >= min_match {
        best_ml = ml
        best_offset = rep0
        best_is_rep = true
        best_rep_rank = 0
      }
    }
    if !ll0 && r2 > 0 && r2 <= effective_max_offset {
      let ml = greedy_match_length_with_offset(
        history, src, start, history_len, pos, block_len, r2, min_match,
      )
      if ml >= min_match &&
        (ml > best_ml || (ml == best_ml && (!best_is_rep || 1 < best_rep_rank))) {
        best_ml = ml
        best_offset = r2
        best_is_rep = true
        best_rep_rank = 1
      }
    }
    if r3 > 0 && r3 <= effective_max_offset {
      let ml = greedy_match_length_with_offset(
        history, src, start, history_len, pos, block_len, r3, min_match,
      )
      if ml >= min_match &&
        (ml > best_ml || (ml == best_ml && (!best_is_rep || 2 < best_rep_rank))) {
        best_ml = ml
        best_offset = r3
        best_is_rep = true
        best_rep_rank = 2
      }
    }
    if ll0 && r1 > 1 {
      let r1m1 = r1 - 1
      if r1m1 > 0 && r1m1 <= effective_max_offset {
        let ml = greedy_match_length_with_offset(
          history, src, start, history_len, pos, block_len, r1m1, min_match,
        )
        if ml >= min_match &&
          (
            ml > best_ml ||
            (ml == best_ml && (!best_is_rep || 3 < best_rep_rank))
          ) {
          best_ml = ml
          best_offset = r1m1
          best_is_rep = true
          best_rep_rank = 3
        }
      }
    }
    let mut cand = prev_pos
    let mut depth = 0
    while cand >= 0 && depth < depth_limit {
      let offset = current_virtual - cand
      if offset > 0 && offset <= effective_max_offset {
        let ml = greedy_match_length_with_offset(
          history, src, start, history_len, pos, block_len, offset, min_match,
        )
        let slight_gain_with_larger_offset = prefer_offset_stability &&
          ml == best_ml + 1 &&
          best_ml > 0 &&
          best_offset > 0 &&
          offset > best_offset &&
          (offset >= best_offset * 2 || offset - best_offset >= 64)
        if ml >= min_match &&
          (
            (ml > best_ml && !slight_gain_with_larger_offset) ||
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
    if best_ml >= min_match {
      let mut skip_for_next_rep = false
      if prefer_offset_stability &&
        !best_is_rep &&
        best_offset > 0 &&
        pos + 1 + min_match <= block_len {
        let next_ll0 = pos + 1 == anchor
        let next_rep0 = if next_ll0 { r2 } else { r1 }
        if next_rep0 > 0 &&
          next_rep0 < best_offset &&
          next_rep0 <= effective_max_offset {
          let next_rep_ml = greedy_match_length_with_offset(
            history,
            src,
            start,
            history_len,
            pos + 1,
            block_len,
            next_rep0,
            min_match,
          )
          if next_rep_ml >= min_match && next_rep_ml >= best_ml - 1 {
            skip_for_next_rep = true
          }
        }
      }
      if !skip_for_next_rep &&
        prefer_offset_stability &&
        pos + 1 + min_match <= block_len {
        let next_pos = pos + 1
        let next_window_limit = history_len + next_pos
        let next_effective_max_offset = if max_match_offset > 0 &&
          max_match_offset < next_window_limit {
          max_match_offset
        } else {
          next_window_limit
        }
        let next_hash = hash4_bytes(src, start + next_pos)
        let next_prev = hash_head[next_hash]
        let (next_best_ml, next_best_offset, next_best_is_rep, _) = greedy_best_match_at_position(
          history, src, start, history_len, anchor, next_pos, block_len, next_effective_max_offset,
          min_match, r1, r2, r3, next_prev, chain, depth_limit,
        )
        let strong_gain = next_best_ml >= best_ml + 4
        let acceptable_offset_jump = if best_offset > 0 {
          next_best_is_rep || next_best_offset <= best_offset * 2
        } else {
          true
        }
        if next_best_ml > best_ml && (strong_gain || acceptable_offset_jump) {
          skip_for_next_rep = true
        }
      }
      if skip_for_next_rep {
        pos = pos + 1
        matched = true
      } else {
        let mut adjusted_pos = pos
        let mut adjusted_ml = best_ml
        if best_offset > 0 && best_offset <= 64 {
          let cand = current_virtual - best_offset
          let (new_pos, _, new_ml) = extend_virtual_match_backward(
            history, src, start, history_len, anchor, pos, cand, best_ml, 0,
          )
          adjusted_pos = new_pos
          adjusted_ml = new_ml
        }
        let literal_length = adjusted_pos - anchor
        ll_values.push(literal_length)
        off_values.push(best_offset)
        off_base_values.push(
          selected_offset_off_base(
            best_offset,
            literal_length == 0,
            best_is_rep,
            r1,
            r2,
            r3,
          ),
        )
        ml_values.push(adjusted_ml)
        let end_pos = adjusted_pos + adjusted_ml
        let mut update_pos = pos + 1
        while update_pos + 4 <= end_pos {
          let hu = hash4_bytes(src, start + update_pos)
          let uv = history_len + update_pos
          chain[uv] = hash_head[hu]
          hash_head[hu] = uv
          update_pos = update_pos + 1
        }
        let (nr1, nr2, nr3) = update_repcodes_after_greedy_offset(
          literal_length == 0,
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
  if (level < 9 && dictionary_history.length() == 0) || block_len < 32 {
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
  let search_depth = search_depth_base
  let min_match = if level == 9 && dictionary_history.length() == 0 {
    5
  } else {
    greedy_sequence_min_match(level, block_len)
  }
  let prefer_offset_stability = level == 9 && dictionary_history.length() == 0
  collect_level_aligned_sequences(
    src,
    start,
    block_len,
    level,
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
    min_match~,
    prefer_offset_stability~,
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
