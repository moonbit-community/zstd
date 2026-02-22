///|
fn detect_repeat_prefix(
  src : Bytes,
  start : Int,
  block_len : Int,
) -> (Int, Int) {
  if block_len < 5 {
    return (0, 0)
  }
  let max_period = if block_len - 3 < 64 { block_len - 3 } else { 64 }
  let mut best_period = 0
  let mut best_run_len = 0
  let mut period = 2
  while period <= max_period {
    let mut run_len = period
    while run_len < block_len &&
          src[start + run_len] == src[start + run_len % period] {
      run_len = run_len + 1
    }
    if run_len >= period + 3 &&
      (
        run_len > best_run_len ||
        (run_len == best_run_len && (best_period == 0 || period < best_period))
      ) {
      best_period = period
      best_run_len = run_len
    }
    period = period + 1
  }
  (best_period, best_run_len)
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
fn encode_sequence_length_symbol(
  symbol_type : Int,
  max_code : Int,
  value : Int,
) -> (UInt, UInt, Int) raise ZstdError {
  let mut code = 0
  while code <= max_code {
    let (base, nb_bits) = sequence_symbol_base_additional_bits(
      symbol_type, code,
    )
    let width = if nb_bits == 0 { 1 } else { (1 : Int) << nb_bits }
    let limit = base + width - 1
    if value >= base && value <= limit {
      return (
        code.reinterpret_as_uint(),
        (value - base).reinterpret_as_uint(),
        nb_bits,
      )
    }
    code = code + 1
  }
  raise CorruptionDetected
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
fn append_raw_literals_section(
  out : Array[Byte],
  literals : Bytes,
) -> Unit raise ZstdError {
  let lit_len = literals.length()
  if lit_len <= 31 {
    out.push((lit_len.reinterpret_as_uint() << 3).to_byte())
  } else if lit_len <= 4095 {
    out.push((((lit_len & 0xF).reinterpret_as_uint() << 4) + 0x04).to_byte())
    out.push(((lit_len >> 4).reinterpret_as_uint() & 0xFF).to_byte())
  } else if lit_len <= 131072 {
    out.push((((lit_len & 0xF).reinterpret_as_uint() << 4) + 0x0C).to_byte())
    out.push(((lit_len >> 4).reinterpret_as_uint() & 0xFF).to_byte())
    out.push(((lit_len >> 12).reinterpret_as_uint() & 0xFF).to_byte())
  } else {
    raise CorruptionDetected
  }
  append_bytes(out, literals, 0, lit_len)
}

///|
fn append_sequence_count(
  payload : Array[Byte],
  seq_count : Int,
) -> Unit raise ZstdError {
  if seq_count < 0 || seq_count > 127 {
    raise CorruptionDetected
  }
  payload.push(seq_count.reinterpret_as_uint().to_byte())
}

///|
fn build_periodic_literals(
  src : Bytes,
  start : Int,
  block_len : Int,
  run_len : Int,
  period : Int,
  seq_count : Int,
  chunk_match_len : Int,
) -> Bytes raise ZstdError {
  let literals : Array[Byte] = Array::new()
  let seq_span = period + chunk_match_len
  let mut s = 0
  while s < seq_count {
    let seq_start = start + s * seq_span
    if seq_start + period > start + run_len {
      raise CorruptionDetected
    }
    append_bytes(literals, src, seq_start, period)
    s = s + 1
  }
  let produced_by_sequences = seq_count * seq_span
  if produced_by_sequences > run_len {
    raise CorruptionDetected
  }
  let run_remainder = run_len - produced_by_sequences
  if run_remainder > 0 {
    append_bytes(literals, src, start + produced_by_sequences, run_remainder)
  }
  let tail_len = block_len - run_len
  if tail_len > 0 {
    append_bytes(literals, src, start + run_len, tail_len)
  }
  Bytes::from_array(literals)
}

///|
fn build_repeat_payload(
  src : Bytes,
  start : Int,
  block_len : Int,
  period : Int,
  run_len : Int,
  seq_count : Int,
  chunk_match_len : Int,
) -> Bytes raise ZstdError {
  if seq_count <= 0 || chunk_match_len < 3 {
    return b""
  }
  let produced_by_sequences = seq_count * (period + chunk_match_len)
  if produced_by_sequences > run_len {
    return b""
  }

  let (ll_code, ll_extra, ll_bits) = encode_sequence_length_symbol(
    sequence_symbol_literal_length, 35, period,
  )
  let (ml_code, ml_extra, ml_bits) = encode_sequence_length_symbol(
    sequence_symbol_match_length, 52, chunk_match_len,
  )
  let (off_code, off_extra, off_bits) = encode_offset_symbol(period)

  let extra_bits : Array[Int] = Array::new()
  let mut i = 0
  while i < seq_count {
    append_bits_be(extra_bits, off_extra, off_bits)
    append_bits_be(extra_bits, ml_extra, ml_bits)
    append_bits_be(extra_bits, ll_extra, ll_bits)
    i = i + 1
  }
  let bitstream = build_reverse_bitstream(extra_bits)
  let literals = build_periodic_literals(
    src, start, block_len, run_len, period, seq_count, chunk_match_len,
  )

  let payload : Array[Byte] = Array::new()
  append_raw_literals_section(payload, literals)
  append_sequence_count(payload, seq_count)
  payload.push((0x54 : UInt).to_byte()) // all RLE sequence modes
  payload.push(ll_code.to_byte())
  payload.push(off_code.to_byte())
  payload.push(ml_code.to_byte())
  append_bytes(payload, bitstream, 0, bitstream.length())
  Bytes::from_array(payload)
}

///|
fn append_compressed_repeat_block(
  out : Array[Byte],
  src : Bytes,
  start : Int,
  block_len : Int,
  last_block : Bool,
  level : Int,
) -> Bool raise ZstdError {
  let (period, run_len) = detect_repeat_prefix(src, start, block_len)
  if period == 0 {
    return false
  }
  let single_match_len = run_len - period
  if single_match_len < 3 {
    return false
  }

  let payload_single = build_repeat_payload(
    src, start, block_len, period, run_len, 1, single_match_len,
  )
  if payload_single.length() == 0 {
    return false
  }

  let payload = if level >= 18 && run_len >= 2 * (period + 3) {
    let half_chunk = run_len / 2 - period
    let payload_multi = build_repeat_payload(
      src, start, block_len, period, run_len, 2, half_chunk,
    )
    if payload_multi.length() > 0 {
      payload_multi
    } else {
      payload_single
    }
  } else {
    payload_single
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
