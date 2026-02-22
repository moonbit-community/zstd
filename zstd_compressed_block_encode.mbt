///|
fn detect_repeat_window(
  src : Bytes,
  start : Int,
  block_len : Int,
) -> (Int, Int, Int) {
  if block_len < 5 {
    return (0, 0, 0)
  }
  let max_prefix = if block_len - 5 < 256 { block_len - 5 } else { 256 }
  let max_period = 64

  let mut best_prefix = 0
  let mut best_period = 0
  let mut best_run_len = 0

  let mut prefix = 0
  while prefix <= max_prefix {
    let remain = block_len - prefix
    if remain >= 5 {
      let period_max = if remain - 3 < max_period {
        remain - 3
      } else {
        max_period
      }
      let mut period = 2
      while period <= period_max {
        let mut run_len = period
        while prefix + run_len < block_len &&
              src[start + prefix + run_len] ==
              src[start + prefix + run_len % period] {
          run_len = run_len + 1
        }

        let score = run_len - period
        let best_score = best_run_len - best_period
        if run_len >= period + 3 &&
          (
            best_period == 0 ||
            score > best_score ||
            (
              score == best_score &&
              (
                prefix < best_prefix ||
                (prefix == best_prefix && period < best_period)
              )
            )
          ) {
          best_prefix = prefix
          best_period = period
          best_run_len = run_len
        }
        period = period + 1
      }
    }
    prefix = prefix + 1
  }
  (best_prefix, best_period, best_run_len)
}

///|
fn choose_target_seq_count(level : Int, block_len : Int) -> Int {
  level_periodic_target_seq_count(level, block_len)
}

///|
fn encode_offset_symbol(offset : Int) -> (UInt, UInt, Int) raise ZstdError {
  if offset <= 0 {
    raise CorruptionDetected
  }
  let target = offset.to_uint64()
  let mut code = 2
  while code <= 31 {
    let base = offset_base_from_code(code.reinterpret_as_uint())
    let base_u = base.to_uint64()
    let range = ((1 : UInt64) << code) - (1 : UInt64)
    let limit = base_u + range
    if target >= base_u && target <= limit {
      return (code.reinterpret_as_uint(), (target - base_u).to_uint(), code)
    }
    code = code + 1
  }
  raise CorruptionDetected
}

