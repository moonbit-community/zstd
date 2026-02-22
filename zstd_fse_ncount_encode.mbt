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

  let bits : Array[Int] = Array::new()
  append_forward_bits_lsb(bits, table_log - fse_min_table_log, 4)

  let mut remaining = table_size + 1
  let mut threshold = table_size
  let mut nb_bits = table_log + 1
  let mut charnum = 0
  let mut previous0 = false

  while remaining > 1 && charnum <= max_symbol {
    if previous0 {
      let mut repeat = 0
      let mut p = charnum
      while p <= max_symbol && normalized_counter[p] == 0 {
        repeat = repeat + 1
        p = p + 1
      }
      let mut r = repeat
      while r >= 3 {
        append_forward_bits_lsb(bits, 3, 2)
        r = r - 3
      }
      append_forward_bits_lsb(bits, r, 2)
      charnum = charnum + repeat
      if charnum > max_symbol {
        break
      }
    }

    let decoded = normalized_counter[charnum]
    let count = decoded + 1
    if count < 0 || count > remaining {
      raise CorruptionDetected
    }
    let max = 2 * threshold - 1 - remaining
    if max < 0 {
      raise CorruptionDetected
    }
    if count < max {
      append_forward_bits_lsb(bits, count, nb_bits - 1)
    } else {
      let value = if count < threshold { count } else { count + max }
      append_forward_bits_lsb(bits, value, nb_bits)
    }

    remaining = if decoded >= 0 {
      remaining - decoded
    } else {
      remaining + decoded
    }
    charnum = charnum + 1
    previous0 = decoded == 0

    if remaining < threshold {
      if remaining <= 1 {
        break
      }
      nb_bits = high_bit_positive(remaining) + 1
      threshold = 1 << (nb_bits - 1)
    }
  }

  if remaining != 1 {
    raise CorruptionDetected
  }
  let header = pack_forward_bits_lsb(bits)
  if header.length() == 0 {
    raise CorruptionDetected
  }
  header
}
