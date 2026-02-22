///|
let compressed_mode_table_log = 5

///|
fn encode_symbol_for_value(
  symbol_type : Int,
  value : Int,
) -> (Bool, Int, UInt, Int) raise ZstdError {
  if value < 0 {
    return (false, 0, 0, 0)
  }
  let (max_symbol, _) = sequence_symbol_limits(symbol_type)
  let mut found = false
  let mut best_symbol = 0
  let mut best_extra : UInt = 0
  let mut best_add_bits = 0

  let mut symbol = 0
  while symbol <= max_symbol {
    let allow = if symbol_type == sequence_symbol_offset {
      symbol > 1
    } else {
      true
    }
    if allow {
      let (base, nb_add_bits) = sequence_symbol_base_additional_bits(
        symbol_type, symbol,
      )
      if value >= base {
        let span = if nb_add_bits == 0 {
          0
        } else {
          (((1 : UInt64) << nb_add_bits) - (1 : UInt64)).to_int()
        }
        let limit = base + span
        if value <= limit &&
          (
            !found ||
            nb_add_bits < best_add_bits ||
            (nb_add_bits == best_add_bits && symbol < best_symbol)
          ) {
          found = true
          best_symbol = symbol
          best_extra = (value - base).reinterpret_as_uint()
          best_add_bits = nb_add_bits
        }
      }
    }
    symbol = symbol + 1
  }
  if found {
    (true, best_symbol, best_extra, best_add_bits)
  } else {
    (false, 0, 0, 0)
  }
}

///|
fn normalize_symbol_frequencies(
  freq : Array[Int],
  max_symbol : Int,
  table_log : Int,
) -> (Bool, Array[Int]) raise ZstdError {
  if max_symbol < 0 || max_symbol >= freq.length() {
    return (false, Array::new())
  }
  let table_size = 1 << table_log
  let active : Array[Int] = Array::new()
  let mut total = 0
  let mut s = 0
  while s <= max_symbol {
    let f = freq[s]
    if f < 0 {
      return (false, Array::new())
    }
    if f > 0 {
      active.push(s)
      total = total + f
    }
    s = s + 1
  }
  if active.length() < 2 || active.length() > table_size || total <= 0 {
    return (false, Array::new())
  }

  let normalized = Array::make(max_symbol + 1, 0)
  s = 0
  while s < active.length() {
    normalized[active[s]] = 1
    s = s + 1
  }

  let remaining = table_size - active.length()
  let mut allocated = 0
  s = 0
  while s < active.length() {
    let sym = active[s]
    let add = freq[sym] * remaining / total
    normalized[sym] = normalized[sym] + add
    allocated = allocated + add
    s = s + 1
  }

  let mut left = remaining - allocated
  let mut i = 0
  while left > 0 {
    let sym = active[i % active.length()]
    normalized[sym] = normalized[sym] + 1
    left = left - 1
    i = i + 1
  }

  let sum = normalized_counter_abs_sum(normalized, max_symbol)
  if sum != table_size {
    return (false, Array::new())
  }
  (true, normalized)
}

///|
fn build_sequence_fse_decode_table_with_symbols(
  normalized_counter : Array[Int],
  max_symbol : Int,
  table_log : Int,
  symbol_type : Int,
) -> (Array[Int], Array[Int], Array[Int], Array[Int], Array[Int]) raise ZstdError {
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
  (table_symbol, next_state, nb_add_bits, nb_bits, base_values)
}