///|
fn encode_offset_symbol_with_repcodes(
  offset : Int,
  literal_length : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (UInt, UInt, Int) raise ZstdError {
  if offset <= 0 {
    raise CorruptionDetected
  }
  if literal_length == 0 {
    if offset == rep2 {
      return (0, 0, 0)
    }
    if offset == rep3 {
      return (1, 0, 1)
    }
    if rep1 > 1 && offset == rep1 - 1 {
      return (1, 1, 1)
    }
  } else {
    if offset == rep1 {
      return (0, 0, 0)
    }
    if offset == rep2 {
      return (1, 0, 1)
    }
    if offset == rep3 {
      return (1, 1, 1)
    }
  }
  encode_offset_symbol(offset)
}

///|
fn try_encode_common_symbol(
  symbol_type : Int,
  max_code : Int,
  values : Array[Int],
) -> (Bool, UInt, Array[UInt], Int) raise ZstdError {
  let mut code = 0
  while code <= max_code {
    let (base, nb_bits) = sequence_symbol_base_additional_bits(
      symbol_type, code,
    )
    let width = if nb_bits == 0 { 1 } else { 1 << nb_bits }
    let limit = base + width - 1
    let extras : Array[UInt] = Array::new()
    let mut ok = true
    let mut i = 0
    while i < values.length() {
      let v = values[i]
      if v < base || v > limit {
        ok = false
        i = values.length()
      } else {
        extras.push((v - base).reinterpret_as_uint())
        i = i + 1
      }
    }
    if ok {
      return (true, code.reinterpret_as_uint(), extras, nb_bits)
    }
    code = code + 1
  }
  (false, 0, Array::new(), 0)
}

///|
fn split_match_lengths(total_match : Int, seq_count : Int) -> Array[Int] {
  let out : Array[Int] = Array::new()
  if seq_count <= 0 || total_match < seq_count * 3 {
    return out
  }
  let base = total_match / seq_count
  let rem = total_match % seq_count
  let mut i = 0
  while i < seq_count {
    let value = base + (if i < rem { 1 } else { 0 })
    if value < 3 {
      return Array::new()
    }
    out.push(value)
    i = i + 1
  }
  out
}

///|
fn single_symbol_encoding(
  symbol_type : Int,
  max_code : Int,
  value : Int,
) -> (Bool, UInt, UInt, Int) raise ZstdError {
  let values : Array[Int] = Array::new()
  values.push(value)
  let (ok, code, extras, bits) = try_encode_common_symbol(
    symbol_type, max_code, values,
  )
  if !ok || extras.length() != 1 {
    return (false, 0, 0, 0)
  }
  (true, code, extras[0], bits)
}

///|
fn detect_best_single_match(
  src : Bytes,
  start : Int,
  block_len : Int,
  search_limit? : Int = 8192,
  search_depth? : Int = 0,
) -> (Int, Int, Int) {
  if block_len < 4 {
    return (0, 0, 0)
  }
  let search_cap = if search_limit > 0 { search_limit } else { 8192 }
  let search_len = if block_len < search_cap { block_len } else { search_cap }
  if search_len < 4 {
    return (0, 0, 0)
  }
  let depth_limit0 = if search_depth > 0 {
    search_depth
  } else {
    single_match_default_search_depth(search_cap)
  }
  let depth_limit = if depth_limit0 > 0 { depth_limit0 } else { 1 }
  let hash_head : Array[Int] = Array::make(1 << 15, -1)
  let chain : Array[Int] = Array::make(search_len, -1)
  let mut best_ll = 0
  let mut best_offset = 0
  let mut best_ml = 0

  let mut ll = 0
  while ll + 4 <= search_len {
    let p = start + ll
    let h = hash4_bytes(src, p)
    let prev = hash_head[h]
    chain[ll] = prev
    hash_head[h] = ll

    let mut cand = prev
    let mut depth = 0
    while cand >= 0 && depth < depth_limit {
      let offset = ll - cand
      if offset > 0 &&
        offset <= search_cap &&
        src[start + cand] == src[p] &&
        src[start + cand + 1] == src[p + 1] &&
        src[start + cand + 2] == src[p + 2] {
        let mut ml = 3
        while ll + ml < block_len &&
              src[start + cand + ml] == src[start + ll + ml] {
          ml = ml + 1
        }
        if ml > best_ml || (ml == best_ml && (best_ll == 0 || ll < best_ll)) {
          best_ll = ll
          best_offset = offset
          best_ml = ml
        }
      }
      cand = chain[cand]
      depth = depth + 1
    }
    ll = ll + 1
  }
  (best_ll, best_offset, best_ml)
}

///|
fn append_bits_be(bits : Array[Int], value : UInt, count : Int) -> Unit {
  let mut i = count - 1
  while i >= 0 {
    bits.push(((value >> i) & 1).reinterpret_as_int())
    i = i - 1
  }
}

///|
fn bits_to_byte_value(bits : Array[Int], start : Int, count : Int) -> UInt {
  let mut value : UInt = 0
  let mut i = 0
  while i < count {
    value = (value << 1) + bits[start + i].reinterpret_as_uint()
    i = i + 1
  }
  value
}

///|
fn build_reverse_bitstream(bits : Array[Int]) -> Bytes {
  let bit_count = bits.length()
  if bit_count == 0 {
    return b""
  }
  let full_bytes = bit_count / 8
  let rem_bits = bit_count % 8
  let mut pos = 0
  let packed_full : Array[UInt] = Array::new()
  if rem_bits > 0 {
    pos = rem_bits
  }
  let mut i = 0
  while i < full_bytes {
    packed_full.push(bits_to_byte_value(bits, pos, 8))
    pos = pos + 8
    i = i + 1
  }

  let out : Array[Byte] = Array::new()
  i = packed_full.length() - 1
  while i >= 0 {
    out.push(packed_full[i].to_byte())
    i = i - 1
  }
  let last_byte = if rem_bits == 0 {
    (1 : UInt)
  } else {
    ((1 : UInt) << rem_bits) + bits_to_byte_value(bits, 0, rem_bits)
  }
  out.push(last_byte.to_byte())
  Bytes::from_array(out)
}

///|
fn append_sequence_count(
  payload : Array[Byte],
  seq_count : Int,
) -> Unit raise ZstdError {
  if seq_count < 0 {
    raise CorruptionDetected
  }
  if seq_count < 128 {
    payload.push(seq_count.reinterpret_as_uint().to_byte())
  } else if seq_count < 0x7F00 {
    payload.push((0x80 + (seq_count >> 8)).reinterpret_as_uint().to_byte())
    payload.push((seq_count & 0xFF).reinterpret_as_uint().to_byte())
  } else if seq_count <= 0x17EFF {
    let rem = seq_count - 0x7F00
    payload.push((0xFF : UInt).to_byte())
    payload.push((rem & 0xFF).reinterpret_as_uint().to_byte())
    payload.push(((rem >> 8) & 0xFF).reinterpret_as_uint().to_byte())
  } else {
    raise CorruptionDetected
  }
}

///|
fn build_periodic_literals(
  src : Bytes,
  start : Int,
  block_len : Int,
  prefix_len : Int,
  run_len : Int,
  period : Int,
  match_lengths : Array[Int],
) -> Bytes raise ZstdError {
  let literals : Array[Byte] = Array::new()
  if prefix_len > 0 {
    append_bytes(literals, src, start, prefix_len)
  }

  let mut produced = prefix_len
  let mut i = 0
  while i < match_lengths.length() {
    let seq_start = start + produced
    if seq_start + period > start + prefix_len + run_len {
      raise CorruptionDetected
    }
    append_bytes(literals, src, seq_start, period)
    produced = produced + period + match_lengths[i]
    i = i + 1
  }
  if produced > prefix_len + run_len {
    raise CorruptionDetected
  }
  let run_remainder = prefix_len + run_len - produced
  if run_remainder > 0 {
    append_bytes(literals, src, start + produced, run_remainder)
  }
  let tail_len = block_len - (prefix_len + run_len)
  if tail_len > 0 {
    append_bytes(literals, src, start + prefix_len + run_len, tail_len)
  }
  Bytes::from_array(literals)
}

///|
fn build_repeat_payload(
  src : Bytes,
  start : Int,
  block_len : Int,
  prefix_len : Int,
  period : Int,
  run_len : Int,
  seq_count : Int,
) -> Bytes raise ZstdError {
  if seq_count <= 0 {
    return b""
  }
  let total_match = run_len - seq_count * period
  let match_lengths = split_match_lengths(total_match, seq_count)
  if match_lengths.length() != seq_count {
    return b""
  }

  let ll_values : Array[Int] = Array::new()
  let mut i = 0
  while i < seq_count {
    if i == 0 {
      ll_values.push(prefix_len + period)
    } else {
      ll_values.push(period)
    }
    i = i + 1
  }
  let (ll_ok, ll_code, ll_extras, ll_bits) = try_encode_common_symbol(
    sequence_symbol_literal_length, 35, ll_values,
  )
  if !ll_ok {
    return b""
  }
  let (ml_ok, ml_code, ml_extras, ml_bits) = try_encode_common_symbol(
    sequence_symbol_match_length, 52, match_lengths,
  )
  if !ml_ok {
    return b""
  }
  let (off_code, off_extra, off_bits) = encode_offset_symbol(period)

  let extra_bits : Array[Int] = Array::new()
  i = 0
  while i < seq_count {
    append_bits_be(extra_bits, off_extra, off_bits)
    append_bits_be(extra_bits, ml_extras[i], ml_bits)
    append_bits_be(extra_bits, ll_extras[i], ll_bits)
    i = i + 1
  }
  let bitstream = build_reverse_bitstream(extra_bits)
  let literals = build_periodic_literals(
    src, start, block_len, prefix_len, run_len, period, match_lengths,
  )

  let payload : Array[Byte] = Array::new()
  append_best_literals_section(payload, literals)
  append_sequence_count(payload, seq_count)
  payload.push((0x54 : UInt).to_byte()) // all RLE sequence modes
  payload.push(ll_code.to_byte())
  payload.push(off_code.to_byte())
  payload.push(ml_code.to_byte())
  append_bytes(payload, bitstream, 0, bitstream.length())
  Bytes::from_array(payload)
}

///|
fn build_single_match_literals(
  src : Bytes,
  start : Int,
  block_len : Int,
  ll : Int,
  ml : Int,
) -> Bytes raise ZstdError {
  if ll < 0 || ml < 3 || ll + ml > block_len {
    raise CorruptionDetected
  }
  let literals : Array[Byte] = Array::new()
  if ll > 0 {
    append_bytes(literals, src, start, ll)
  }
  let tail_len = block_len - (ll + ml)
  if tail_len > 0 {
    append_bytes(literals, src, start + ll + ml, tail_len)
  }
  Bytes::from_array(literals)
}

///|
fn build_single_match_payload_rle(
  src : Bytes,
  start : Int,
  block_len : Int,
  ll : Int,
  offset : Int,
  ml : Int,
  max_offset : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> Bytes raise ZstdError {
  if ll < 0 ||
    offset <= 0 ||
    ml < 3 ||
    ll + ml > block_len ||
    offset > max_offset {
    return b""
  }
  let (ll_ok, ll_code, ll_extra, ll_bits) = single_symbol_encoding(
    sequence_symbol_literal_length, 35, ll,
  )
  if !ll_ok {
    return b""
  }
  let (ml_ok, ml_code, ml_extra, ml_bits) = single_symbol_encoding(
    sequence_symbol_match_length, 52, ml,
  )
  if !ml_ok {
    return b""
  }
  let (off_code, off_extra, off_bits) = encode_offset_symbol_with_repcodes(
    offset, ll, rep1, rep2, rep3,
  )
  let literals = build_single_match_literals(src, start, block_len, ll, ml)

  let extra_bits : Array[Int] = Array::new()
  append_bits_be(extra_bits, off_extra, off_bits)
  append_bits_be(extra_bits, ml_extra, ml_bits)
  append_bits_be(extra_bits, ll_extra, ll_bits)
  let bitstream = build_reverse_bitstream(extra_bits)

  let payload : Array[Byte] = Array::new()
  append_best_literals_section(payload, literals)
  append_sequence_count(payload, 1)
  payload.push((0x54 : UInt).to_byte()) // all RLE sequence modes
  payload.push(ll_code.to_byte())
  payload.push(off_code.to_byte())
  payload.push(ml_code.to_byte())
  append_bytes(payload, bitstream, 0, bitstream.length())
  Bytes::from_array(payload)
}

///|
fn build_single_match_payload(
  src : Bytes,
  start : Int,
  block_len : Int,
  ll : Int,
  offset : Int,
  ml : Int,
  max_offset : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> Bytes raise ZstdError {
  let rle_payload = build_single_match_payload_rle(
    src, start, block_len, ll, offset, ml, max_offset, rep1, rep2, rep3,
  )
  let predefined_payload = build_single_match_payload_predefined(
    src, start, block_len, ll, offset, ml, max_offset,
  )
  if rle_payload.length() == 0 {
    return predefined_payload
  }
  if predefined_payload.length() == 0 {
    return rle_payload
  }
  if predefined_payload.length() < rle_payload.length() {
    predefined_payload
  } else {
    rle_payload
  }
}

///|
fn build_best_periodic_payload(
  src : Bytes,
  start : Int,
  block_len : Int,
  level : Int,
) -> Bytes raise ZstdError {
  let (prefix_len, period, run_len) = detect_repeat_window(
    src, start, block_len,
  )
  if period == 0 {
    return b""
  }
  let target_seq_count = choose_target_seq_count(level, block_len)
  let mut seq_count = target_seq_count
  let mut payload = b""
  while seq_count >= 1 {
    let candidate = build_repeat_payload(
      src, start, block_len, prefix_len, period, run_len, seq_count,
    )
    if candidate.length() > 0 {
      payload = candidate
      seq_count = 0
    } else {
      seq_count = seq_count - 1
    }
  }
  payload
}

///|
fn append_compressed_repeat_block(
  out : Array[Byte],
  src : Bytes,
  start : Int,
  block_len : Int,
  last_block : Bool,
  level : Int,
  dictionary_history : Bytes,
  dictionary_rep1 : Int,
  dictionary_rep2 : Int,
  dictionary_rep3 : Int,
  enable_long_distance_matching : Bool,
  target_compressed_block_size : Int,
  prev_rle_valid : Ref[Bool],
  prev_ll_code : Ref[UInt],
  prev_off_code : Ref[UInt],
  prev_ml_code : Ref[UInt],
  prev_predefined_valid : Ref[Bool],
  prev_compressed_valid : Ref[Bool],
  prev_ll_header : Ref[Bytes],
  prev_off_header : Ref[Bytes],
  prev_ml_header : Ref[Bytes],
  prev_lit_huf_valid : Ref[Bool],
  prev_lit_huf_tree_desc : Ref[Bytes],
) -> Bool raise ZstdError {
  let periodic_payload = build_best_periodic_payload(
    src, start, block_len, level,
  )
  let sequence_max_offset = if enable_long_distance_matching { 0 } else { 8192 }
  let predefined_payload = build_general_predefined_payload(
    src,
    start,
    block_len,
    level,
    dictionary_history~,
    max_match_offset=sequence_max_offset,
    enable_long_distance_matching~,
    rep1=dictionary_rep1,
    rep2=dictionary_rep2,
    rep3=dictionary_rep3,
  )
  let compressed_fse_payload = build_general_compressed_fse_payload(
    src,
    start,
    block_len,
    level,
    dictionary_history~,
    max_match_offset=sequence_max_offset,
    enable_long_distance_matching~,
  )
  let mixed_payload = build_general_mixed_sequence_payload(
    src,
    start,
    block_len,
    level,
    dictionary_history~,
    max_match_offset=sequence_max_offset,
    enable_long_distance_matching~,
  )
  let literals_only_payload = build_literals_only_payload(
    src, start, block_len, level,
  )
  let general_payload = build_general_rle_payload(
    src,
    start,
    block_len,
    level,
    dictionary_history~,
    max_match_offset=sequence_max_offset,
    enable_long_distance_matching~,
    rep1=dictionary_rep1,
    rep2=dictionary_rep2,
    rep3=dictionary_rep3,
  )
  let search_limit = if enable_long_distance_matching {
    block_len
  } else {
    8192
  }
  let search_depth = level_single_match_search_depth(
    level, enable_long_distance_matching,
  )
  let (ll, offset, ml) = detect_best_single_match_with_dictionary_history(
    src,
    start,
    block_len,
    dictionary_history,
    rep1=dictionary_rep1,
    rep2=dictionary_rep2,
    rep3=dictionary_rep3,
    search_limit~,
    search_depth~,
  )
  let max_offset = ll + dictionary_history.length()
  let single_payload = if ml >= 3 {
    build_single_match_payload(
      src, start, block_len, ll, offset, ml, max_offset, dictionary_rep1, dictionary_rep2,
      dictionary_rep3,
    )
  } else {
    b""
  }
  let payload_pref = if compressed_fse_payload.length() > 0 &&
    prefer_compressed_fse_candidate(level, block_len) {
    compressed_fse_payload
  } else if mixed_payload.length() > 0 &&
    prefer_mixed_candidate(level, block_len) {
    mixed_payload
  } else if periodic_payload.length() > 0 &&
    prefer_periodic_candidate(level, block_len) {
    periodic_payload
  } else {
    let mut best = b""
    if periodic_payload.length() > 0 {
      best = periodic_payload
    }
    if single_payload.length() > 0 &&
      (best.length() == 0 || single_payload.length() < best.length()) {
      best = single_payload
    }
    if general_payload.length() > 0 &&
      (best.length() == 0 || general_payload.length() < best.length()) {
      best = general_payload
    }
    if predefined_payload.length() > 0 &&
      (best.length() == 0 || predefined_payload.length() < best.length()) {
      best = predefined_payload
    }
    if compressed_fse_payload.length() > 0 &&
      (best.length() == 0 || compressed_fse_payload.length() < best.length()) {
      best = compressed_fse_payload
    }
    if mixed_payload.length() > 0 &&
      (best.length() == 0 || mixed_payload.length() < best.length()) {
      best = mixed_payload
    }
    best
  }
  let mut payload0 = payload_pref
  if prev_compressed_valid.val || prev_lit_huf_valid.val {
    payload0 = choose_seeded_best_payload(
      payload_pref,
      periodic_payload,
      predefined_payload,
      compressed_fse_payload,
      mixed_payload,
      single_payload,
      general_payload,
      literals_only_payload,
      prev_rle_valid.val,
      prev_ll_code.val,
      prev_off_code.val,
      prev_ml_code.val,
      prev_predefined_valid.val,
      prev_compressed_valid.val,
      prev_ll_header.val,
      prev_off_header.val,
      prev_ml_header.val,
      prev_lit_huf_valid.val,
      prev_lit_huf_tree_desc.val,
    )
  } else if literals_only_payload.length() > 0 &&
    (
      payload0.length() == 0 ||
      literals_only_payload.length() < payload0.length()
    ) {
    payload0 = literals_only_payload
  }
  let payload0_rewrite = maybe_rewrite_sequence_modes_to_repeat(
    payload0, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
    prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
  )
  let payload = rewrite_literals_section_to_treeless_if_repeat(
    payload0_rewrite, prev_lit_huf_valid, prev_lit_huf_tree_desc,
  )
  if payload.length() == 0 {
    return false
  }
  if target_compressed_block_size > 0 &&
    payload.length() > target_compressed_block_size {
    return false
  }
  if payload.length() >= block_len || payload.length() > 128 << 10 {
    return false
  }

  let last_block_bit : UInt = if last_block { 1 } else { 0 }
  let block_type_compressed : UInt = 2
  let block_header : UInt = (payload.length().reinterpret_as_uint() << 3) +
    (block_type_compressed << 1) +
    last_block_bit
  append_u24_le(out, block_header)
  append_bytes(out, payload, 0, payload.length())
  true
}
