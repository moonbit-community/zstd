///|
let sequence_symbol_literal_length = 0

///|
let sequence_symbol_offset = 1

///|
let sequence_symbol_match_length = 2

///|
let fse_min_table_log = 5

///|
let fse_table_log_absolute_max = 15

///|
fn build_sequence_fse_table_from_header(
  src : Bytes,
  start : Int,
  end_pos : Int,
  symbol_type : Int,
) -> (Int, Int, Array[Int], Array[Int], Array[Int], Array[Int]) raise ZstdError {
  let (max_symbol, max_table_log) = sequence_symbol_limits(symbol_type)
  let (header_size, table_log, decoded_max_symbol, normalized_counter) = read_fse_ncount_header(
    src, start, end_pos, max_symbol, max_table_log,
  )
  let (next_state, nb_add_bits, nb_bits, base_values) = build_sequence_fse_decode_table(
    normalized_counter, decoded_max_symbol, table_log, symbol_type,
  )
  (header_size, table_log, next_state, nb_add_bits, nb_bits, base_values)
}

///|
fn sequence_symbol_limits(symbol_type : Int) -> (Int, Int) raise ZstdError {
  if symbol_type == sequence_symbol_literal_length {
    (35, 9)
  } else if symbol_type == sequence_symbol_offset {
    (31, 8)
  } else if symbol_type == sequence_symbol_match_length {
    (52, 9)
  } else {
    raise CorruptionDetected
  }
}

///|
fn sequence_symbol_base_additional_bits(
  symbol_type : Int,
  symbol : Int,
) -> (Int, Int) raise ZstdError {
  if symbol_type == sequence_symbol_literal_length {
    literal_length_base_bits(symbol.reinterpret_as_uint())
  } else if symbol_type == sequence_symbol_offset {
    (offset_base_from_code(symbol.reinterpret_as_uint()), symbol)
  } else if symbol_type == sequence_symbol_match_length {
    match_length_base_bits(symbol.reinterpret_as_uint())
  } else {
    raise CorruptionDetected
  }
}

///|
fn build_sequence_fse_decode_table(
  normalized_counter : Array[Int],
  max_symbol : Int,
  table_log : Int,
  symbol_type : Int,
) -> (Array[Int], Array[Int], Array[Int], Array[Int]) raise ZstdError {
  if table_log < fse_min_table_log || table_log > fse_table_log_absolute_max {
    raise CorruptionDetected
  }
  let table_size = (1 : Int) << table_log
  let table_mask = table_size - 1
  let step = (table_size >> 1) + (table_size >> 3) + 3

  let table_symbol : Array[Int] = Array::new()
  let symbol_next : Array[Int] = Array::new()
  let mut i = 0
  while i < table_size {
    table_symbol.push(0)
    i = i + 1
  }
  i = 0
  while i <= max_symbol {
    symbol_next.push(0)
    i = i + 1
  }

  let mut high_threshold = table_size - 1
  let mut s = 0
  while s <= max_symbol {
    let count = normalized_counter[s]
    if count == -1 {
      if high_threshold < 0 {
        raise CorruptionDetected
      }
      table_symbol[high_threshold] = s
      high_threshold = high_threshold - 1
      symbol_next[s] = 1
    } else if count >= 0 {
      symbol_next[s] = count
    } else {
      raise CorruptionDetected
    }
    s = s + 1
  }

  let mut position = 0
  s = 0
  while s <= max_symbol {
    let count = normalized_counter[s]
    if count > 0 {
      let mut n = 0
      while n < count {
        table_symbol[position] = s
        position = (position + step) & table_mask
        while position > high_threshold {
          position = (position + step) & table_mask
        }
        n = n + 1
      }
    }
    s = s + 1
  }
  if position != 0 {
    raise CorruptionDetected
  }

  let next_state : Array[Int] = Array::new()
  let nb_add_bits : Array[Int] = Array::new()
  let nb_bits : Array[Int] = Array::new()
  let base_values : Array[Int] = Array::new()
  i = 0
  while i < table_size {
    next_state.push(0)
    nb_add_bits.push(0)
    nb_bits.push(0)
    base_values.push(0)
    i = i + 1
  }

  i = 0
  while i < table_size {
    let symbol = table_symbol[i]
    if symbol < 0 || symbol > max_symbol {
      raise CorruptionDetected
    }
    let state = symbol_next[symbol]
    if state <= 0 {
      raise CorruptionDetected
    }
    symbol_next[symbol] = state + 1

    let state_high_bit = high_bit_positive(state)
    let state_bits = table_log - state_high_bit
    if state_bits < 0 {
      raise CorruptionDetected
    }

    next_state[i] = (state << state_bits) - table_size
    nb_bits[i] = state_bits

    let (base, add_bits) = sequence_symbol_base_additional_bits(
      symbol_type, symbol,
    )
    nb_add_bits[i] = add_bits
    base_values[i] = base

    i = i + 1
  }

  (next_state, nb_add_bits, nb_bits, base_values)
}

