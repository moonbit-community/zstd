///|
fn int_arrays_equal(lhs : Array[Int], rhs : Array[Int]) -> Bool {
  if lhs.length() != rhs.length() {
    return false
  }
  let mut i = 0
  while i < lhs.length() {
    if lhs[i] != rhs[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn unique_symbols_from_table(
  table_symbols : Array[Int],
  max_symbol : Int,
) -> Array[Int] {
  if max_symbol < 0 {
    return Array::new()
  }
  let seen = Array::make(max_symbol + 1, false)
  let out : Array[Int] = Array::new()
  let mut i = 0
  while i < table_symbols.length() {
    let s = table_symbols[i]
    if s >= 0 && s <= max_symbol && !seen[s] {
      seen[s] = true
      out.push(s)
    }
    i = i + 1
  }
  out
}

///|
fn even_index_symbols(values : Array[Int]) -> Array[Int] {
  let out : Array[Int] = Array::new()
  let mut i = 0
  while i < values.length() {
    out.push(values[i])
    i = i + 2
  }
  out
}

///|
fn odd_index_symbols(values : Array[Int]) -> Array[Int] {
  let out : Array[Int] = Array::new()
  let mut i = 1
  while i < values.length() {
    out.push(values[i])
    i = i + 2
  }
  out
}

///|
fn append_with_extra_symbol(values : Array[Int], symbol : Int) -> Array[Int] {
  let out : Array[Int] = Array::new()
  let mut i = 0
  while i < values.length() {
    out.push(values[i])
    i = i + 1
  }
  out.push(symbol)
  out
}

///|
fn build_weight_normalized_counter(
  freq : Array[Int],
  active_symbols : Array[Int],
  total : Int,
  highest_symbol : Int,
  table_log : Int,
  offset : Int,
) -> (Bool, Array[Int]) {
  if total <= 0 || highest_symbol < 0 || highest_symbol >= freq.length() {
    return (false, Array::new())
  }
  if active_symbols.length() < 2 {
    return (false, Array::new())
  }
  let table_size = 1 << table_log
  if table_size < active_symbols.length() {
    return (false, Array::new())
  }

  let normalized = Array::make(highest_symbol + 1, 0)
  let mut i = 0
  while i < active_symbols.length() {
    let sym = active_symbols[i]
    if sym < 0 || sym > highest_symbol || freq[sym] <= 0 {
      return (false, Array::new())
    }
    normalized[sym] = 1
    i = i + 1
  }

  let remaining = table_size - active_symbols.length()
  let mut allocated = 0
  i = 0
  while i < active_symbols.length() {
    let sym = active_symbols[i]
    let add = freq[sym] * remaining / total
    normalized[sym] = normalized[sym] + add
    allocated = allocated + add
    i = i + 1
  }

  let mut left = remaining - allocated
  i = 0
  while left > 0 {
    let sym = active_symbols[(offset + i) % active_symbols.length()]
    normalized[sym] = normalized[sym] + 1
    left = left - 1
    i = i + 1
  }
  let mut sum = 0
  i = 0
  while i <= highest_symbol {
    sum = sum + normalized[i]
    i = i + 1
  }
  if sum != table_size {
    return (false, Array::new())
  }
  (true, normalized)
}

///|
fn decode_weight_fse_bitstream_matches(
  bitstream : Bytes,
  table_log : Int,
  next_state : Array[Int],
  nb_bits : Array[Int],
  table_symbols : Array[Int],
  expected : Array[Int],
) -> Bool {
  if bitstream.length() <= 0 {
    return false
  }
  let decoded = try? decode_fse_symbol_stream_reverse(
    bitstream,
    0,
    bitstream.length(),
    table_log,
    next_state,
    nb_bits,
    table_symbols,
    255,
  )
  match decoded {
    Ok(out) => int_arrays_equal(out, expected)
    Err(_) => false
  }
}

///|
fn try_update_weight_fse_bitstream_best_with_ops(
  best : Bytes,
  op_values : Array[Int],
  op_counts : Array[Int],
  table_log : Int,
  next_state : Array[Int],
  nb_bits : Array[Int],
  table_symbols : Array[Int],
  expected : Array[Int],
) -> Bytes raise ZstdError {
  if op_values.length() != op_counts.length() || op_values.length() == 0 {
    return best
  }
  let mut current_best = best
  let mut mode = 0
  while mode < 6 {
    let reverse_order = mode == 2 || mode == 3 || mode == 5
    let use_lsb = mode == 1 || mode == 3 || mode == 4 || mode == 5
    let use_forward_pack = mode >= 4
    let bits : Array[Int] = Array::new()
    let mut i = 0
    while i < op_values.length() {
      let idx = if reverse_order { op_values.length() - 1 - i } else { i }
      let value = op_values[idx]
      let count = op_counts[idx]
      if count < 0 || value < 0 {
        return current_best
      }
      if use_lsb {
        append_forward_bits_lsb(bits, value, count)
      } else {
        append_bits_be(bits, value.reinterpret_as_uint(), count)
      }
      i = i + 1
    }

    let candidate = if use_forward_pack {
      bits.push(1)
      pack_forward_bits_lsb(bits)
    } else {
      build_reverse_bitstream(bits)
    }
    if candidate.length() > 0 &&
      decode_weight_fse_bitstream_matches(
        candidate, table_log, next_state, nb_bits, table_symbols, expected,
      ) &&
      (current_best.length() == 0 || candidate.length() < current_best.length()) {
      current_best = candidate
    }
    mode = mode + 1
  }
  current_best
}

///|
fn build_weight_fse_bitstream_from_ops(
  op_values : Array[Int],
  op_counts : Array[Int],
  table_log : Int,
  next_state : Array[Int],
  nb_bits : Array[Int],
  table_symbols : Array[Int],
  expected : Array[Int],
) -> Bytes raise ZstdError {
  if op_values.length() != op_counts.length() || op_values.length() == 0 {
    return b""
  }
  let mut best = try_update_weight_fse_bitstream_best_with_ops(
    b"", op_values, op_counts, table_log, next_state, nb_bits, table_symbols, expected,
  )

  if op_values.length() >= 2 {
    let swapped_init_values : Array[Int] = Array::new()
    let swapped_init_counts : Array[Int] = Array::new()
    swapped_init_values.push(op_values[1])
    swapped_init_counts.push(op_counts[1])
    swapped_init_values.push(op_values[0])
    swapped_init_counts.push(op_counts[0])
    let mut i = 2
    while i < op_values.length() {
      swapped_init_values.push(op_values[i])
      swapped_init_counts.push(op_counts[i])
      i = i + 1
    }
    best = try_update_weight_fse_bitstream_best_with_ops(
      best, swapped_init_values, swapped_init_counts, table_log, next_state, nb_bits,
      table_symbols, expected,
    )

    let pair_swapped_values : Array[Int] = Array::new()
    let pair_swapped_counts : Array[Int] = Array::new()
    pair_swapped_values.push(op_values[0])
    pair_swapped_counts.push(op_counts[0])
    pair_swapped_values.push(op_values[1])
    pair_swapped_counts.push(op_counts[1])
    i = 2
    while i < op_values.length() {
      if i + 1 < op_values.length() {
        pair_swapped_values.push(op_values[i + 1])
        pair_swapped_counts.push(op_counts[i + 1])
        pair_swapped_values.push(op_values[i])
        pair_swapped_counts.push(op_counts[i])
        i = i + 2
      } else {
        pair_swapped_values.push(op_values[i])
        pair_swapped_counts.push(op_counts[i])
        i = i + 1
      }
    }
    best = try_update_weight_fse_bitstream_best_with_ops(
      best, pair_swapped_values, pair_swapped_counts, table_log, next_state, nb_bits,
      table_symbols, expected,
    )

    let pair_and_init_swapped_values : Array[Int] = Array::new()
    let pair_and_init_swapped_counts : Array[Int] = Array::new()
    pair_and_init_swapped_values.push(op_values[1])
    pair_and_init_swapped_counts.push(op_counts[1])
    pair_and_init_swapped_values.push(op_values[0])
    pair_and_init_swapped_counts.push(op_counts[0])
    i = 2
    while i < op_values.length() {
      if i + 1 < op_values.length() {
        pair_and_init_swapped_values.push(op_values[i + 1])
        pair_and_init_swapped_counts.push(op_counts[i + 1])
        pair_and_init_swapped_values.push(op_values[i])
        pair_and_init_swapped_counts.push(op_counts[i])
        i = i + 2
      } else {
        pair_and_init_swapped_values.push(op_values[i])
        pair_and_init_swapped_counts.push(op_counts[i])
        i = i + 1
      }
    }
    best = try_update_weight_fse_bitstream_best_with_ops(
      best, pair_and_init_swapped_values, pair_and_init_swapped_counts, table_log,
      next_state, nb_bits, table_symbols, expected,
    )
  }
  best
}

///|
fn build_two_state_weight_fse_bitstream_even(
  values : Array[Int],
  table_symbols : Array[Int],
  next_state : Array[Int],
  nb_bits : Array[Int],
  table_log : Int,
  dummy_candidates : Array[Int],
  state_table : Array[Int],
  delta_nb_bits : Array[Int],
  delta_find_state : Array[Int],
) -> Bytes {
  // Output pattern when ending after state1 update:
  // s1, s2, s1, s2, ..., s1, terminal(s2)
  let m = values.length()
  if m <= 0 || (m & 1) != 0 {
    return b""
  }
  let stream1_updates = even_index_symbols(values) // length m/2
  let stream2_full = odd_index_symbols(values) // length m/2 (last is terminal)
  if stream1_updates.length() != stream2_full.length() {
    return b""
  }
  if stream1_updates.length() <= 0 || stream2_full.length() <= 0 {
    return b""
  }
  let (ok2, init2, trans_bits2, trans_nb2, states2) = build_reference_fse_state_path(
    stream2_full, table_symbols, next_state, nb_bits, state_table, delta_nb_bits,
    delta_find_state,
  )
  if !ok2 || states2.length() != stream2_full.length() {
    return b""
  }
  if trans_bits2.length() != stream2_full.length() - 1 ||
    trans_nb2.length() != stream2_full.length() - 1 {
    return b""
  }

  let mut best = b""
  let mut c = 0
  while c < dummy_candidates.length() {
    let stream1_path_symbols = append_with_extra_symbol(
      stream1_updates,
      dummy_candidates[c],
    )
    let (ok1, init1, trans_bits1, trans_nb1, states1) = build_reference_fse_state_path(
      stream1_path_symbols, table_symbols, next_state, nb_bits, state_table, delta_nb_bits,
      delta_find_state,
    )
    if ok1 &&
      states1.length() == stream1_path_symbols.length() &&
      trans_bits1.length() == stream1_updates.length() &&
      trans_nb1.length() == stream1_updates.length() {
      let op_values : Array[Int] = Array::new()
      let op_counts : Array[Int] = Array::new()
      op_values.push(init1)
      op_counts.push(table_log)
      op_values.push(init2)
      op_counts.push(table_log)

      let mut j = 0
      while j + 1 < stream1_updates.length() {
        op_values.push(trans_bits1[j])
        op_counts.push(trans_nb1[j])
        op_values.push(trans_bits2[j])
        op_counts.push(trans_nb2[j])
        j = j + 1
      }
      // Final state1 update before terminal symbol from state2.
      op_values.push(trans_bits1[stream1_updates.length() - 1])
      op_counts.push(trans_nb1[stream1_updates.length() - 1])
      let bitstream = try? build_weight_fse_bitstream_from_ops(
        op_values, op_counts, table_log, next_state, nb_bits, table_symbols, values,
      )
      match bitstream {
        Ok(candidate) =>
          if candidate.length() > 0 &&
            (best.length() == 0 || candidate.length() < best.length()) {
            best = candidate
          }
        Err(_) => ()
      }
    }
    c = c + 1
  }
  best
}

///|
fn build_two_state_weight_fse_bitstream_odd(
  values : Array[Int],
  table_symbols : Array[Int],
  next_state : Array[Int],
  nb_bits : Array[Int],
  table_log : Int,
  dummy_candidates : Array[Int],
  state_table : Array[Int],
  delta_nb_bits : Array[Int],
  delta_find_state : Array[Int],
) -> Bytes {
  // Output pattern when ending after state2 update:
  // s1, s2, s1, s2, ..., s1, s2, terminal(s1)
  let m = values.length()
  if m <= 0 || (m & 1) == 0 {
    return b""
  }
  let stream1_full = even_index_symbols(values) // includes terminal
  let stream2_updates = odd_index_symbols(values)
  if stream1_full.length() != stream2_updates.length() + 1 {
    return b""
  }
  if stream1_full.length() <= 1 || stream2_updates.length() <= 0 {
    return b""
  }
  let (ok1, init1, trans_bits1, trans_nb1, states1) = build_reference_fse_state_path(
    stream1_full, table_symbols, next_state, nb_bits, state_table, delta_nb_bits,
    delta_find_state,
  )
  if !ok1 || states1.length() != stream1_full.length() {
    return b""
  }
  if trans_bits1.length() != stream2_updates.length() ||
    trans_nb1.length() != stream2_updates.length() {
    return b""
  }

  let mut best = b""
  let mut c = 0
  while c < dummy_candidates.length() {
    let stream2_path_symbols = append_with_extra_symbol(
      stream2_updates,
      dummy_candidates[c],
    )
    let (ok2, init2, trans_bits2, trans_nb2, states2) = build_reference_fse_state_path(
      stream2_path_symbols, table_symbols, next_state, nb_bits, state_table, delta_nb_bits,
      delta_find_state,
    )
    if ok2 &&
      states2.length() == stream2_path_symbols.length() &&
      trans_bits2.length() == stream2_updates.length() &&
      trans_nb2.length() == stream2_updates.length() {
      let op_values : Array[Int] = Array::new()
      let op_counts : Array[Int] = Array::new()
      op_values.push(init1)
      op_counts.push(table_log)
      op_values.push(init2)
      op_counts.push(table_log)
      let mut j = 0
      while j < stream2_updates.length() {
        op_values.push(trans_bits1[j])
        op_counts.push(trans_nb1[j])
        op_values.push(trans_bits2[j])
        op_counts.push(trans_nb2[j])
        j = j + 1
      }
      let bitstream = try? build_weight_fse_bitstream_from_ops(
        op_values, op_counts, table_log, next_state, nb_bits, table_symbols, values,
      )
      match bitstream {
        Ok(candidate) =>
          if candidate.length() > 0 &&
            (best.length() == 0 || candidate.length() < best.length()) {
            best = candidate
          }
        Err(_) => ()
      }
    }
    c = c + 1
  }
  best
}

///|
fn try_update_huffman_weight_fse_best_candidate(
  best : Bytes,
  values : Array[Int],
  normalized : Array[Int],
  highest_symbol : Int,
  table_log : Int,
) -> Bytes raise ZstdError {
  let header = write_fse_ncount_header(normalized, highest_symbol, table_log)
  if header.length() == 0 {
    return best
  }
  let (next_state, nb_bits, table_symbols) = build_fse_symbol_decode_table(
    normalized, highest_symbol, table_log,
  )
  let (ctable_ok, state_table, delta_nb_bits, delta_find_state) = build_fse_compression_table_from_normalized(
    normalized, highest_symbol, table_log,
  )
  if !ctable_ok {
    return best
  }
  let dummy_candidates = unique_symbols_from_table(
    table_symbols, highest_symbol,
  )
  if dummy_candidates.length() == 0 {
    return best
  }
  let bitstream = if (values.length() & 1) == 0 {
    build_two_state_weight_fse_bitstream_even(
      values, table_symbols, next_state, nb_bits, table_log, dummy_candidates, state_table,
      delta_nb_bits, delta_find_state,
    )
  } else {
    build_two_state_weight_fse_bitstream_odd(
      values, table_symbols, next_state, nb_bits, table_log, dummy_candidates, state_table,
      delta_nb_bits, delta_find_state,
    )
  }
  if bitstream.length() == 0 {
    return best
  }

  let payload : Array[Byte] = Array::new()
  append_bytes(payload, header, 0, header.length())
  append_bytes(payload, bitstream, 0, bitstream.length())
  let candidate = Bytes::from_array(payload)
  if candidate.length() <= 0 || candidate.length() >= 128 {
    return best
  }

  let decoded = try? read_huffman_weights_fse(candidate, 0, candidate.length())
  match decoded {
    Ok(out) =>
      if int_arrays_equal(out, values) &&
        (best.length() == 0 || candidate.length() < best.length()) {
        candidate
      } else {
        best
      }
    Err(_) => best
  }
}

///|
fn build_huffman_weights_fse_payload(
  values : Array[Int],
) -> Bytes raise ZstdError {
  if values.length() < 2 || values.length() > 255 {
    return b""
  }
  let max_symbol = huf_max_nb_bits
  let freq = Array::make(max_symbol + 1, 0)
  let mut highest_symbol = 0
  let mut active_symbols = 0
  let mut s = 0
  while s < values.length() {
    let v = values[s]
    if v < 0 || v > max_symbol {
      return b""
    }
    if freq[v] == 0 {
      active_symbols = active_symbols + 1
    }
    freq[v] = freq[v] + 1
    if v > highest_symbol {
      highest_symbol = v
    }
    s = s + 1
  }
  if active_symbols < 2 {
    return b""
  }
  let active_symbol_list : Array[Int] = Array::new()
  s = 0
  while s <= highest_symbol {
    if freq[s] > 0 {
      active_symbol_list.push(s)
    }
    s = s + 1
  }
  if active_symbol_list.length() != active_symbols {
    return b""
  }

  let mut best = b""
  let mut table_log = fse_min_table_log
  while table_log <= huf_weight_fse_table_log_max {
    if 1 << table_log >= active_symbols {
      let (norm_ok, normalized) = normalize_symbol_frequencies(
        freq, highest_symbol, table_log, false,
      )
      if norm_ok {
        best = try_update_huffman_weight_fse_best_candidate(
          best, values, normalized, highest_symbol, table_log,
        )
      }
      let (norm_lp_ok, normalized_lp) = normalize_symbol_frequencies(
        freq, highest_symbol, table_log, true,
      )
      if norm_lp_ok {
        best = try_update_huffman_weight_fse_best_candidate(
          best, values, normalized_lp, highest_symbol, table_log,
        )
      }

      let mut offset = 0
      while offset < active_symbol_list.length() {
        let (norm_ok, normalized) = build_weight_normalized_counter(
          freq,
          active_symbol_list,
          values.length(),
          highest_symbol,
          table_log,
          offset,
        )
        if norm_ok {
          best = try_update_huffman_weight_fse_best_candidate(
            best, values, normalized, highest_symbol, table_log,
          )
        }
        offset = offset + 1
      }
    }
    table_log = table_log + 1
  }
  best
}

///|
fn try_build_huffman_fse_weights_description(
  weights : Array[Int],
  last_symbol : Int,
) -> Bytes raise ZstdError {
  if last_symbol <= 1 || last_symbol > 128 || last_symbol > weights.length() {
    return b""
  }
  let values : Array[Int] = Array::new()
  let mut i = 0
  while i < last_symbol {
    let v = weights[i]
    if v < 0 || v > huf_max_nb_bits {
      return b""
    }
    values.push(v)
    i = i + 1
  }
  let payload = build_huffman_weights_fse_payload(values)
  if payload.length() <= 0 || payload.length() >= 128 {
    return b""
  }
  let out : Array[Byte] = Array::new()
  out.push(payload.length().reinterpret_as_uint().to_byte())
  append_bytes(out, payload, 0, payload.length())
  Bytes::from_array(out)
}
