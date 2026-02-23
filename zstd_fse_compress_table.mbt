///|
fn build_fse_compression_table_from_normalized(
  normalized_counter : Array[Int],
  max_symbol : Int,
  table_log : Int,
) -> (Bool, Array[Int], Array[Int], Array[Int]) {
  if table_log < fse_min_table_log || table_log > fse_table_log_absolute_max {
    return (false, Array::new(), Array::new(), Array::new())
  }
  if max_symbol < 0 || max_symbol >= normalized_counter.length() {
    return (false, Array::new(), Array::new(), Array::new())
  }
  let table_size = (1 : Int) << table_log
  let table_mask = table_size - 1
  let step = (table_size >> 1) + (table_size >> 3) + 3
  let cumul = Array::make(max_symbol + 2, 0)
  let table_symbol = Array::make(table_size, 0)
  let mut high_threshold = table_size - 1
  let mut u = 1
  while u <= max_symbol + 1 {
    let count = normalized_counter[u - 1]
    let prev = cumul[u - 1]
    if count == -1 {
      cumul[u] = prev + 1
      if high_threshold < 0 {
        return (false, Array::new(), Array::new(), Array::new())
      }
      table_symbol[high_threshold] = u - 1
      high_threshold = high_threshold - 1
    } else if count >= 0 {
      cumul[u] = prev + count
    } else {
      return (false, Array::new(), Array::new(), Array::new())
    }
    u = u + 1
  }
  if cumul[max_symbol + 1] != table_size {
    return (false, Array::new(), Array::new(), Array::new())
  }
  cumul[max_symbol + 1] = table_size + 1

  let mut position = 0
  let mut symbol = 0
  while symbol <= max_symbol {
    let freq = normalized_counter[symbol]
    if freq < -1 {
      return (false, Array::new(), Array::new(), Array::new())
    }
    if freq > 0 {
      let mut n = 0
      while n < freq {
        table_symbol[position] = symbol
        position = (position + step) & table_mask
        while position > high_threshold {
          position = (position + step) & table_mask
        }
        n = n + 1
      }
    }
    symbol = symbol + 1
  }
  if position != 0 {
    return (false, Array::new(), Array::new(), Array::new())
  }

  let state_table = Array::make(table_size, 0)
  u = 0
  while u < table_size {
    let s = table_symbol[u]
    if s < 0 || s > max_symbol {
      return (false, Array::new(), Array::new(), Array::new())
    }
    let idx = cumul[s]
    if idx < 0 || idx >= table_size {
      return (false, Array::new(), Array::new(), Array::new())
    }
    state_table[idx] = table_size + u
    cumul[s] = idx + 1
    u = u + 1
  }

  let delta_nb_bits = Array::make(max_symbol + 1, 0)
  let delta_find_state = Array::make(max_symbol + 1, 0)
  let mut total = 0
  symbol = 0
  while symbol <= max_symbol {
    let count = normalized_counter[symbol]
    if count == 0 {
      delta_nb_bits[symbol] = ((table_log + 1) << 16) - table_size
      delta_find_state[symbol] = 0
    } else if count == -1 || count == 1 {
      delta_nb_bits[symbol] = (table_log << 16) - table_size
      delta_find_state[symbol] = total - 1
      total = total + 1
    } else if count > 1 {
      let max_bits_out = table_log - high_bit_floor_non_zero(count - 1)
      let min_state_plus = count << max_bits_out
      delta_nb_bits[symbol] = (max_bits_out << 16) - min_state_plus
      delta_find_state[symbol] = total - count
      total = total + count
    } else {
      return (false, Array::new(), Array::new(), Array::new())
    }
    symbol = symbol + 1
  }
  if total != table_size {
    return (false, Array::new(), Array::new(), Array::new())
  }
  (true, state_table, delta_nb_bits, delta_find_state)
}

///|
fn fse_init_cstate2_with_table(
  state_table : Array[Int],
  delta_nb_bits : Array[Int],
  delta_find_state : Array[Int],
  symbol : Int,
) -> (Bool, Int) {
  let table_size = state_table.length()
  if table_size <= 0 ||
    symbol < 0 ||
    symbol >= delta_nb_bits.length() ||
    symbol >= delta_find_state.length() {
    return (false, 0)
  }
  let delta = delta_nb_bits[symbol]
  let nb_bits_out = (delta + (1 << 15)) >> 16
  if nb_bits_out < 0 {
    return (false, 0)
  }
  let state_base = (nb_bits_out << 16) - delta
  let idx = (state_base >> nb_bits_out) + delta_find_state[symbol]
  if idx < 0 || idx >= table_size {
    return (false, 0)
  }
  let state = state_table[idx]
  if state < table_size || state >= table_size * 2 {
    return (false, 0)
  }
  (true, state)
}

