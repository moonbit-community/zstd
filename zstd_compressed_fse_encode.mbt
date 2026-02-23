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
fn choose_offset_symbols_with_repcodes(
  off_values : Array[Int],
  ll_values : Array[Int],
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (Bool, Array[Int], Array[UInt], Array[Int]) raise ZstdError {
  if off_values.length() <= 0 || ll_values.length() != off_values.length() {
    return (false, Array::new(), Array::new(), Array::new())
  }
  let symbols : Array[Int] = Array::new()
  let extras : Array[UInt] = Array::new()
  let extra_bits : Array[Int] = Array::new()
  let mut r1 = rep1
  let mut r2 = rep2
  let mut r3 = rep3

  let mut i = 0
  while i < off_values.length() {
    let ll0 = ll_values[i] == 0
    let off_base = finalize_offset_off_base(off_values[i], ll0, r1, r2, r3)
    let (symbol, extra, add_bits) = offset_symbol_from_off_base(off_base)
    symbols.push(symbol.reinterpret_as_int())
    extras.push(extra)
    extra_bits.push(add_bits)
    let (nr1, nr2, nr3) = update_repcodes_with_off_base(
      ll0, off_base, r1, r2, r3,
    )
    r1 = nr1
    r2 = nr2
    r3 = nr3
    i = i + 1
  }
  (true, symbols, extras, extra_bits)
}

///|
fn normalize_symbol_frequencies(
  freq : Array[Int],
  max_symbol : Int,
  table_log : Int,
  use_low_prob_count : Bool,
) -> (Bool, Array[Int]) raise ZstdError {
  if max_symbol < 0 || max_symbol >= freq.length() {
    return (false, Array::new())
  }
  let table_size = 1 << table_log
  let mut total = 0
  let mut active = 0
  let mut s = 0
  while s <= max_symbol {
    let c = freq[s]
    if c < 0 {
      return (false, Array::new())
    }
    if c > 0 {
      active = active + 1
      total = total + c
    }
    s = s + 1
  }
  if active < 2 || active > table_size || total <= 1 {
    return (false, Array::new())
  }

  let normalized = Array::make(max_symbol + 1, 0)
  let rtb = [0, 473195, 504333, 520860, 550000, 700000, 750000, 830000]
  let low_prob_count = if use_low_prob_count { -1 } else { 1 }
  let scale = 62 - table_log
  let step = ((1 : UInt64) << 62) / total.to_uint64()
  let v_step = if scale >= 20 {
    (1 : UInt64) << (scale - 20)
  } else {
    (1 : UInt64)
  }
  let mut still_to_distribute = table_size
  let mut largest = 0
  let mut largest_p = 0
  let low_threshold = total >> table_log
  s = 0
  while s <= max_symbol {
    let count = freq[s]
    if count == 0 {
      normalized[s] = 0
      s = s + 1
      continue
    }
    if count <= low_threshold {
      normalized[s] = low_prob_count
      still_to_distribute = still_to_distribute - 1
      s = s + 1
      continue
    }
    let scaled = count.to_uint64() * step
    let mut proba = (scaled >> scale).to_int()
    if proba < 8 {
      let rest_to_beat = v_step * rtb[proba].to_uint64()
      let base = proba.to_uint64() << scale
      if scaled > base && scaled - base > rest_to_beat {
        proba = proba + 1
      }
    }
    if proba > largest_p {
      largest_p = proba
      largest = s
    }
    normalized[s] = proba
    still_to_distribute = still_to_distribute - proba
    s = s + 1
  }

  if -still_to_distribute >= normalized[largest] >> 1 {
    let not_yet_assigned = -2
    let mut distributed = 0
    let mut total_m2 = total
    let mut low_one = (total_m2 * 3) >> (table_log + 1)
    s = 0
    while s <= max_symbol {
      let count = freq[s]
      if count == 0 {
        normalized[s] = 0
      } else if count <= low_threshold {
        normalized[s] = low_prob_count
        distributed = distributed + 1
        total_m2 = total_m2 - count
      } else if count <= low_one {
        normalized[s] = 1
        distributed = distributed + 1
        total_m2 = total_m2 - count
      } else {
        normalized[s] = not_yet_assigned
      }
      s = s + 1
    }
    let mut to_distribute = table_size - distributed
    if to_distribute == 0 {
      let sum = normalized_counter_abs_sum(normalized, max_symbol)
      if sum == table_size {
        return (true, normalized)
      }
      return (false, Array::new())
    }

    if total_m2 > 0 && total_m2 / to_distribute > low_one {
      low_one = total_m2 * 3 / (to_distribute * 2)
      s = 0
      while s <= max_symbol {
        if normalized[s] == not_yet_assigned && freq[s] <= low_one {
          normalized[s] = 1
          distributed = distributed + 1
          total_m2 = total_m2 - freq[s]
        }
        s = s + 1
      }
      to_distribute = table_size - distributed
    }

    if distributed == max_symbol + 1 {
      let mut max_v = 0
      let mut max_c = 0
      s = 0
      while s <= max_symbol {
        if freq[s] > max_c {
          max_v = s
          max_c = freq[s]
        }
        s = s + 1
      }
      normalized[max_v] = normalized[max_v] + to_distribute
    } else if total_m2 == 0 {
      s = 0
      while to_distribute > 0 {
        if normalized[s] > 0 {
          normalized[s] = normalized[s] + 1
          to_distribute = to_distribute - 1
        }
        s = s + 1
        if s > max_symbol {
          s = 0
        }
      }
    } else {
      let v_step_log = 62 - table_log
      let mid = ((1 : UInt64) << (v_step_log - 1)) - 1
      let r_step = (
          ((1 : UInt64) << v_step_log) * to_distribute.to_uint64() + mid
        ) /
        total_m2.to_uint64()
      let mut tmp_total = mid
      s = 0
      while s <= max_symbol {
        if normalized[s] == not_yet_assigned {
          let end = tmp_total + freq[s].to_uint64() * r_step
          let s_start = (tmp_total >> v_step_log).to_int()
          let s_end = (end >> v_step_log).to_int()
          let weight = s_end - s_start
          if weight < 1 {
            return (false, Array::new())
          }
          normalized[s] = weight
          tmp_total = end
        }
        s = s + 1
      }
    }
  } else {
    normalized[largest] = normalized[largest] + still_to_distribute
  }

  let sum = normalized_counter_abs_sum(normalized, max_symbol)
  if sum != table_size {
    return (false, Array::new())
  }
  (true, normalized)
}

///|
fn high_bit_floor_non_zero(value : Int) -> Int {
  if value <= 0 {
    return -1
  }
  let mut bit = 0
  let mut v = value
  while v > 1 {
    v = v >> 1
    bit = bit + 1
  }
  bit
}

///|
fn choose_compressed_table_log(
  seq_count : Int,
  max_symbol : Int,
  table_log_max : Int,
) -> Int {
  if seq_count <= 1 {
    return fse_min_table_log
  }
  let mut table_log = if table_log_max == 0 {
    fse_default_table_log
  } else {
    table_log_max
  }
  let src_hb = high_bit_floor_non_zero(seq_count - 1)
  let max_bits_src = if src_hb > 2 { src_hb - 2 } else { 0 }
  if max_bits_src < table_log {
    table_log = max_bits_src
  }
  let min_bits_src = high_bit_floor_non_zero(seq_count) + 1
  let min_bits_symbols = if max_symbol > 0 {
    high_bit_floor_non_zero(max_symbol) + 2
  } else {
    2
  }
  let min_bits = if min_bits_src < min_bits_symbols {
    min_bits_src
  } else {
    min_bits_symbols
  }
  if min_bits > table_log {
    table_log = min_bits
  }
  if table_log < fse_min_table_log {
    table_log = fse_min_table_log
  }
  if table_log > fse_table_log_absolute_max {
    table_log = fse_table_log_absolute_max
  }
  table_log
}

///|
let fse_default_table_log = 11

///|
fn should_use_low_prob_count(seq_count : Int) -> Bool {
  seq_count >= 2048
}

///|
fn count_active_symbols(freq : Array[Int], highest_symbol : Int) -> Int {
  let mut count = 0
  let mut i = 0
  while i <= highest_symbol {
    if freq[i] > 0 {
      count = count + 1
    }
    i = i + 1
  }
  count
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
) -> (Bool, Bytes, Int, Int, Array[UInt], Array[Int], Array[Int], Array[Int]) raise ZstdError {
  let symbols : Array[Int] = Array::new()
  let extras : Array[UInt] = Array::new()
  let extra_bits : Array[Int] = Array::new()
  let mut i = 0
  while i < values.length() {
    let (ok, sym, extra, add_bits) = encode_symbol_for_value(
      symbol_type,
      values[i],
    )
    if !ok {
      return (
        false,
        b"",
        0,
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
    i = i + 1
  }
  build_compressed_sequence_source_from_symbols(
    symbol_type, symbols, extras, extra_bits,
  )
}

///|
fn build_compressed_offset_sequence_source_with_repcodes(
  off_values : Array[Int],
  ll_values : Array[Int],
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (Bool, Bytes, Int, Int, Array[UInt], Array[Int], Array[Int], Array[Int]) raise ZstdError {
  let (ok, symbols, extras, extra_bits) = choose_offset_symbols_with_repcodes(
    off_values, ll_values, rep1, rep2, rep3,
  )
  if !ok {
    return (
      false,
      b"",
      0,
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }
  build_compressed_sequence_source_from_symbols(
    sequence_symbol_offset, symbols, extras, extra_bits,
  )
}

///|
fn build_compressed_sequence_source_from_symbols(
  symbol_type : Int,
  symbols : Array[Int],
  extras : Array[UInt],
  extra_bits : Array[Int],
) -> (Bool, Bytes, Int, Int, Array[UInt], Array[Int], Array[Int], Array[Int]) raise ZstdError {
  let n = symbols.length()
  if n <= 0 || extras.length() != n || extra_bits.length() != n {
    return (
      false,
      b"",
      0,
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }

  let (max_symbol, table_log_max) = sequence_symbol_limits(symbol_type)
  let freq = Array::make(max_symbol + 1, 0)

  let mut i = 0
  while i < n {
    let sym = symbols[i]
    if sym < 0 || sym > max_symbol {
      return (
        false,
        b"",
        0,
        0,
        Array::new(),
        Array::new(),
        Array::new(),
        Array::new(),
      )
    }
    freq[sym] = freq[sym] + 1
    i = i + 1
  }
  let norm_freq = Array::make(max_symbol + 1, 0)
  i = 0
  while i <= max_symbol {
    norm_freq[i] = freq[i]
    i = i + 1
  }
  let mut norm_seq_count = n
  let init_symbol = symbols[n - 1]
  if init_symbol < 0 || init_symbol > max_symbol {
    return (
      false,
      b"",
      0,
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }
  if norm_freq[init_symbol] > 1 {
    norm_freq[init_symbol] = norm_freq[init_symbol] - 1
    norm_seq_count = norm_seq_count - 1
  }
  if norm_seq_count <= 1 {
    return (
      false,
      b"",
      0,
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }

  let mut highest_symbol = 0
  i = max_symbol
  while i >= 0 {
    if norm_freq[i] > 0 {
      highest_symbol = i
      i = -1
    } else {
      i = i - 1
    }
  }
  let active_symbols = count_active_symbols(norm_freq, highest_symbol)
  if active_symbols < 2 {
    return (
      false,
      b"",
      0,
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }
  let table_log = choose_compressed_table_log(n, highest_symbol, table_log_max)
  let (norm_ok, normalized) = normalize_symbol_frequencies(
    norm_freq,
    highest_symbol,
    table_log,
    should_use_low_prob_count(norm_seq_count),
  )
  if !norm_ok {
    return (
      false,
      b"",
      0,
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }
  let (table_symbol, next_state, nb_add_bits, nb_bits, _) = build_sequence_fse_decode_table_with_symbols(
    normalized, highest_symbol, table_log, symbol_type,
  )
  let (path_ok, states, trans_bits, trans_nb_bits) = select_fse_state_path(
    symbols, table_symbol, next_state, nb_bits,
  )
  if !path_ok || states.length() != n {
    return (
      false,
      b"",
      0,
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
        0,
        Array::new(),
        Array::new(),
        Array::new(),
        Array::new(),
      )
    }
    i = i + 1
  }

  let header = write_fse_ncount_header(normalized, highest_symbol, table_log)
  (
    true,
    header,
    states[0],
    table_log,
    extras,
    extra_bits,
    trans_bits,
    trans_nb_bits,
  )
}

///|
fn build_general_compressed_fse_payload(
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
  if (level < 13 && dictionary_history.length() == 0) || block_len < 96 {
    return b""
  }
  let ll_values : Array[Int] = Array::new()
  let off_values : Array[Int] = Array::new()
  let ml_values : Array[Int] = Array::new()
  let max_sequences_base = compressed_fse_sequence_cap(level, block_len)
  let max_sequences = if dictionary_history.length() > 0 && level < 10 {
    sequence_cap_by_block(48, block_len)
  } else {
    max_sequences_base
  }
  let search_depth_base = greedy_sequence_search_depth(
    level,
    block_len,
    enable_long_distance_matching~,
  )
  let search_depth = search_depth_base
  let min_match = greedy_sequence_min_match(level, block_len)
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
  )
  let seq_count = ll_values.length()
  if seq_count < 3 {
    return b""
  }

  let (
    ll_ok,
    ll_header,
    ll_init_state,
    ll_table_log,
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
    off_table_log,
    off_extras,
    off_extra_bits,
    off_trans_bits,
    off_trans_nb_bits,
  ) = build_compressed_offset_sequence_source_with_repcodes(
    off_values, ll_values, rep1, rep2, rep3,
  )
  if !off_ok {
    return b""
  }
  let (
    ml_ok,
    ml_header,
    ml_init_state,
    ml_table_log,
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
  append_bits_be(bits, ll_init_state.reinterpret_as_uint(), ll_table_log)
  append_bits_be(bits, off_init_state.reinterpret_as_uint(), off_table_log)
  append_bits_be(bits, ml_init_state.reinterpret_as_uint(), ml_table_log)

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
