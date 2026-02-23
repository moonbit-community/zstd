///|
fn append_forward_bits_lsb(
  bits : Array[Int],
  value : Int,
  count : Int,
) -> Unit raise ZstdError {
  if count < 0 {
    raise CorruptionDetected
  }
  if count == 0 {
    return
  }
  let mask = (1 : Int64) << count
  if value < 0 || value.to_int64() >= mask {
    raise CorruptionDetected
  }
  let mut i = 0
  while i < count {
    bits.push((value >> i) & 1)
    i = i + 1
  }
}

///|
fn pack_forward_bits_lsb(bits : Array[Int]) -> Bytes {
  if bits.length() == 0 {
    return b""
  }
  let out_len = (bits.length() + 7) >> 3
  let out : Array[Byte] = Array::make(out_len, b"\x00"[0])
  let mut i = 0
  while i < bits.length() {
    if bits[i] == 1 {
      let byte_pos = i >> 3
      let bit_pos = i & 7
      out[byte_pos] = (out[byte_pos].to_uint() + ((1 : UInt) << bit_pos)).to_byte()
    }
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
fn normalized_counter_abs_sum(
  normalized_counter : Array[Int],
  max_symbol : Int,
) -> Int raise ZstdError {
  if max_symbol < 0 || max_symbol >= normalized_counter.length() {
    raise CorruptionDetected
  }
  let mut sum = 0
  let mut i = 0
  while i <= max_symbol {
    let v = normalized_counter[i]
    if v < -1 {
      raise CorruptionDetected
    }
    sum = sum + (if v < 0 { -v } else { v })
    i = i + 1
  }
  sum
}

///|
fn write_fse_ncount_header(
  normalized_counter : Array[Int],
  max_symbol : Int,
  table_log : Int,
) -> Bytes raise ZstdError {
  if table_log < fse_min_table_log || table_log > fse_table_log_absolute_max {
    raise CorruptionDetected
  }
  if max_symbol < 0 || max_symbol >= normalized_counter.length() {
    raise CorruptionDetected
  }
  let table_size = 1 << table_log
  if normalized_counter_abs_sum(normalized_counter, max_symbol) != table_size {
    raise CorruptionDetected
  }
  let out : Array[Byte] = Array::new()
  let mut bit_stream = (table_log - fse_min_table_log).to_uint64()
  let mut bit_count = 4
  let mut remaining = table_size + 1
  let mut threshold = table_size
  let mut nb_bits = table_log + 1
  let mut symbol = 0
  let alphabet_size = max_symbol + 1
  let mut previous_is0 = false

  while symbol < alphabet_size && remaining > 1 {
    if previous_is0 {
      let mut start = symbol
      while symbol < alphabet_size && normalized_counter[symbol] == 0 {
        symbol = symbol + 1
      }
      if symbol == alphabet_size {
        break
      }
      while symbol >= start + 24 {
        start = start + 24
        bit_stream = bit_stream + ((0xFFFF : UInt64) << bit_count)
        out.push((bit_stream & 0xFF).to_byte())
        out.push(((bit_stream >> 8) & 0xFF).to_byte())
        bit_stream = bit_stream >> 16
      }
      while symbol >= start + 3 {
        start = start + 3
        bit_stream = bit_stream + ((3 : UInt64) << bit_count)
        bit_count = bit_count + 2
      }
      bit_stream = bit_stream + ((symbol - start).to_uint64() << bit_count)
      bit_count = bit_count + 2
      if bit_count > 16 {
        out.push((bit_stream & 0xFF).to_byte())
        out.push(((bit_stream >> 8) & 0xFF).to_byte())
        bit_stream = bit_stream >> 16
        bit_count = bit_count - 16
      }
    }

    let mut count = normalized_counter[symbol]
    symbol = symbol + 1
    let max = 2 * threshold - 1 - remaining
    remaining = remaining - (if count < 0 { -count } else { count })
    count = count + 1
    if count >= threshold {
      count = count + max
    }
    bit_stream = bit_stream + (count.to_uint64() << bit_count)
    bit_count = bit_count + nb_bits
    if count < max {
      bit_count = bit_count - 1
    }
    previous_is0 = count == 1
    if remaining < 1 {
      raise CorruptionDetected
    }
    while remaining < threshold {
      nb_bits = nb_bits - 1
      threshold = threshold >> 1
    }
    if bit_count > 16 {
      out.push((bit_stream & 0xFF).to_byte())
      out.push(((bit_stream >> 8) & 0xFF).to_byte())
      bit_stream = bit_stream >> 16
      bit_count = bit_count - 16
    }
  }

  if remaining != 1 {
    raise CorruptionDetected
  }
  out.push((bit_stream & 0xFF).to_byte())
  if bit_count > 8 {
    out.push(((bit_stream >> 8) & 0xFF).to_byte())
  }
  let header = Bytes::from_array(out)
  if header.length() == 0 {
    raise CorruptionDetected
  }
  header
}
