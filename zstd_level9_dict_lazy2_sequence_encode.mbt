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
let zstd_level9_prime4bytes : UInt = 2654435761

///|
let zstd_window_start_index = 2

///|
let zstd_search_strength = 8

///|
let zstd_lazy_skipping_step = 8

///|
let zstd_hash_read_size = 8

///|
let zstd_dubt_unsorted_mark = 1

///|
let zstd_level9_dict_lazy2_no_match_off_base = 999999999

///|
fn level9_dict_lazy2_min_int(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn level9_dict_lazy2_max_int(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn level9_dict_lazy2_cparams(src_len : Int) -> (Bool, Int, Int, Int, Int) {
  ignore(src_len)
  (true, 14, 15, 5, 4)
}

///|
fn should_use_level9_dict_lazy2(
  level : Int,
  start : Int,
  src_len : Int,
  history_len : Int,
  block_len : Int,
) -> Bool {
  let (enabled, _, _, _, _) = level9_dict_lazy2_cparams(src_len)
  enabled &&
  level == 9 &&
  start == 0 &&
  history_len >= zstd_hash_read_size &&
  block_len >= zstd_hash_read_size
}

///|
fn level9_dict_lazy2_dict_limit(history_len : Int) -> Int {
  zstd_window_start_index + history_len
}

///|
fn level9_dict_lazy2_virtual_source_byte(
  history : Bytes,
  src : Bytes,
  start : Int,
  dict_limit : Int,
  index : Int,
) -> Byte {
  if index < dict_limit {
    history[index - zstd_window_start_index]
  } else {
    src[start + index - dict_limit]
  }
}

///|
fn level9_dict_lazy2_hash_abs(
  history : Bytes,
  src : Bytes,
  start : Int,
  dict_limit : Int,
  abs_pos : Int,
  hash_log : Int,
) -> Int {
  let a = level9_dict_lazy2_virtual_source_byte(
    history, src, start, dict_limit, abs_pos,
  ).to_uint()
  let b = level9_dict_lazy2_virtual_source_byte(
    history,
    src,
    start,
    dict_limit,
    abs_pos + 1,
  ).to_uint()
  let c = level9_dict_lazy2_virtual_source_byte(
    history,
    src,
    start,
    dict_limit,
    abs_pos + 2,
  ).to_uint()
  let d = level9_dict_lazy2_virtual_source_byte(
    history,
    src,
    start,
    dict_limit,
    abs_pos + 3,
  ).to_uint()
  let v : UInt = a + (b << 8) + (c << 16) + (d << 24)
  let shift = 32 - hash_log
  ((v * zstd_level9_prime4bytes) >> shift).reinterpret_as_int()
}

///|
fn level9_dict_lazy2_common_match_len_abs(
  history : Bytes,
  src : Bytes,
  start : Int,
  dict_limit : Int,
  pos_abs : Int,
  cand_abs : Int,
  end_abs : Int,
  prefix_len? : Int = 0,
) -> Int {
  let mut ml = prefix_len
  while pos_abs + ml < end_abs &&
        level9_dict_lazy2_virtual_source_byte(
          history,
          src,
          start,
          dict_limit,
          pos_abs + ml,
        ) ==
        level9_dict_lazy2_virtual_source_byte(
          history,
          src,
          start,
          dict_limit,
          cand_abs + ml,
        ) {
    ml = ml + 1
  }
  ml
}

///|
fn level9_dict_lazy2_count_match_len(
  history : Bytes,
  src : Bytes,
  start : Int,
  dict_limit : Int,
  pos : Int,
  cand_abs : Int,
  block_len : Int,
) -> Int {
  let pos_abs = dict_limit + pos
  let end_abs = dict_limit + block_len
  if pos < 0 || pos_abs + 4 > end_abs {
    return 0
  }
  let ml = level9_dict_lazy2_common_match_len_abs(
    history, src, start, dict_limit, pos_abs, cand_abs, end_abs,
  )
  if ml >= 4 {
    ml
  } else {
    0
  }
}

///|
fn level9_dict_lazy2_extend_match_backward(
  history : Bytes,
  src : Bytes,
  start : Int,
  dict_limit : Int,
  anchor : Int,
  pos : Int,
  cand_abs : Int,
  ml : Int,
) -> (Int, Int, Int) {
  let mut p = pos
  let mut c = cand_abs
  let mut m = ml
  let cand_low_exclusive = if cand_abs < dict_limit {
    zstd_window_start_index
  } else {
    dict_limit
  }
  while p > anchor &&
        c > cand_low_exclusive &&
        src[start + p - 1] ==
        level9_dict_lazy2_virtual_source_byte(
          history,
          src,
          start,
          dict_limit,
          c - 1,
        ) {
    p = p - 1
    c = c - 1
    m = m + 1
  }
  (p, c, m)
}

///|
fn level9_dict_lazy2_off_base_high_bit(off_base : Int) -> Int {
  let bit = high_bit_floor_non_zero(off_base)
  if bit >= 0 {
    bit
  } else {
    0
  }
}

///|
fn level9_dict_lazy2_raw_offset_from_off_base(
  off_base : Int,
  ll0 : Bool,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> Int {
  if off_base > 3 {
    return off_base - 3
  }
  let rep_code = off_base - 1 + (if ll0 { 1 } else { 0 })
  if rep_code == 0 {
    rep1
  } else if rep_code == 1 {
    rep2
  } else if rep_code == 2 {
    rep3
  } else {
    rep1 - 1
  }
}

///|
fn level9_dict_lazy2_update_repcodes(
  ll0 : Bool,
  off_base : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (Int, Int, Int) {
  if off_base > 3 {
    (off_base - 3, rep1, rep2)
  } else {
    let rep_code = off_base - 1 + (if ll0 { 1 } else { 0 })
    if rep_code == 0 {
      (rep1, rep2, rep3)
    } else {
      let current = if rep_code == 3 {
        rep1 - 1
      } else if rep_code == 2 {
        rep3
      } else {
        rep2
      }
      (current, rep1, rep2)
    }
  }
}

///|
fn level9_dict_lazy2_lowest_match_index(
  current_abs : Int,
  max_match_offset : Int,
) -> Int {
  if max_match_offset <= 0 {
    return zstd_window_start_index
  }
  let within_window = current_abs - max_match_offset
  if within_window > zstd_window_start_index {
    within_window
  } else {
    zstd_window_start_index
  }
}

///|
fn level9_dict_lazy2_prefill_insert_bt1(
  history : Bytes,
  hash_log : Int,
  chain_log : Int,
  search_log : Int,
  hash_table : Array[Int],
  bt_table : Array[Int],
  curr_abs : Int,
  target_abs : Int,
  dict_limit : Int,
) -> Int {
  ignore(target_abs)
  let h = level9_dict_lazy2_hash_abs(
    history, b"", 0, dict_limit, curr_abs, hash_log,
  )
  let bt_mask = (1 << (chain_log - 1)) - 1
  let mut match_index = hash_table[h]
  let mut common_smaller = 0
  let mut common_larger = 0
  let bt_low = if bt_mask >= curr_abs { 0 } else { curr_abs - bt_mask }
  let window_low = zstd_window_start_index
  let mut smaller_slot = 2 * (curr_abs & bt_mask)
  let mut larger_slot = smaller_slot + 1
  let mut match_end_idx = curr_abs + zstd_hash_read_size + 1
  let mut best_length = zstd_hash_read_size
  let mut nb_compares = 1 << search_log
  hash_table[h] = curr_abs

  while nb_compares > 0 && match_index >= window_low {
    let next_slot = 2 * (match_index & bt_mask)
    let mut match_length = level9_dict_lazy2_min_int(
      common_smaller, common_larger,
    )
    match_length = level9_dict_lazy2_common_match_len_abs(
      history,
      b"",
      0,
      dict_limit,
      curr_abs,
      match_index,
      dict_limit,
      prefix_len=match_length,
    )

    if match_length > best_length {
      best_length = match_length
      if match_length > match_end_idx - match_index {
        match_end_idx = match_index + match_length
      }
    }

    if curr_abs + match_length == dict_limit {
      break
    }

    let match_byte = level9_dict_lazy2_virtual_source_byte(
      history,
      b"",
      0,
      dict_limit,
      match_index + match_length,
    )
    let curr_byte = level9_dict_lazy2_virtual_source_byte(
      history,
      b"",
      0,
      dict_limit,
      curr_abs + match_length,
    )
    if match_byte < curr_byte {
      bt_table[smaller_slot] = match_index
      common_smaller = match_length
      if match_index <= bt_low {
        smaller_slot = -1
        break
      }
      smaller_slot = next_slot + 1
      match_index = bt_table[next_slot + 1]
    } else {
      bt_table[larger_slot] = match_index
      common_larger = match_length
      if match_index <= bt_low {
        larger_slot = -1
        break
      }
      larger_slot = next_slot
      match_index = bt_table[next_slot]
    }
    nb_compares = nb_compares - 1
  }

  if smaller_slot >= 0 {
    bt_table[smaller_slot] = 0
  }
  if larger_slot >= 0 {
    bt_table[larger_slot] = 0
  }

  let positions = if best_length > 384 {
    level9_dict_lazy2_min_int(192, best_length - 384)
  } else {
    0
  }
  let forward = match_end_idx - (curr_abs + zstd_hash_read_size)
  if positions > forward {
    positions
  } else {
    forward
  }
}

///|
fn build_level9_dict_lazy2_bt_state(
  history : Bytes,
  hash_log : Int,
  chain_log : Int,
  search_log : Int,
) -> (Array[Int], Array[Int]) {
  let dict_limit = level9_dict_lazy2_dict_limit(history.length())
  let hash_table = Array::make(1 << hash_log, 0)
  let bt_table = Array::make(1 << chain_log, 0)
  let target_abs = dict_limit - zstd_hash_read_size
  let mut idx = zstd_window_start_index
  while idx < target_abs {
    let forward = level9_dict_lazy2_prefill_insert_bt1(
      history, hash_log, chain_log, search_log, hash_table, bt_table, idx, target_abs,
      dict_limit,
    )
    idx = idx + forward
  }
  (hash_table, bt_table)
}

///|
fn level9_dict_lazy2_update_dubt(
  history : Bytes,
  src : Bytes,
  start : Int,
  dict_limit : Int,
  curr_abs : Int,
  hash_log : Int,
  chain_log : Int,
  hash_table : Array[Int],
  bt_table : Array[Int],
  next_to_update : Ref[Int],
) -> Unit {
  let bt_mask = (1 << (chain_log - 1)) - 1
  let mut idx = next_to_update.val
  while idx < curr_abs {
    let h = level9_dict_lazy2_hash_abs(
      history, src, start, dict_limit, idx, hash_log,
    )
    let match_index = hash_table[h]
    let slot = 2 * (idx & bt_mask)
    hash_table[h] = idx
    bt_table[slot] = match_index
    bt_table[slot + 1] = zstd_dubt_unsorted_mark
    idx = idx + 1
  }
  next_to_update.val = curr_abs
}

///|
fn level9_dict_lazy2_insert_dubt1(
  history : Bytes,
  src : Bytes,
  start : Int,
  block_len : Int,
  dict_limit : Int,
  current_abs : Int,
  hash_log : Int,
  chain_log : Int,
  bt_table : Array[Int],
  nb_compares : Int,
  bt_low : Int,
  max_match_offset : Int,
) -> Unit {
  ignore(hash_log)
  let bt_mask = (1 << (chain_log - 1)) - 1
  let end_abs = dict_limit + block_len
  let mut common_smaller = 0
  let mut common_larger = 0
  let mut smaller_slot = 2 * (current_abs & bt_mask)
  let mut larger_slot = smaller_slot + 1
  let window_low = level9_dict_lazy2_lowest_match_index(
    current_abs, max_match_offset,
  )
  let mut match_index = bt_table[smaller_slot]
  let mut remaining = nb_compares

  while remaining > 0 && match_index > window_low {
    let next_slot = 2 * (match_index & bt_mask)
    let mut match_length = level9_dict_lazy2_min_int(
      common_smaller, common_larger,
    )
    match_length = level9_dict_lazy2_common_match_len_abs(
      history,
      src,
      start,
      dict_limit,
      current_abs,
      match_index,
      end_abs,
      prefix_len=match_length,
    )

    if current_abs + match_length == end_abs {
      break
    }

    let match_byte = level9_dict_lazy2_virtual_source_byte(
      history,
      src,
      start,
      dict_limit,
      match_index + match_length,
    )
    let curr_byte = level9_dict_lazy2_virtual_source_byte(
      history,
      src,
      start,
      dict_limit,
      current_abs + match_length,
    )
    if match_byte < curr_byte {
      bt_table[smaller_slot] = match_index
      common_smaller = match_length
      if match_index <= bt_low {
        smaller_slot = -1
        break
      }
      smaller_slot = next_slot + 1
      match_index = bt_table[next_slot + 1]
    } else {
      bt_table[larger_slot] = match_index
      common_larger = match_length
      if match_index <= bt_low {
        larger_slot = -1
        break
      }
      larger_slot = next_slot
      match_index = bt_table[next_slot]
    }
    remaining = remaining - 1
  }

  if smaller_slot >= 0 {
    bt_table[smaller_slot] = 0
  }
  if larger_slot >= 0 {
    bt_table[larger_slot] = 0
  }
}

///|
fn level9_dict_lazy2_bt_find_best_match(
  history : Bytes,
  src : Bytes,
  start : Int,
  block_len : Int,
  pos : Int,
  hash_log : Int,
  chain_log : Int,
  search_log : Int,
  dict_limit : Int,
  hash_table : Array[Int],
  bt_table : Array[Int],
  next_to_update : Ref[Int],
  max_match_offset : Int,
) -> (Int, Int) {
  let current_abs = dict_limit + pos
  if current_abs < next_to_update.val {
    return (0, zstd_level9_dict_lazy2_no_match_off_base)
  }

  let end_abs = dict_limit + block_len
  let bt_mask = (1 << (chain_log - 1)) - 1
  let h = level9_dict_lazy2_hash_abs(
    history, src, start, dict_limit, current_abs, hash_log,
  )
  let window_low = level9_dict_lazy2_lowest_match_index(
    current_abs, max_match_offset,
  )
  let bt_low = if bt_mask >= current_abs { 0 } else { current_abs - bt_mask }
  let unsort_limit = level9_dict_lazy2_max_int(bt_low, window_low)
  let mut match_index = hash_table[h]
  let mut next_candidate_slot = 2 * (match_index & bt_mask)
  let mut unsorted_mark_slot = next_candidate_slot + 1
  let mut nb_compares = 1 << search_log
  let mut nb_candidates = nb_compares
  let mut previous_candidate = 0

  while match_index > unsort_limit &&
        bt_table[unsorted_mark_slot] == zstd_dubt_unsorted_mark &&
        nb_candidates > 1 {
    bt_table[unsorted_mark_slot] = previous_candidate
    previous_candidate = match_index
    match_index = bt_table[next_candidate_slot]
    next_candidate_slot = 2 * (match_index & bt_mask)
    unsorted_mark_slot = next_candidate_slot + 1
    nb_candidates = nb_candidates - 1
  }

  if match_index > unsort_limit &&
    bt_table[unsorted_mark_slot] == zstd_dubt_unsorted_mark {
    bt_table[next_candidate_slot] = 0
    bt_table[unsorted_mark_slot] = 0
  }

  match_index = previous_candidate
  while match_index != 0 {
    let next_candidate_index_slot = 2 * (match_index & bt_mask) + 1
    let next_candidate_index = bt_table[next_candidate_index_slot]
    level9_dict_lazy2_insert_dubt1(
      history, src, start, block_len, dict_limit, match_index, hash_log, chain_log,
      bt_table, nb_candidates, unsort_limit, max_match_offset,
    )
    match_index = next_candidate_index
    nb_candidates = nb_candidates + 1
  }

  let mut common_smaller = 0
  let mut common_larger = 0
  let mut smaller_slot = 2 * (current_abs & bt_mask)
  let mut larger_slot = smaller_slot + 1
  let mut match_end_idx = current_abs + zstd_hash_read_size + 1
  let mut best_length = 0
  let mut best_off_base = zstd_level9_dict_lazy2_no_match_off_base

  match_index = hash_table[h]
  hash_table[h] = current_abs

  while nb_compares > 0 && match_index > window_low {
    let next_slot = 2 * (match_index & bt_mask)
    let mut match_length = level9_dict_lazy2_min_int(
      common_smaller, common_larger,
    )
    match_length = level9_dict_lazy2_common_match_len_abs(
      history,
      src,
      start,
      dict_limit,
      current_abs,
      match_index,
      end_abs,
      prefix_len=match_length,
    )

    if match_length > best_length {
      if match_length > match_end_idx - match_index {
        match_end_idx = match_index + match_length
      }
      let gain2 = 4 * (match_length - best_length)
      let gain1 = level9_dict_lazy2_off_base_high_bit(
          current_abs - match_index + 1,
        ) -
        level9_dict_lazy2_off_base_high_bit(best_off_base)
      if gain2 > gain1 {
        best_length = match_length
        best_off_base = current_abs - match_index + 3
      }
      if current_abs + match_length == end_abs {
        break
      }
    }

    let match_byte = level9_dict_lazy2_virtual_source_byte(
      history,
      src,
      start,
      dict_limit,
      match_index + match_length,
    )
    let curr_byte = level9_dict_lazy2_virtual_source_byte(
      history,
      src,
      start,
      dict_limit,
      current_abs + match_length,
    )
    if match_byte < curr_byte {
      bt_table[smaller_slot] = match_index
      common_smaller = match_length
      if match_index <= bt_low {
        smaller_slot = -1
        break
      }
      smaller_slot = next_slot + 1
      match_index = bt_table[next_slot + 1]
    } else {
      bt_table[larger_slot] = match_index
      common_larger = match_length
      if match_index <= bt_low {
        larger_slot = -1
        break
      }
      larger_slot = next_slot
      match_index = bt_table[next_slot]
    }
    nb_compares = nb_compares - 1
  }

  if smaller_slot >= 0 {
    bt_table[smaller_slot] = 0
  }
  if larger_slot >= 0 {
    bt_table[larger_slot] = 0
  }

  next_to_update.val = match_end_idx - zstd_hash_read_size
  if best_length >= 4 {
    (best_length, best_off_base)
  } else {
    (0, zstd_level9_dict_lazy2_no_match_off_base)
  }
}

///|
fn level9_dict_lazy2_rep_match_length(
  history : Bytes,
  src : Bytes,
  start : Int,
  dict_limit : Int,
  pos : Int,
  block_len : Int,
  offset : Int,
  current_abs : Int,
  max_match_offset : Int,
) -> Int {
  if offset <= 0 {
    return 0
  }
  let rep_index = current_abs - offset
  let window_low = level9_dict_lazy2_lowest_match_index(
    current_abs, max_match_offset,
  )
  if !index_overlap_check(dict_limit, rep_index) ||
    offset > current_abs - window_low {
    return 0
  }
  level9_dict_lazy2_count_match_len(
    history, src, start, dict_limit, pos, rep_index, block_len,
  )
}

///|
fn collect_level9_dict_lazy2_sequences(
  src : Bytes,
  start : Int,
  block_len : Int,
  ll_values : Array[Int],
  off_values : Array[Int],
  off_base_values : Array[Int],
  ml_values : Array[Int],
  max_sequences : Int,
  history : Bytes,
  max_match_offset : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> Unit {
  let history_len = history.length()
  let (enabled, hash_log, chain_log, search_log, _) = level9_dict_lazy2_cparams(
    src.length(),
  )
  if !enabled ||
    history_len < zstd_hash_read_size ||
    block_len < zstd_hash_read_size {
    return
  }

  let dict_limit = level9_dict_lazy2_dict_limit(history_len)
  let (hash_table, bt_table) = build_level9_dict_lazy2_bt_state(
    history, hash_log, chain_log, search_log,
  )
  let next_to_update : Ref[Int] = { val: dict_limit }
  let mut ip = 1
  let mut anchor = 0
  let mut offset_1 = rep1
  let mut offset_2 = rep2
  let mut offset_3 = rep3
  let mut lazy_skipping = false
  let ilimit = block_len - zstd_hash_read_size

  while ip < ilimit && ll_values.length() < max_sequences {
    let current_abs = dict_limit + ip
    let mut match_length = 0
    let mut off_base = 1
    let mut start_pos = ip + 1

    let rep_length0 = level9_dict_lazy2_rep_match_length(
      history,
      src,
      start,
      dict_limit,
      ip + 1,
      block_len,
      offset_1,
      current_abs + 1,
      max_match_offset,
    )
    if rep_length0 >= 4 {
      match_length = rep_length0
    }

    level9_dict_lazy2_update_dubt(
      history, src, start, dict_limit, current_abs, hash_log, chain_log, hash_table,
      bt_table, next_to_update,
    )
    let (base_ml, base_off_base) = level9_dict_lazy2_bt_find_best_match(
      history, src, start, block_len, ip, hash_log, chain_log, search_log, dict_limit,
      hash_table, bt_table, next_to_update, max_match_offset,
    )
    if base_ml > match_length {
      match_length = base_ml
      off_base = base_off_base
      start_pos = ip
    }

    if match_length < 4 {
      let step = (ip - anchor) >> zstd_search_strength
      ip = ip + step + 1
      lazy_skipping = step > zstd_lazy_skipping_step
      continue
    }

    while ip < ilimit {
      ip = ip + 1
      let curr1 = dict_limit + ip
      if off_base > 0 {
        let rep_length = level9_dict_lazy2_rep_match_length(
          history, src, start, dict_limit, ip, block_len, offset_1, curr1, max_match_offset,
        )
        let gain2 = rep_length * 3
        let gain1 = match_length * 3 -
          level9_dict_lazy2_off_base_high_bit(off_base) +
          1
        if rep_length >= 4 && gain2 > gain1 {
          match_length = rep_length
          off_base = 1
          start_pos = ip
        }
      }

      let (candidate_ml, candidate_off_base) = level9_dict_lazy2_bt_find_best_match(
        history, src, start, block_len, ip, hash_log, chain_log, search_log, dict_limit,
        hash_table, bt_table, next_to_update, max_match_offset,
      )
      let gain2 = candidate_ml * 4 -
        level9_dict_lazy2_off_base_high_bit(candidate_off_base)
      let gain1 = match_length * 4 -
        level9_dict_lazy2_off_base_high_bit(off_base) +
        4
      if candidate_ml >= 4 && gain2 > gain1 {
        match_length = candidate_ml
        off_base = candidate_off_base
        start_pos = ip
        continue
      }

      if ip < ilimit {
        ip = ip + 1
        let curr2 = dict_limit + ip
        if off_base > 0 {
          let rep_length = level9_dict_lazy2_rep_match_length(
            history, src, start, dict_limit, ip, block_len, offset_1, curr2, max_match_offset,
          )
          let gain2 = rep_length * 4
          let gain1 = match_length * 4 -
            level9_dict_lazy2_off_base_high_bit(off_base) +
            1
          if rep_length >= 4 && gain2 > gain1 {
            match_length = rep_length
            off_base = 1
            start_pos = ip
          }
        }

        let (candidate_ml2, candidate_off_base2) = level9_dict_lazy2_bt_find_best_match(
          history, src, start, block_len, ip, hash_log, chain_log, search_log, dict_limit,
          hash_table, bt_table, next_to_update, max_match_offset,
        )
        let gain2 = candidate_ml2 * 4 -
          level9_dict_lazy2_off_base_high_bit(candidate_off_base2)
        let gain1 = match_length * 4 -
          level9_dict_lazy2_off_base_high_bit(off_base) +
          7
        if candidate_ml2 >= 4 && gain2 > gain1 {
          match_length = candidate_ml2
          off_base = candidate_off_base2
          start_pos = ip
          continue
        }
      }
      break
    }

    let mut adjusted_start = start_pos
    let mut adjusted_ml = match_length
    if off_base > 3 {
      let match_index = dict_limit + adjusted_start - (off_base - 3)
      let (new_start, _, new_ml) = level9_dict_lazy2_extend_match_backward(
        history, src, start, dict_limit, anchor, adjusted_start, match_index, adjusted_ml,
      )
      adjusted_start = new_start
      adjusted_ml = new_ml
    }

    let lit_length = adjusted_start - anchor
    let raw_offset = level9_dict_lazy2_raw_offset_from_off_base(
      off_base,
      lit_length == 0,
      offset_1,
      offset_2,
      offset_3,
    )
    let (new_rep1, new_rep2, new_rep3) = level9_dict_lazy2_update_repcodes(
      lit_length == 0,
      off_base,
      offset_1,
      offset_2,
      offset_3,
    )
    offset_1 = new_rep1
    offset_2 = new_rep2
    offset_3 = new_rep3

    ll_values.push(lit_length)
    off_values.push(raw_offset)
    off_base_values.push(off_base)
    ml_values.push(adjusted_ml)
    anchor = adjusted_start + adjusted_ml
    ip = anchor
    if lazy_skipping {
      lazy_skipping = false
    }

    while ip <= ilimit && ll_values.length() < max_sequences {
      let rep_current = dict_limit + ip
      let rep_length = level9_dict_lazy2_rep_match_length(
        history, src, start, dict_limit, ip, block_len, offset_2, rep_current, max_match_offset,
      )
      if rep_length < 4 {
        break
      }
      let rep_offset = offset_2
      offset_2 = offset_1
      offset_1 = rep_offset
      ll_values.push(0)
      off_values.push(rep_offset)
      off_base_values.push(1)
      ml_values.push(rep_length)
      ip = ip + rep_length
      anchor = ip
    }
  }
}
