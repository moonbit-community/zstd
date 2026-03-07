// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
fn bitc_add_bits_lsb_u64(
  bit_container : Ref[UInt64],
  bit_pos : Ref[Int],
  value : Int,
  nb_bits : Int,
) -> Bool {
  if nb_bits < 0 || nb_bits >= 32 {
    return false
  }
  if nb_bits == 0 {
    return true
  }
  if value < 0 || bit_pos.val < 0 || bit_pos.val + nb_bits >= 64 {
    return false
  }
  let mask = ((1 : UInt64) << nb_bits) - (1 : UInt64)
  let low = value.reinterpret_as_uint().to_uint64() & mask
  bit_container.val = bit_container.val | (low << bit_pos.val)
  bit_pos.val = bit_pos.val + nb_bits
  true
}

///|
fn bitc_flush_bits_lsb_u64(
  out : Array[Byte],
  bit_container : Ref[UInt64],
  bit_pos : Ref[Int],
) -> Unit {
  let nb_bytes = bit_pos.val >> 3
  let mut i = 0
  while i < nb_bytes {
    out.push(
      ((bit_container.val >> (i * 8)) & (0xFF : UInt64)).to_uint().to_byte(),
    )
    i = i + 1
  }
  bit_container.val = bit_container.val >> (nb_bytes * 8)
  bit_pos.val = bit_pos.val & 7
}