///|
fn build_fse_symbol_decode_table(
  normalized_counter : Array[Int],
  max_symbol : Int,
  table_log : Int,
) -> (Array[Int], Array[Int], Array[Int]) raise ZstdError {
  if table_log < fse_min_table_log || table_log > fse_table_log_absolute_max {
    raise CorruptionDetected
  }
  if max_symbol < 0 || max_symbol >= normalized_counter.length() {
    raise CorruptionDetected
  }
  let table_size = (1 : Int) << table_log
  let table_mask = table_size - 1
  let step = (table_size >> 1) + (table_size >> 3) + 3

  let table_symbol : Array[Int] = Array::new()
  let symbol_next : Array[Int] = Array::new()
  let mut i = 0
  while i < table_size {
    table_symbol.push(0)
    i = i + 1
  }
  i = 0
  while i <= max_symbol {
    symbol_next.push(0)
    i = i + 1
  }

  let mut high_threshold = table_size - 1
  let mut s = 0
  while s <= max_symbol {
    let count = normalized_counter[s]
    if count == -1 {
      if high_threshold < 0 {
        raise CorruptionDetected
      }
      table_symbol[high_threshold] = s
      high_threshold = high_threshold - 1
      symbol_next[s] = 1
    } else if count >= 0 {
      symbol_next[s] = count
    } else {
      raise CorruptionDetected
    }
    s = s + 1
  }

  let mut position = 0
  s = 0
  while s <= max_symbol {
    let count = normalized_counter[s]
    if count > 0 {
      let mut n = 0
      while n < count {
        table_symbol[position] = s
        position = (position + step) & table_mask
        while position > high_threshold {
          position = (position + step) & table_mask
        }
        n = n + 1
      }
    }
    s = s + 1
  }
  if position != 0 {
    raise CorruptionDetected
  }

  let next_state : Array[Int] = Array::new()
  let nb_bits : Array[Int] = Array::new()
  let symbols : Array[Int] = Array::new()
  i = 0
  while i < table_size {
    next_state.push(0)
    nb_bits.push(0)
    symbols.push(0)
    i = i + 1
  }

  i = 0
  while i < table_size {
    let symbol = table_symbol[i]
    if symbol < 0 || symbol > max_symbol {
      raise CorruptionDetected
    }
    let state = symbol_next[symbol]
    if state <= 0 {
      raise CorruptionDetected
    }
    symbol_next[symbol] = state + 1

    let state_high_bit = high_bit_positive(state)
    let state_bits = table_log - state_high_bit
    if state_bits < 0 {
      raise CorruptionDetected
    }

    next_state[i] = (state << state_bits) - table_size
    nb_bits[i] = state_bits
    symbols[i] = symbol
    i = i + 1
  }

  (next_state, nb_bits, symbols)
}