///|
fn select_fse_state_path(
  symbols : Array[Int],
  table_symbol : Array[Int],
  next_state : Array[Int],
  nb_bits : Array[Int],
) -> (Bool, Array[Int], Array[Int], Array[Int]) {
  let n = symbols.length()
  if n <= 0 {
    return (false, Array::new(), Array::new(), Array::new())
  }
  let table_size = table_symbol.length()
  let states_by_symbol : Array[Array[Int]] = Array::new()
  let mut max_symbol = 0
  let mut i = 0
  while i < table_size {
    if table_symbol[i] > max_symbol {
      max_symbol = table_symbol[i]
    }
    i = i + 1
  }
  i = 0
  while i <= max_symbol {
    states_by_symbol.push(Array::new())
    i = i + 1
  }
  i = 0
  while i < table_size {
    let s = table_symbol[i]
    if s >= 0 && s < states_by_symbol.length() {
      states_by_symbol[s].push(i)
    }
    i = i + 1
  }

  let candidates : Array[Array[Int]] = Array::new()
  i = 0
  while i < n {
    let sym = symbols[i]
    if sym < 0 || sym >= states_by_symbol.length() {
      return (false, Array::new(), Array::new(), Array::new())
    }
    let c = states_by_symbol[sym]
    if c.length() == 0 {
      return (false, Array::new(), Array::new(), Array::new())
    }
    candidates.push(c)
    i = i + 1
  }

  let inf = 1 << 30
  let parent_idx_per_pos : Array[Array[Int]] = Array::new()
  let parent_bits_per_pos : Array[Array[Int]] = Array::new()
  let parent_nb_bits_per_pos : Array[Array[Int]] = Array::new()
  let mut cost_prev : Array[Int] = Array::new()

  let first_len = candidates[0].length()
  parent_idx_per_pos.push(Array::make(first_len, -1))
  parent_bits_per_pos.push(Array::make(first_len, 0))
  parent_nb_bits_per_pos.push(Array::make(first_len, 0))
  i = 0
  while i < first_len {
    cost_prev.push(0)
    i = i + 1
  }

  let mut pos = 1
  while pos < n {
    let cand_len = candidates[pos].length()
    let cost_curr = Array::make(cand_len, inf)
    let parent_idx = Array::make(cand_len, -1)
    let parent_bits = Array::make(cand_len, 0)
    let parent_nb = Array::make(cand_len, 0)

    let mut j = 0
    while j < cand_len {
      let st = candidates[pos][j]
      let mut k = 0
      while k < candidates[pos - 1].length() {
        let prev_st = candidates[pos - 1][k]
        let bits = nb_bits[prev_st]
        let range = if bits == 0 { 1 } else { 1 << bits }
        let start = next_state[prev_st]
        if st >= start && st < start + range {
          let cost = cost_prev[k] + bits
          if cost < cost_curr[j] {
            cost_curr[j] = cost
            parent_idx[j] = k
            parent_bits[j] = st - start
            parent_nb[j] = bits
          }
        }
        k = k + 1
      }
      j = j + 1
    }
    parent_idx_per_pos.push(parent_idx)
    parent_bits_per_pos.push(parent_bits)
    parent_nb_bits_per_pos.push(parent_nb)
    cost_prev = cost_curr
    pos = pos + 1
  }

  let mut best_idx = -1
  let mut best_cost = inf
  i = 0
  while i < cost_prev.length() {
    if cost_prev[i] < best_cost {
      best_cost = cost_prev[i]
      best_idx = i
    }
    i = i + 1
  }
  if best_idx < 0 || best_cost >= inf {
    return (false, Array::new(), Array::new(), Array::new())
  }

  let states = Array::make(n, 0)
  let trans_bits = if n > 1 { Array::make(n - 1, 0) } else { Array::new() }
  let trans_nb_bits = if n > 1 { Array::make(n - 1, 0) } else { Array::new() }

  let mut idx = best_idx
  pos = n - 1
  while pos >= 0 {
    states[pos] = candidates[pos][idx]
    if pos > 0 {
      let parent = parent_idx_per_pos[pos][idx]
      if parent < 0 {
        return (false, Array::new(), Array::new(), Array::new())
      }
      trans_bits[pos - 1] = parent_bits_per_pos[pos][idx]
      trans_nb_bits[pos - 1] = parent_nb_bits_per_pos[pos][idx]
      idx = parent
    }
    pos = pos - 1
  }
  (true, states, trans_bits, trans_nb_bits)
}

