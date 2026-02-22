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
fn collect_greedy_sequences(
  src : Bytes,
  start : Int,
  block_len : Int,
  ll_values : Array[Int],
  off_values : Array[Int],
  ml_values : Array[Int],
  max_sequences : Int,
) -> Unit {
  let hash_table : Array[Int] = Array::make(1 << 15, -1)
  let mut pos = 0
  let mut anchor = 0

  while pos + 4 <= block_len && ll_values.length() < max_sequences {
    let abs_pos = start + pos
    let h = hash4_bytes(src, abs_pos)
    let prev_pos = hash_table[h]
    hash_table[h] = pos

    let mut matched = false
    if prev_pos >= 0 {
      let offset = pos - prev_pos
      if offset > 0 &&
        src[start + prev_pos] == src[abs_pos] &&
        src[start + prev_pos + 1] == src[abs_pos + 1] &&
        src[start + prev_pos + 2] == src[abs_pos + 2] {
        let mut ml = 3
        while pos + ml < block_len &&
              src[start + prev_pos + ml] == src[start + pos + ml] {
          ml = ml + 1
        }
        if ml >= 3 {
          ll_values.push(pos - anchor)
          off_values.push(offset)
          ml_values.push(ml)
          let end_pos = pos + ml
          let mut update_pos = pos + 1
          while update_pos + 4 <= end_pos {
            let hu = hash4_bytes(src, start + update_pos)
            hash_table[hu] = update_pos
            update_pos = update_pos + 1
          }
          pos = end_pos
          anchor = pos
          matched = true
        }
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
) -> Bytes raise ZstdError {
  if level < 11 || block_len < 32 {
    return b""
  }
  let ll_values : Array[Int] = Array::new()
  let off_values : Array[Int] = Array::new()
  let ml_values : Array[Int] = Array::new()
  let max_sequences = general_rle_sequence_cap(level, block_len)
  collect_greedy_sequences(
    src, start, block_len, ll_values, off_values, ml_values, max_sequences,
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
  let (off_ok, off_code, off_extras, off_bits) = try_encode_common_offset_symbol(
    off_values,
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