///|
fn fse_encode_symbol_with_table(
  state : Int,
  symbol : Int,
  state_table : Array[Int],
  delta_nb_bits : Array[Int],
  delta_find_state : Array[Int],
) -> (Bool, Int, Int, Int) {
  let table_size = state_table.length()
  if table_size <= 0 ||
    state < table_size ||
    state >= table_size * 2 ||
    symbol < 0 ||
    symbol >= delta_nb_bits.length() ||
    symbol >= delta_find_state.length() {
    return (false, 0, 0, 0)
  }
  let delta = delta_nb_bits[symbol]
  let nb_bits_out = (state + delta) >> 16
  if nb_bits_out < 0 {
    return (false, 0, 0, 0)
  }
  let bits = if nb_bits_out == 0 { 0 } else { state & ((1 << nb_bits_out) - 1) }
  let idx = (state >> nb_bits_out) + delta_find_state[symbol]
  if idx < 0 || idx >= table_size {
    return (false, 0, 0, 0)
  }
  let new_state = state_table[idx]
  if new_state < table_size || new_state >= table_size * 2 {
    return (false, 0, 0, 0)
  }
  (true, bits, nb_bits_out, new_state)
}

///|
fn build_reference_fse_state_path(
  symbols : Array[Int],
  table_symbol : Array[Int],
  next_state : Array[Int],
  nb_bits : Array[Int],
  state_table : Array[Int],
  delta_nb_bits : Array[Int],
  delta_find_state : Array[Int],
) -> (Bool, Int, Array[Int], Array[Int], Array[Int]) {
  let n = symbols.length()
  let table_size = table_symbol.length()
  if n <= 0 ||
    table_size <= 0 ||
    next_state.length() != table_size ||
    nb_bits.length() != table_size ||
    state_table.length() != table_size {
    return (false, 0, Array::new(), Array::new(), Array::new())
  }
  let last_symbol = symbols[n - 1]
  let (init_ok, init_state_c) = fse_init_cstate2_with_table(
    state_table, delta_nb_bits, delta_find_state, last_symbol,
  )
  if !init_ok {
    return (false, 0, Array::new(), Array::new(), Array::new())
  }
  let trans_bits = if n > 1 { Array::make(n - 1, 0) } else { Array::new() }
  let trans_nb_bits = if n > 1 { Array::make(n - 1, 0) } else { Array::new() }
  let mut cstate = init_state_c
  let mut i = n - 2
  while i >= 0 {
    let symbol = symbols[i]
    let (ok, bits, nb, new_state) = fse_encode_symbol_with_table(
      cstate, symbol, state_table, delta_nb_bits, delta_find_state,
    )
    if !ok {
      return (false, 0, Array::new(), Array::new(), Array::new())
    }
    trans_bits[i] = bits
    trans_nb_bits[i] = nb
    cstate = new_state
    i = i - 1
  }

  let init_state = cstate - table_size
  if init_state < 0 || init_state >= table_size {
    return (false, 0, Array::new(), Array::new(), Array::new())
  }

  let states = Array::make(n, 0)
  states[0] = init_state
  i = 0
  while i < n {
    let st = states[i]
    if st < 0 || st >= table_size || symbols[i] != table_symbol[st] {
      return (false, 0, Array::new(), Array::new(), Array::new())
    }
    if i + 1 < n {
      let bits = trans_bits[i]
      let nb = trans_nb_bits[i]
      if nb != nb_bits[st] {
        return (false, 0, Array::new(), Array::new(), Array::new())
      }
      let range = if nb == 0 { 1 } else { 1 << nb }
      if bits < 0 || bits >= range {
        return (false, 0, Array::new(), Array::new(), Array::new())
      }
      let next = next_state[st] + bits
      if next < 0 || next >= table_size {
        return (false, 0, Array::new(), Array::new(), Array::new())
      }
      states[i + 1] = next
    }
    i = i + 1
  }
  (true, init_state, trans_bits, trans_nb_bits, states)
}