///|
fn build_compressed_sequence_source(
  values : Array[Int],
  symbol_type : Int,
) -> (Bool, Bytes, Int, Array[UInt], Array[Int], Array[Int], Array[Int]) raise ZstdError {
  let n = values.length()
  if n <= 0 {
    return (
      false,
      b"",
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }

  let (max_symbol, _) = sequence_symbol_limits(symbol_type)
  let freq = Array::make(max_symbol + 1, 0)
  let symbols : Array[Int] = Array::new()
  let extras : Array[UInt] = Array::new()
  let extra_bits : Array[Int] = Array::new()

  let mut i = 0
  while i < n {
    let (ok, sym, extra, add_bits) = encode_symbol_for_value(
      symbol_type,
      values[i],
    )
    if !ok {
      return (
        false,
        b"",
        0,
        Array::new(),
        Array::new(),
        Array::new(),
        Array::new(),
      )
    }
    symbols.push(sym)
    extras.push(extra)
    extra_bits.push(add_bits)
    freq[sym] = freq[sym] + 1
    i = i + 1
  }

  let mut highest_symbol = 0
  i = max_symbol
  while i >= 0 {
    if freq[i] > 0 {
      highest_symbol = i
      i = -1
    } else {
      i = i - 1
    }
  }
  let (norm_ok, normalized) = normalize_symbol_frequencies(
    freq, highest_symbol, compressed_mode_table_log,
  )
  if !norm_ok {
    return (
      false,
      b"",
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }
  let (table_symbol, next_state, nb_add_bits, nb_bits, _) = build_sequence_fse_decode_table_with_symbols(
    normalized, highest_symbol, compressed_mode_table_log, symbol_type,
  )
  let (path_ok, states, trans_bits, trans_nb_bits) = select_fse_state_path(
    symbols, table_symbol, next_state, nb_bits,
  )
  if !path_ok || states.length() != n {
    return (
      false,
      b"",
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }

  // Ensure chosen states are compatible with selected extra-bit widths.
  i = 0
  while i < n {
    if nb_add_bits[states[i]] != extra_bits[i] {
      return (
        false,
        b"",
        0,
        Array::new(),
        Array::new(),
        Array::new(),
        Array::new(),
      )
    }
    i = i + 1
  }

  let header = write_fse_ncount_header(
    normalized, highest_symbol, compressed_mode_table_log,
  )
  (true, header, states[0], extras, extra_bits, trans_bits, trans_nb_bits)
}

///|
fn build_general_compressed_fse_payload(
  src : Bytes,
  start : Int,
  block_len : Int,
  level : Int,
) -> Bytes raise ZstdError {
  if level < 13 || block_len < 96 {
    return b""
  }
  let ll_values : Array[Int] = Array::new()
  let off_values : Array[Int] = Array::new()
  let ml_values : Array[Int] = Array::new()
  let max_sequences = if level >= 20 { 24 } else { 16 }
  collect_greedy_sequences(
    src, start, block_len, ll_values, off_values, ml_values, max_sequences,
  )
  let seq_count = ll_values.length()
  if seq_count < 3 {
    return b""
  }

  let (
    ll_ok,
    ll_header,
    ll_init_state,
    ll_extras,
    ll_extra_bits,
    ll_trans_bits,
    ll_trans_nb_bits,
  ) = build_compressed_sequence_source(
    ll_values, sequence_symbol_literal_length,
  )
  if !ll_ok {
    return b""
  }
  let (
    off_ok,
    off_header,
    off_init_state,
    off_extras,
    off_extra_bits,
    off_trans_bits,
    off_trans_nb_bits,
  ) = build_compressed_sequence_source(off_values, sequence_symbol_offset)
  if !off_ok {
    return b""
  }
  let (
    ml_ok,
    ml_header,
    ml_init_state,
    ml_extras,
    ml_extra_bits,
    ml_trans_bits,
    ml_trans_nb_bits,
  ) = build_compressed_sequence_source(ml_values, sequence_symbol_match_length)
  if !ml_ok {
    return b""
  }

  let literals = build_literals_from_sequences(
    src, start, block_len, ll_values, ml_values,
  )

  let bits : Array[Int] = Array::new()
  append_bits_be(
    bits,
    ll_init_state.reinterpret_as_uint(),
    compressed_mode_table_log,
  )
  append_bits_be(
    bits,
    off_init_state.reinterpret_as_uint(),
    compressed_mode_table_log,
  )
  append_bits_be(
    bits,
    ml_init_state.reinterpret_as_uint(),
    compressed_mode_table_log,
  )

  let mut i = 0
  while i < seq_count {
    append_bits_be(bits, off_extras[i], off_extra_bits[i])
    append_bits_be(bits, ml_extras[i], ml_extra_bits[i])
    append_bits_be(bits, ll_extras[i], ll_extra_bits[i])
    if i + 1 < seq_count {
      append_bits_be(
        bits,
        ll_trans_bits[i].reinterpret_as_uint(),
        ll_trans_nb_bits[i],
      )
      append_bits_be(
        bits,
        ml_trans_bits[i].reinterpret_as_uint(),
        ml_trans_nb_bits[i],
      )
      append_bits_be(
        bits,
        off_trans_bits[i].reinterpret_as_uint(),
        off_trans_nb_bits[i],
      )
    }
    i = i + 1
  }
  let bitstream = build_reverse_bitstream(bits)

  let payload : Array[Byte] = Array::new()
  append_best_literals_section(payload, literals)
  append_sequence_count(payload, seq_count)
  payload.push((0xA8 : UInt).to_byte()) // all compressed sequence modes
  append_bytes(payload, ll_header, 0, ll_header.length())
  append_bytes(payload, off_header, 0, off_header.length())
  append_bytes(payload, ml_header, 0, ml_header.length())
  append_bytes(payload, bitstream, 0, bitstream.length())
  Bytes::from_array(payload)
}
