///|
fn collect_predefined_candidates_for_value(
  symbol_type : Int,
  value : Int,
  states : Array[Int],
  extras : Array[UInt],
  nb_add_bits : Array[Int],
  next_states : Array[Int],
  nb_state_bits : Array[Int],
) -> Unit raise ZstdError {
  let limit = predefined_state_limit(symbol_type)
  let mut state = 0
  while state <= limit {
    let (next_state, add_bits, state_bits, base) = predefined_sequence_entry(
      symbol_type, state,
    )
    let can_use = if symbol_type == sequence_symbol_offset {
      // Keep direct-offset states only; repcode-special states are not encoded here.
      add_bits > 1
    } else {
      true
    }
    if can_use && value >= base {
      let span = if add_bits == 0 {
        0
      } else {
        (((1 : UInt64) << add_bits) - (1 : UInt64)).to_int()
      }
      let limit_value = base + span
      if value <= limit_value {
        states.push(state)
        extras.push((value - base).reinterpret_as_uint())
        nb_add_bits.push(add_bits)
        next_states.push(next_state)
        nb_state_bits.push(state_bits)
      }
    }
    state = state + 1
  }
}

///|
fn select_predefined_state_path(
  values : Array[Int],
  symbol_type : Int,
) -> (Bool, Array[Int], Array[UInt], Array[Int], Array[Int], Array[Int]) raise ZstdError {
  let n = values.length()
  if n <= 0 {
    return (
      false,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }

  let states_per_pos : Array[Array[Int]] = Array::new()
  let extras_per_pos : Array[Array[UInt]] = Array::new()
  let add_bits_per_pos : Array[Array[Int]] = Array::new()
  let next_states_per_pos : Array[Array[Int]] = Array::new()
  let state_bits_per_pos : Array[Array[Int]] = Array::new()

  let mut i = 0
  while i < n {
    let cand_states : Array[Int] = Array::new()
    let cand_extras : Array[UInt] = Array::new()
    let cand_add_bits : Array[Int] = Array::new()
    let cand_next_states : Array[Int] = Array::new()
    let cand_state_bits : Array[Int] = Array::new()
    collect_predefined_candidates_for_value(
      symbol_type,
      values[i],
      cand_states,
      cand_extras,
      cand_add_bits,
      cand_next_states,
      cand_state_bits,
    )
    if cand_states.length() == 0 {
      return (
        false,
        Array::new(),
        Array::new(),
        Array::new(),
        Array::new(),
        Array::new(),
      )
    }
    states_per_pos.push(cand_states)
    extras_per_pos.push(cand_extras)
    add_bits_per_pos.push(cand_add_bits)
    next_states_per_pos.push(cand_next_states)
    state_bits_per_pos.push(cand_state_bits)
    i = i + 1
  }

  let inf = 1 << 30
  let parent_idx_per_pos : Array[Array[Int]] = Array::new()
  let parent_bits_per_pos : Array[Array[Int]] = Array::new()
  let mut cost_prev : Array[Int] = Array::new()

  let cand0_len = states_per_pos[0].length()
  parent_idx_per_pos.push(Array::make(cand0_len, -1))
  parent_bits_per_pos.push(Array::make(cand0_len, 0))
  i = 0
  while i < cand0_len {
    cost_prev.push(add_bits_per_pos[0][i])
    i = i + 1
  }

  let mut pos = 1
  while pos < n {
    let cand_len = states_per_pos[pos].length()
    let cost_curr = Array::make(cand_len, inf)
    let parent_idx = Array::make(cand_len, -1)
    let parent_bits = Array::make(cand_len, 0)

    let mut j = 0
    while j < cand_len {
      let state_j = states_per_pos[pos][j]
      let mut k = 0
      while k < cost_prev.length() {
        let prev_cost = cost_prev[k]
        if prev_cost < inf {
          let prev_next = next_states_per_pos[pos - 1][k]
          let prev_state_bits = state_bits_per_pos[pos - 1][k]
          let range = if prev_state_bits == 0 {
            1
          } else {
            1 << prev_state_bits
          }
          if state_j >= prev_next && state_j < prev_next + range {
            let trans_bits = state_j - prev_next
            let cost = prev_cost + add_bits_per_pos[pos][j] + prev_state_bits
            if cost < cost_curr[j] {
              cost_curr[j] = cost
              parent_idx[j] = k
              parent_bits[j] = trans_bits
            }
          }
        }
        k = k + 1
      }
      j = j + 1
    }

    parent_idx_per_pos.push(parent_idx)
    parent_bits_per_pos.push(parent_bits)
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
    return (
      false,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }

  let states = Array::make(n, 0)
  let extras = Array::make(n, (0 : UInt))
  let extra_bits = Array::make(n, 0)
  let trans_bits = if n > 1 { Array::make(n - 1, 0) } else { Array::new() }
  let trans_nb_bits = if n > 1 { Array::make(n - 1, 0) } else { Array::new() }

  let mut idx = best_idx
  pos = n - 1
  while pos >= 0 {
    states[pos] = states_per_pos[pos][idx]
    extras[pos] = extras_per_pos[pos][idx]
    extra_bits[pos] = add_bits_per_pos[pos][idx]
    if pos > 0 {
      let parent = parent_idx_per_pos[pos][idx]
      if parent < 0 {
        return (
          false,
          Array::new(),
          Array::new(),
          Array::new(),
          Array::new(),
          Array::new(),
        )
      }
      trans_bits[pos - 1] = parent_bits_per_pos[pos][idx]
      trans_nb_bits[pos - 1] = state_bits_per_pos[pos - 1][parent]
      idx = parent
    }
    pos = pos - 1
  }

  (true, states, extras, extra_bits, trans_bits, trans_nb_bits)
}

///|
fn build_literals_from_sequences(
  src : Bytes,
  start : Int,
  block_len : Int,
  ll_values : Array[Int],
  ml_values : Array[Int],
) -> Bytes raise ZstdError {
  if ll_values.length() != ml_values.length() {
    raise CorruptionDetected
  }
  let literals : Array[Byte] = Array::new()
  let mut consumed = 0
  let mut i = 0
  while i < ll_values.length() {
    let ll = ll_values[i]
    if ll < 0 || ml_values[i] < 3 || consumed + ll + ml_values[i] > block_len {
      raise CorruptionDetected
    }
    append_bytes(literals, src, start + consumed, ll)
    consumed = consumed + ll + ml_values[i]
    i = i + 1
  }
  if consumed > block_len {
    raise CorruptionDetected
  }
  let tail_len = block_len - consumed
  if tail_len > 0 {
    append_bytes(literals, src, start + consumed, tail_len)
  }
  Bytes::from_array(literals)
}

///|
fn build_general_predefined_payload(
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
  if (level < 12 && dictionary_history.length() == 0) || block_len < 64 {
    return b""
  }

  let ll_values : Array[Int] = Array::new()
  let off_values : Array[Int] = Array::new()
  let ml_values : Array[Int] = Array::new()
  let max_sequences_base = predefined_multi_sequence_cap(level, block_len)
  let max_sequences = if dictionary_history.length() > 0 && level < 10 {
    sequence_cap_by_block(63, block_len)
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
  if seq_count < 2 {
    return b""
  }

  let (
    ll_ok,
    ll_states,
    ll_extras,
    ll_extra_bits,
    ll_trans_bits,
    ll_trans_nb_bits,
  ) = select_predefined_state_path(ll_values, sequence_symbol_literal_length)
  if !ll_ok {
    return b""
  }
  let (
    off_ok,
    off_states,
    off_extras,
    off_extra_bits,
    off_trans_bits,
    off_trans_nb_bits,
  ) = select_predefined_offset_state_path(
    off_values, ll_values, rep1, rep2, rep3,
  )
  if !off_ok {
    return b""
  }
  let (
    ml_ok,
    ml_states,
    ml_extras,
    ml_extra_bits,
    ml_trans_bits,
    ml_trans_nb_bits,
  ) = select_predefined_state_path(ml_values, sequence_symbol_match_length)
  if !ml_ok {
    return b""
  }

  let literals = build_literals_from_sequences(
    src, start, block_len, ll_values, ml_values,
  )
  let extra_bits : Array[Int] = Array::new()
  append_bits_be(
    extra_bits,
    ll_states[0].reinterpret_as_uint(),
    ll_predefined_table_log,
  )
  append_bits_be(
    extra_bits,
    off_states[0].reinterpret_as_uint(),
    of_predefined_table_log,
  )
  append_bits_be(
    extra_bits,
    ml_states[0].reinterpret_as_uint(),
    ml_predefined_table_log,
  )

  let mut i = 0
  while i < seq_count {
    append_bits_be(extra_bits, off_extras[i], off_extra_bits[i])
    append_bits_be(extra_bits, ml_extras[i], ml_extra_bits[i])
    append_bits_be(extra_bits, ll_extras[i], ll_extra_bits[i])
    if i + 1 < seq_count {
      append_bits_be(
        extra_bits,
        ll_trans_bits[i].reinterpret_as_uint(),
        ll_trans_nb_bits[i],
      )
      append_bits_be(
        extra_bits,
        ml_trans_bits[i].reinterpret_as_uint(),
        ml_trans_nb_bits[i],
      )
      append_bits_be(
        extra_bits,
        off_trans_bits[i].reinterpret_as_uint(),
        off_trans_nb_bits[i],
      )
    }
    i = i + 1
  }

  let bitstream = build_reverse_bitstream(extra_bits)
  let payload : Array[Byte] = Array::new()
  append_best_literals_section(payload, literals)
  append_sequence_count(payload, seq_count)
  payload.push((0 : UInt).to_byte()) // all predefined sequence modes
  append_bytes(payload, bitstream, 0, bitstream.length())
  Bytes::from_array(payload)
}