///|
fn read_fse_ncount_header(
  src : Bytes,
  start : Int,
  end_pos : Int,
  max_symbol_limit : Int,
  table_log_max : Int,
) -> (Int, Int, Int, Array[Int]) raise ZstdError {
  if start >= end_pos || max_symbol_limit < 0 {
    raise CorruptionDetected
  }
  let hb_size = end_pos - start
  let total_bits = hb_size * 8

  let normalized_counter : Array[Int] = Array::new()
  let mut i = 0
  while i <= max_symbol_limit {
    normalized_counter.push(0)
    i = i + 1
  }

  let bit_pos : Ref[Int] = { val: 0 }
  let table_log = read_forward_bits(src, start, total_bits, bit_pos, 4).reinterpret_as_int() +
    fse_min_table_log
  if table_log < fse_min_table_log ||
    table_log > table_log_max ||
    table_log > fse_table_log_absolute_max {
    raise CorruptionDetected
  }

  let mut remaining = ((1 : Int) << table_log) + 1
  let mut threshold = (1 : Int) << table_log
  let mut nb_bits = table_log + 1
  let mut charnum = 0
  let mut previous0 = false

  while true {
    if previous0 {
      let mut repeat_count = 0
      while true {
        let repeat_code = read_forward_bits(src, start, total_bits, bit_pos, 2).reinterpret_as_int()
        if repeat_code == 3 {
          repeat_count = repeat_count + 3
        } else {
          repeat_count = repeat_count + repeat_code
          break
        }
      }
      charnum = charnum + repeat_count
      if charnum >= max_symbol_limit + 1 {
        break
      }
    }

    let max = 2 * threshold - 1 - remaining
    if nb_bits <= 0 {
      raise CorruptionDetected
    }

    let low = peek_forward_bits(
      src,
      start,
      total_bits,
      bit_pos.val,
      nb_bits - 1,
    ).reinterpret_as_int()

    let mut count = if low < max {
      bit_pos.val = bit_pos.val + nb_bits - 1
      low
    } else {
      let mut value = peek_forward_bits(
        src,
        start,
        total_bits,
        bit_pos.val,
        nb_bits,
      ).reinterpret_as_int()
      bit_pos.val = bit_pos.val + nb_bits
      if value >= threshold {
        value = value - max
      }
      value
    }

    count = count - 1
    if count >= 0 {
      remaining = remaining - count
    } else {
      remaining = remaining + count
    }

    if charnum >= max_symbol_limit + 1 {
      break
    }
    normalized_counter[charnum] = count
    charnum = charnum + 1
    previous0 = count == 0

    if remaining < threshold {
      if remaining <= 1 {
        break
      }
      nb_bits = high_bit_positive(remaining) + 1
      threshold = (1 : Int) << (nb_bits - 1)
    }

    if charnum >= max_symbol_limit + 1 {
      break
    }
  }

  if remaining != 1 {
    raise CorruptionDetected
  }
  if charnum <= 0 || charnum > max_symbol_limit + 1 {
    raise CorruptionDetected
  }

  let header_size = (bit_pos.val + 7) >> 3
  if header_size <= 0 || start + header_size > end_pos {
    raise CorruptionDetected
  }

  (header_size, table_log, charnum - 1, normalized_counter)
}

///|
fn read_forward_bits(
  src : Bytes,
  start : Int,
  total_bits : Int,
  bit_pos : Ref[Int],
  count : Int,
) -> UInt raise ZstdError {
  let value = peek_forward_bits(src, start, total_bits, bit_pos.val, count)
  bit_pos.val = bit_pos.val + count
  value
}

///|
fn peek_forward_bits(
  src : Bytes,
  start : Int,
  total_bits : Int,
  bit_pos : Int,
  count : Int,
) -> UInt raise ZstdError {
  if count < 0 || bit_pos < 0 || bit_pos + count > total_bits {
    raise CorruptionDetected
  }
  if count == 0 {
    return (0 : UInt)
  }

  let mut value : UInt = 0
  let mut i = 0
  while i < count {
    let absolute_bit = bit_pos + i
    let byte_index = start + (absolute_bit >> 3)
    let bit_index = absolute_bit & 7
    let bit = (src[byte_index].to_uint() >> bit_index) & 1
    value = value + (bit << i)
    i = i + 1
  }
  value
}

///|
fn high_bit_positive(value : Int) -> Int raise ZstdError {
  if value <= 0 {
    raise CorruptionDetected
  }
  let mut bit = 0
  let mut v = value
  while v > 1 {
    v = v >> 1
    bit = bit + 1
  }
  bit
}