///|
fn build_weight_fse_bitstream_using_ctable(
  values : Array[Int],
  table_log : Int,
  state_table : Array[Int],
  delta_nb_bits : Array[Int],
  delta_find_state : Array[Int],
) -> Bytes {
  let src_size = values.length()
  if src_size <= 2 || table_log <= 0 {
    return b""
  }
  let bit_container : Ref[UInt64] = { val: (0 : UInt64) }
  let bit_pos : Ref[Int] = { val: 0 }
  let out : Array[Byte] = Array::new()
  let state1 : Ref[Int] = { val: 0 }
  let state2 : Ref[Int] = { val: 0 }
  let mut ip = src_size

  if (src_size & 1) != 0 {
    let (ok1, s1) = fse_init_cstate2_with_table(
      state_table,
      delta_nb_bits,
      delta_find_state,
      values[ip - 1],
    )
    if !ok1 {
      return b""
    }
    ip = ip - 1
    let (ok2, s2) = fse_init_cstate2_with_table(
      state_table,
      delta_nb_bits,
      delta_find_state,
      values[ip - 1],
    )
    if !ok2 {
      return b""
    }
    ip = ip - 1
    state1.val = s1
    state2.val = s2

    let (enc_ok, bits, nb_out, next_s1) = fse_encode_symbol_with_table(
      state1.val,
      values[ip - 1],
      state_table,
      delta_nb_bits,
      delta_find_state,
    )
    if !enc_ok || !bitc_add_bits_lsb_u64(bit_container, bit_pos, bits, nb_out) {
      return b""
    }
    ip = ip - 1
    state1.val = next_s1
    bitc_flush_bits_lsb_u64(out, bit_container, bit_pos)
  } else {
    let (ok2, s2) = fse_init_cstate2_with_table(
      state_table,
      delta_nb_bits,
      delta_find_state,
      values[ip - 1],
    )
    if !ok2 {
      return b""
    }
    ip = ip - 1
    let (ok1, s1) = fse_init_cstate2_with_table(
      state_table,
      delta_nb_bits,
      delta_find_state,
      values[ip - 1],
    )
    if !ok1 {
      return b""
    }
    ip = ip - 1
    state1.val = s1
    state2.val = s2
  }

  let adjusted_size = src_size - 2
  if (adjusted_size & 2) != 0 {
    let (ok2, bits2, nb2, next_s2) = fse_encode_symbol_with_table(
      state2.val,
      values[ip - 1],
      state_table,
      delta_nb_bits,
      delta_find_state,
    )
    if !ok2 || !bitc_add_bits_lsb_u64(bit_container, bit_pos, bits2, nb2) {
      return b""
    }
    ip = ip - 1
    state2.val = next_s2

    let (ok1, bits1, nb1, next_s1) = fse_encode_symbol_with_table(
      state1.val,
      values[ip - 1],
      state_table,
      delta_nb_bits,
      delta_find_state,
    )
    if !ok1 || !bitc_add_bits_lsb_u64(bit_container, bit_pos, bits1, nb1) {
      return b""
    }
    ip = ip - 1
    state1.val = next_s1
    bitc_flush_bits_lsb_u64(out, bit_container, bit_pos)
  }

  while ip > 0 {
    let (ok2a, bits2a, nb2a, next_s2a) = fse_encode_symbol_with_table(
      state2.val,
      values[ip - 1],
      state_table,
      delta_nb_bits,
      delta_find_state,
    )
    if !ok2a || !bitc_add_bits_lsb_u64(bit_container, bit_pos, bits2a, nb2a) {
      return b""
    }
    ip = ip - 1
    state2.val = next_s2a

    let (ok1a, bits1a, nb1a, next_s1a) = fse_encode_symbol_with_table(
      state1.val,
      values[ip - 1],
      state_table,
      delta_nb_bits,
      delta_find_state,
    )
    if !ok1a || !bitc_add_bits_lsb_u64(bit_container, bit_pos, bits1a, nb1a) {
      return b""
    }
    ip = ip - 1
    state1.val = next_s1a

    if ip <= 0 {
      return b""
    }
    let (ok2b, bits2b, nb2b, next_s2b) = fse_encode_symbol_with_table(
      state2.val,
      values[ip - 1],
      state_table,
      delta_nb_bits,
      delta_find_state,
    )
    if !ok2b || !bitc_add_bits_lsb_u64(bit_container, bit_pos, bits2b, nb2b) {
      return b""
    }
    ip = ip - 1
    state2.val = next_s2b

    if ip <= 0 {
      return b""
    }
    let (ok1b, bits1b, nb1b, next_s1b) = fse_encode_symbol_with_table(
      state1.val,
      values[ip - 1],
      state_table,
      delta_nb_bits,
      delta_find_state,
    )
    if !ok1b || !bitc_add_bits_lsb_u64(bit_container, bit_pos, bits1b, nb1b) {
      return b""
    }
    ip = ip - 1
    state1.val = next_s1b

    bitc_flush_bits_lsb_u64(out, bit_container, bit_pos)
  }

  if !bitc_add_bits_lsb_u64(bit_container, bit_pos, state2.val, table_log) {
    return b""
  }
  bitc_flush_bits_lsb_u64(out, bit_container, bit_pos)
  if !bitc_add_bits_lsb_u64(bit_container, bit_pos, state1.val, table_log) {
    return b""
  }
  bitc_flush_bits_lsb_u64(out, bit_container, bit_pos)

  if !bitc_add_bits_lsb_u64(bit_container, bit_pos, 1, 1) {
    return b""
  }
  bitc_flush_bits_lsb_u64(out, bit_container, bit_pos)
  if bit_pos.val > 0 {
    out.push((bit_container.val & (0xFF : UInt64)).to_uint().to_byte())
  }
  Bytes::from_array(out)
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
  allow_ctable_fallback : Bool,
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
  let fallback_bitstream = build_weight_fse_bitstream_using_ctable(
    values, table_log, state_table, delta_nb_bits, delta_find_state,
  )
  let primary_bitstream = if (values.length() & 1) == 0 {
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
  let prefer_fallback = fallback_bitstream.length() > 0
  let bitstream = if prefer_fallback {
    fallback_bitstream
  } else if primary_bitstream.length() > 0 {
    primary_bitstream
  } else if allow_ctable_fallback {
    primary_bitstream
  } else {
    b""
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
  allow_ctable_fallback? : Bool = false,
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
  let table_log = choose_compressed_table_log(
    values.length(),
    highest_symbol,
    huf_weight_fse_table_log_max,
  )
  if table_log < fse_min_table_log || table_log > huf_weight_fse_table_log_max {
    return b""
  }
  if 1 << table_log < active_symbols {
    return b""
  }

  let (norm_ok, normalized) = normalize_symbol_frequencies(
    freq, highest_symbol, table_log, false,
  )
  if !norm_ok {
    return b""
  }
  try_update_huffman_weight_fse_best_candidate(
    b"", values, normalized, highest_symbol, table_log, allow_ctable_fallback,
  )
}

///|
fn try_build_huffman_fse_weights_description(
  weights : Array[Int],
  last_symbol : Int,
  allow_ctable_fallback? : Bool = false,
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
  let payload = build_huffman_weights_fse_payload(
    values,
    allow_ctable_fallback~,
  )
  if payload.length() <= 0 || payload.length() >= 128 {
    return b""
  }
  if allow_ctable_fallback && last_symbol >= 120 {
    let direct_desc = build_huffman_direct_weights_description(
      weights, last_symbol,
    )
    let fse_desc_len = payload.length() + 1
    // Keep FSE only when it is strictly smaller than direct weights encoding.
    if direct_desc.length() > 0 && fse_desc_len >= direct_desc.length() {
      return b""
    }
  }
  let out : Array[Byte] = Array::new()
  out.push(payload.length().reinterpret_as_uint().to_byte())
  append_bytes(out, payload, 0, payload.length())
  Bytes::from_array(out)
}
