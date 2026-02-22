///|
fn hash4_for_dictionary(src : Bytes, pos : Int) -> Int {
  let v : UInt = src[pos].to_uint() +
    (src[pos + 1].to_uint() << 8) +
    (src[pos + 2].to_uint() << 16) +
    (src[pos + 3].to_uint() << 24)
  let x = v * (2654435761 : UInt)
  ((x >> 17) & (((1 : UInt) << 15) - (1 : UInt))).reinterpret_as_int()
}

///|
fn detect_best_single_match_with_dictionary_history(
  src : Bytes,
  start : Int,
  block_len : Int,
  history : Bytes,
  rep1? : Int = 1,
  rep2? : Int = 4,
  rep3? : Int = 8,
  search_limit? : Int = 8192,
  allow_internal? : Bool = true,
) -> (Int, Int, Int) {
  let (best_ll0, best_offset0, best_ml0) = if allow_internal {
    detect_best_single_match(src, start, block_len, search_limit~)
  } else {
    (0, 0, 0)
  }
  let mut best_ll = best_ll0
  let mut best_offset = best_offset0
  let mut best_ml = best_ml0
  let history_len = history.length()
  if block_len < 4 || history_len < 4 {
    return (best_ll, best_offset, best_ml)
  }

  let dict_hash_table : Array[Int] = Array::make(1 << 15, -1)
  let mut dict_pos = 0
  while dict_pos + 4 <= history_len {
    let h = hash4_for_dictionary(history, dict_pos)
    dict_hash_table[h] = dict_pos
    dict_pos = dict_pos + 1
  }

  let search_cap = if search_limit > 0 { search_limit } else { 8192 }
  let search_len = if block_len < search_cap { block_len } else { search_cap }
  let mut ll = 0
  while ll + 4 <= search_len {
    let p = start + ll
    let h = hash4_for_dictionary(src, p)
    let cand = dict_hash_table[h]
    if cand >= 0 &&
      history[cand] == src[p] &&
      history[cand + 1] == src[p + 1] &&
      history[cand + 2] == src[p + 2] {
      let mut ml = 3
      let max_ml_by_block = block_len - ll
      let max_ml_by_dict = history_len - cand
      let max_ml = if max_ml_by_block < max_ml_by_dict {
        max_ml_by_block
      } else {
        max_ml_by_dict
      }
      while ml < max_ml && history[cand + ml] == src[p + ml] {
        ml = ml + 1
      }
      let candidate_offset = history_len + ll - cand
      let candidate_rep = is_dictionary_rep_offset(
        candidate_offset, rep1, rep2, rep3,
      )
      let best_rep = is_dictionary_rep_offset(best_offset, rep1, rep2, rep3)
      if ml > best_ml ||
        (
          ml == best_ml &&
          (
            best_ml == 0 ||
            (candidate_rep && !best_rep) ||
            (candidate_rep == best_rep && ll < best_ll)
          )
        ) {
        best_ll = ll
        best_ml = ml
        best_offset = candidate_offset
      }
    }
    ll = ll + 1
  }

  (best_ll, best_offset, best_ml)
}

///|
fn is_dictionary_rep_offset(
  offset : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> Bool {
  offset > 0 && (offset == rep1 || offset == rep2 || offset == rep3)
}
