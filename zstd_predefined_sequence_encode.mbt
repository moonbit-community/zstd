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
fn predefined_sequence_entry(
  symbol_type : Int,
  state : Int,
) -> (Int, Int, Int, Int) raise ZstdError {
  if symbol_type == sequence_symbol_literal_length {
    ll_predefined_entry(state)
  } else if symbol_type == sequence_symbol_offset {
    of_predefined_entry(state)
  } else if symbol_type == sequence_symbol_match_length {
    ml_predefined_entry(state)
  } else {
    raise CorruptionDetected
  }
}

///|
fn predefined_state_limit(symbol_type : Int) -> Int raise ZstdError {
  if symbol_type == sequence_symbol_literal_length ||
    symbol_type == sequence_symbol_match_length {
    63
  } else if symbol_type == sequence_symbol_offset {
    31
  } else {
    raise CorruptionDetected
  }
}

///|
fn try_choose_predefined_state(
  symbol_type : Int,
  value : Int,
) -> (Bool, Int, UInt, Int) raise ZstdError {
  if value < 0 {
    return (false, 0, 0, 0)
  }
  let mut found = false
  let mut best_state = 0
  let mut best_extra : UInt = 0
  let mut best_nb_add_bits = 0

  let state_limit = predefined_state_limit(symbol_type)
  let mut state = 0
  while state <= state_limit {
    let (_, nb_add_bits, _, base) = predefined_sequence_entry(
      symbol_type, state,
    )
    let can_use = if symbol_type == sequence_symbol_offset {
      // Prefer direct-offset states and avoid repcode-special states in encode.
      nb_add_bits > 1
    } else {
      true
    }
    if can_use && value >= base {
      let span = if nb_add_bits == 0 {
        0
      } else {
        (((1 : UInt64) << nb_add_bits) - (1 : UInt64)).to_int()
      }
      let limit = base + span
      if value <= limit &&
        (
          !found ||
          nb_add_bits < best_nb_add_bits ||
          (nb_add_bits == best_nb_add_bits && state < best_state)
        ) {
        found = true
        best_state = state
        best_extra = (value - base).reinterpret_as_uint()
        best_nb_add_bits = nb_add_bits
      }
    }
    state = state + 1
  }
  if found {
    (true, best_state, best_extra, best_nb_add_bits)
  } else {
    (false, 0, 0, 0)
  }
}

///|
fn try_choose_predefined_offset_state_with_repcodes(
  value : Int,
  ll : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (Bool, Int, UInt, Int) raise ZstdError {
  if value <= 0 {
    return (false, 0, 0, 0)
  }
  let states : Array[Int] = Array::new()
  let extras : Array[UInt] = Array::new()
  let nb_add_bits : Array[Int] = Array::new()
  let next_states : Array[Int] = Array::new()
  let nb_state_bits : Array[Int] = Array::new()
  let out_r1 : Array[Int] = Array::new()
  let out_r2 : Array[Int] = Array::new()
  let out_r3 : Array[Int] = Array::new()
  collect_predefined_offset_candidates_for_context(
    value,
    ll == 0,
    rep1,
    rep2,
    rep3,
    states,
    extras,
    nb_add_bits,
    next_states,
    nb_state_bits,
    out_r1,
    out_r2,
    out_r3,
  )
  if states.length() == 0 {
    return (false, 0, 0, 0)
  }
  let mut best_idx = 0
  let mut i = 1
  while i < states.length() {
    if nb_add_bits[i] < nb_add_bits[best_idx] ||
      (nb_add_bits[i] == nb_add_bits[best_idx] && states[i] < states[best_idx]) {
      best_idx = i
    }
    i = i + 1
  }
  (true, states[best_idx], extras[best_idx], nb_add_bits[best_idx])
}

///|
fn build_single_match_payload_predefined(
  src : Bytes,
  start : Int,
  block_len : Int,
  ll : Int,
  offset : Int,
  ml : Int,
  max_offset : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> Bytes raise ZstdError {
  if ll < 0 ||
    offset <= 0 ||
    ml < 3 ||
    ll + ml > block_len ||
    offset > max_offset {
    return b""
  }
  let (ll_ok, ll_state, ll_extra, ll_bits) = try_choose_predefined_state(
    sequence_symbol_literal_length, ll,
  )
  if !ll_ok {
    return b""
  }
  let (off_ok, off_state, off_extra, off_bits) = try_choose_predefined_offset_state_with_repcodes(
    offset, ll, rep1, rep2, rep3,
  )
  if !off_ok {
    return b""
  }
  let (ml_ok, ml_state, ml_extra, ml_bits) = try_choose_predefined_state(
    sequence_symbol_match_length, ml,
  )
  if !ml_ok {
    return b""
  }
  let literals = build_single_match_literals(src, start, block_len, ll, ml)

  let extra_bits : Array[Int] = Array::new()
  append_bits_be(
    extra_bits,
    ll_state.reinterpret_as_uint(),
    ll_predefined_table_log,
  )
  append_bits_be(
    extra_bits,
    off_state.reinterpret_as_uint(),
    of_predefined_table_log,
  )
  append_bits_be(
    extra_bits,
    ml_state.reinterpret_as_uint(),
    ml_predefined_table_log,
  )
  append_bits_be(extra_bits, off_extra, off_bits)
  append_bits_be(extra_bits, ml_extra, ml_bits)
  append_bits_be(extra_bits, ll_extra, ll_bits)
  let bitstream = build_reverse_bitstream(extra_bits)

  let payload : Array[Byte] = Array::new()
  append_best_literals_section(payload, literals)
  append_sequence_count(payload, 1)
  payload.push((0 : UInt).to_byte()) // all predefined sequence modes
  append_bytes(payload, bitstream, 0, bitstream.length())
  Bytes::from_array(payload)
}
