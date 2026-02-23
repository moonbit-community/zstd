///|
let zstd_prime4bytes : UInt = 2654435761

///|
let zstd_prime8bytes : UInt64 = 0xCF1BBCDCB7A56463

///|
let zstd_short_cache_tag_bits = 8

///|
fn hash4_with_bits(src : Bytes, pos : Int, h_bits : Int) -> Int {
  let v : UInt = src[pos].to_uint() +
    (src[pos + 1].to_uint() << 8) +
    (src[pos + 2].to_uint() << 16) +
    (src[pos + 3].to_uint() << 24)
  let shift = 32 - h_bits
  (((v * zstd_prime4bytes) >> shift) & (((1 : UInt) << h_bits) - (1 : UInt))).reinterpret_as_int()
}

///|
fn hash8_with_bits(src : Bytes, pos : Int, h_bits : Int) -> Int {
  let v : UInt64 = src[pos].to_uint().to_uint64() +
    (src[pos + 1].to_uint().to_uint64() << 8) +
    (src[pos + 2].to_uint().to_uint64() << 16) +
    (src[pos + 3].to_uint().to_uint64() << 24) +
    (src[pos + 4].to_uint().to_uint64() << 32) +
    (src[pos + 5].to_uint().to_uint64() << 40) +
    (src[pos + 6].to_uint().to_uint64() << 48) +
    (src[pos + 7].to_uint().to_uint64() << 56)
  let shift = 64 - h_bits
  (((v * zstd_prime8bytes) >> shift) & (((1 : UInt64) << h_bits) - (1 : UInt64))).to_int()
}

///|
fn hash4_with_tag(src : Bytes, pos : Int, h_bits : Int) -> (Int, Int) {
  let hash_and_tag = hash4_with_bits(
    src,
    pos,
    h_bits + zstd_short_cache_tag_bits,
  )
  (
    hash_and_tag >> zstd_short_cache_tag_bits,
    hash_and_tag & ((1 << zstd_short_cache_tag_bits) - 1),
  )
}

///|
fn hash8_with_tag(src : Bytes, pos : Int, h_bits : Int) -> (Int, Int) {
  let hash_and_tag = hash8_with_bits(
    src,
    pos,
    h_bits + zstd_short_cache_tag_bits,
  )
  (
    hash_and_tag >> zstd_short_cache_tag_bits,
    hash_and_tag & ((1 << zstd_short_cache_tag_bits) - 1),
  )
}

///|
fn virtual_eq_at(
  history : Bytes,
  src : Bytes,
  start : Int,
  history_len : Int,
  pos : Int,
  cand : Int,
  count : Int,
) -> Bool {
  if pos < 0 || cand < 0 || pos + count > src.length() - start {
    return false
  }
  let mut i = 0
  while i < count {
    if src[start + pos + i] !=
      virtual_match_source_byte(history, src, start, history_len, cand + i) {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn virtual_match_len_from(
  history : Bytes,
  src : Bytes,
  start : Int,
  history_len : Int,
  pos : Int,
  cand : Int,
  block_len : Int,
  min_match : Int,
) -> Int {
  let mut ml = min_match
  while pos + ml < block_len &&
        src[start + pos + ml] ==
        virtual_match_source_byte(history, src, start, history_len, cand + ml) {
    ml = ml + 1
  }
  ml
}

///|
fn extend_virtual_match_backward(
  history : Bytes,
  src : Bytes,
  start : Int,
  history_len : Int,
  anchor : Int,
  pos : Int,
  cand : Int,
  ml : Int,
  cand_low_exclusive : Int,
) -> (Int, Int, Int) {
  let mut p = pos
  let mut c = cand
  let mut m = ml
  while p > anchor &&
        c > cand_low_exclusive &&
        src[start + p - 1] ==
        virtual_match_source_byte(history, src, start, history_len, c - 1) {
    p = p - 1
    c = c - 1
    m = m + 1
  }
  (p, c, m)
}

///|
fn index_overlap_check(prefix_lowest_index : Int, rep_index : Int) -> Bool {
  if rep_index < 0 {
    return false
  }
  if prefix_lowest_index <= 0 {
    return true
  }
  rep_index <= prefix_lowest_index || rep_index >= prefix_lowest_index + 4
}

///|
fn dfast_hash_bits_for_level3_dict(
  history_len : Int,
  block_len : Int,
) -> (Int, Int) {
  let total_len = history_len + block_len
  let mut bits = 0
  let mut n = if total_len <= 1 { 1 } else { total_len - 1 }
  while n > 0 {
    bits = bits + 1
    n = n >> 1
  }
  let mut window_log = if bits < 10 { 10 } else { bits }
  if window_log < 10 {
    window_log = 10
  } else if window_log > 27 {
    window_log = 27
  }
  let h_bits_long = if window_log + 1 > 15 { 15 } else { window_log + 1 }
  let h_bits_short = if window_log > 14 { 14 } else { window_log }
  (h_bits_long, h_bits_short)
}

///|
fn collect_level3_dict_dfast_sequences(
  src : Bytes,
  start : Int,
  block_len : Int,
  ll_values : Array[Int],
  off_values : Array[Int],
  ml_values : Array[Int],
  max_sequences : Int,
  history : Bytes,
  max_match_offset : Int,
  rep1 : Int,
  rep2 : Int,
) -> Unit {
  let history_len = history.length()
  if block_len < 8 || history_len < 8 {
    return
  }
  let end_virtual = history_len + block_len
  let lowest_index = if max_match_offset > 0 && end_virtual > max_match_offset {
    end_virtual - max_match_offset
  } else {
    0
  }
  let dict_start_index = if lowest_index < history_len {
    lowest_index
  } else {
    history_len
  }

  let (h_bits_long, h_bits_short) = dfast_hash_bits_for_level3_dict(
    history_len, block_len,
  )
  let fast_hash_fill_step = 3
  let dict_hash_long_index : Array[Int] = Array::make(1 << h_bits_long, -1)
  let dict_hash_long_tag : Array[Int] = Array::make(1 << h_bits_long, -1)
  let dict_hash_short_index : Array[Int] = Array::make(1 << h_bits_short, -1)
  let dict_hash_short_tag : Array[Int] = Array::make(1 << h_bits_short, -1)
  let prefix_hash_long : Array[Int] = Array::make(1 << h_bits_long, -1)
  let prefix_hash_short : Array[Int] = Array::make(1 << h_bits_short, -1)

  // Follow ZSTD_fillDoubleHashTableForCDict full-load behavior.
  let dict_iend = history_len - 8
  let mut dict_pos = 0
  while dict_pos + fast_hash_fill_step - 1 <= dict_iend {
    let mut i = 0
    while i < fast_hash_fill_step {
      let p = dict_pos + i
      let (sm_hash, sm_tag) = hash4_with_tag(history, p, h_bits_short)
      let (lg_hash, lg_tag) = hash8_with_tag(history, p, h_bits_long)
      if i == 0 {
        dict_hash_short_index[sm_hash] = p
        dict_hash_short_tag[sm_hash] = sm_tag
      }
      if i == 0 || dict_hash_long_index[lg_hash] < 0 {
        dict_hash_long_index[lg_hash] = p
        dict_hash_long_tag[lg_hash] = lg_tag
      }
      i = i + 1
    }
    dict_pos = dict_pos + fast_hash_fill_step
  }

  let mut ip = 0
  let mut anchor = 0
  let mut offset_1 = rep1
  let mut offset_2 = rep2
  let ilimit = block_len - 8

  while ip < ilimit && ll_values.length() < max_sequences {
    let current_virtual = history_len + ip
    let old_ip = ip
    let old_current_virtual = current_virtual
    let h_long = hash8_with_bits(src, start + ip, h_bits_long)
    let h_short = hash4_with_bits(src, start + ip, h_bits_short)
    let (dict_h_long, dict_tag_long) = hash8_with_tag(
      src,
      start + ip,
      h_bits_long,
    )
    let (dict_h_short, dict_tag_short) = hash4_with_tag(
      src,
      start + ip,
      h_bits_short,
    )
    let match_index_long = prefix_hash_long[h_long]
    let match_index_short = prefix_hash_short[h_short]
    let dict_match_index_long = if dict_hash_long_tag[dict_h_long] ==
      dict_tag_long {
      dict_hash_long_index[dict_h_long]
    } else {
      -1
    }
    let dict_match_index_short = if dict_hash_short_tag[dict_h_short] ==
      dict_tag_short {
      dict_hash_short_index[dict_h_short]
    } else {
      -1
    }

    prefix_hash_long[h_long] = current_virtual
    prefix_hash_short[h_short] = current_virtual

    let rep_index = current_virtual + 1 - offset_1
    if offset_1 > 0 &&
      index_overlap_check(history_len, rep_index) &&
      virtual_eq_at(history, src, start, history_len, ip + 1, rep_index, 4) {
      let rep_length = virtual_match_len_from(
        history,
        src,
        start,
        history_len,
        ip + 1,
        rep_index,
        block_len,
        4,
      )
      ip = ip + 1
      ll_values.push(ip - anchor)
      off_values.push(offset_1)
      ml_values.push(rep_length)
      ip = ip + rep_length
      anchor = ip
      if ip <= ilimit {
        while ip <= ilimit && ll_values.length() < max_sequences {
          let current2 = history_len + ip
          let rep_index2 = current2 - offset_2
          if offset_2 <= 0 ||
            !index_overlap_check(history_len, rep_index2) ||
            !virtual_eq_at(history, src, start, history_len, ip, rep_index2, 4) {
            break
          }
          let rep_length2 = virtual_match_len_from(
            history, src, start, history_len, ip, rep_index2, block_len, 4,
          )
          let tmp_offset = offset_2
          offset_2 = offset_1
          offset_1 = tmp_offset
          ll_values.push(0)
          off_values.push(tmp_offset)
          ml_values.push(rep_length2)
          if ip + 8 <= block_len {
            let h_rep_long = hash8_with_bits(src, start + ip, h_bits_long)
            prefix_hash_long[h_rep_long] = current2
          }
          let h_rep_short = hash4_with_bits(src, start + ip, h_bits_short)
          prefix_hash_short[h_rep_short] = current2
          ip = ip + rep_length2
          anchor = ip
        }
      }
      continue
    }

    let mut found = false
    let mut found_pos = ip
    let mut found_cand = -1
    let mut found_ml = 0
    let mut found_offset = 0
    let mut found_cand_low = 0
    if match_index_long >= history_len &&
      match_index_long >= lowest_index &&
      virtual_eq_at(history, src, start, history_len, ip, match_index_long, 8) {
      found = true
      found_pos = ip
      found_cand = match_index_long
      found_ml = virtual_match_len_from(
        history, src, start, history_len, ip, match_index_long, block_len, 8,
      )
      found_offset = current_virtual - match_index_long
      found_cand_low = history_len
    } else if dict_match_index_long > dict_start_index &&
      virtual_eq_at(
        history, src, start, history_len, ip, dict_match_index_long, 8,
      ) {
      found = true
      found_pos = ip
      found_cand = dict_match_index_long
      found_ml = virtual_match_len_from(
        history, src, start, history_len, ip, dict_match_index_long, block_len, 8,
      )
      found_offset = current_virtual - dict_match_index_long
      found_cand_low = dict_start_index
    }

    if !found {
      let mut short_cand = -1
      let mut short_is_dict = false
      if match_index_short > history_len &&
        match_index_short >= lowest_index &&
        virtual_eq_at(
          history, src, start, history_len, ip, match_index_short, 4,
        ) {
        short_cand = match_index_short
      } else if dict_match_index_short > dict_start_index &&
        virtual_eq_at(
          history, src, start, history_len, ip, dict_match_index_short, 4,
        ) {
        short_cand = dict_match_index_short
        short_is_dict = true
      }

      if short_cand >= 0 {
        let h_long_p1 = hash8_with_bits(src, start + ip + 1, h_bits_long)
        let (dict_h_long_p1, dict_tag_long_p1) = hash8_with_tag(
          src,
          start + ip + 1,
          h_bits_long,
        )
        let match_long_p1 = prefix_hash_long[h_long_p1]
        let dict_match_long_p1 = if dict_hash_long_tag[dict_h_long_p1] ==
          dict_tag_long_p1 {
          dict_hash_long_index[dict_h_long_p1]
        } else {
          -1
        }
        prefix_hash_long[h_long_p1] = current_virtual + 1

        if match_long_p1 >= history_len &&
          match_long_p1 >= lowest_index &&
          virtual_eq_at(
            history,
            src,
            start,
            history_len,
            ip + 1,
            match_long_p1,
            8,
          ) {
          found = true
          found_pos = ip + 1
          found_cand = match_long_p1
          found_ml = virtual_match_len_from(
            history,
            src,
            start,
            history_len,
            ip + 1,
            match_long_p1,
            block_len,
            8,
          )
          found_offset = history_len + found_pos - match_long_p1
          found_cand_low = history_len
        } else if dict_match_long_p1 > dict_start_index &&
          virtual_eq_at(
            history,
            src,
            start,
            history_len,
            ip + 1,
            dict_match_long_p1,
            8,
          ) {
          found = true
          found_pos = ip + 1
          found_cand = dict_match_long_p1
          found_ml = virtual_match_len_from(
            history,
            src,
            start,
            history_len,
            ip + 1,
            dict_match_long_p1,
            block_len,
            8,
          )
          found_offset = history_len + found_pos - dict_match_long_p1
          found_cand_low = dict_start_index
        } else {
          found = true
          found_pos = ip
          found_cand = short_cand
          found_ml = virtual_match_len_from(
            history, src, start, history_len, ip, short_cand, block_len, 4,
          )
          found_offset = current_virtual - short_cand
          found_cand_low = if short_is_dict {
            dict_start_index
          } else {
            history_len
          }
        }
      }
    }

    if !found {
      ip = ip + ((ip - anchor) >> 8) + 1
      continue
    }

    let (new_pos, _, new_ml) = extend_virtual_match_backward(
      history, src, start, history_len, anchor, found_pos, found_cand, found_ml,
      found_cand_low,
    )
    let ll = new_pos - anchor
    if ll < 0 || found_offset <= 0 || new_ml < 4 {
      ip = old_ip + 1
      continue
    }
    ll_values.push(ll)
    off_values.push(found_offset)
    ml_values.push(new_ml)
    if ll_values.length() >= max_sequences {
      break
    }

    offset_2 = offset_1
    offset_1 = found_offset
    ip = new_pos + new_ml
    anchor = ip

    if ip <= ilimit {
      let index_to_insert = old_ip + 2
      if index_to_insert + 8 <= block_len {
        let h_insert_long = hash8_with_bits(
          src,
          start + index_to_insert,
          h_bits_long,
        )
        prefix_hash_long[h_insert_long] = old_current_virtual + 2
      }
      if ip - 2 >= 0 && ip - 2 + 8 <= block_len {
        let h_ip_long = hash8_with_bits(src, start + ip - 2, h_bits_long)
        prefix_hash_long[h_ip_long] = history_len + ip - 2
      }
      if index_to_insert + 4 <= block_len {
        let h_insert_short = hash4_with_bits(
          src,
          start + index_to_insert,
          h_bits_short,
        )
        prefix_hash_short[h_insert_short] = old_current_virtual + 2
      }
      if ip - 1 >= 0 && ip - 1 + 4 <= block_len {
        let h_ip_short = hash4_with_bits(src, start + ip - 1, h_bits_short)
        prefix_hash_short[h_ip_short] = history_len + ip - 1
      }

      while ip <= ilimit && ll_values.length() < max_sequences {
        let current2 = history_len + ip
        let rep_index2 = current2 - offset_2
        if offset_2 <= 0 ||
          !index_overlap_check(history_len, rep_index2) ||
          !virtual_eq_at(history, src, start, history_len, ip, rep_index2, 4) {
          break
        }
        let rep_length2 = virtual_match_len_from(
          history, src, start, history_len, ip, rep_index2, block_len, 4,
        )
        let tmp_offset = offset_2
        offset_2 = offset_1
        offset_1 = tmp_offset
        ll_values.push(0)
        off_values.push(tmp_offset)
        ml_values.push(rep_length2)
        if ip + 8 <= block_len {
          let h_rep_long = hash8_with_bits(src, start + ip, h_bits_long)
          prefix_hash_long[h_rep_long] = current2
        }
        let h_rep_short = hash4_with_bits(src, start + ip, h_bits_short)
        prefix_hash_short[h_rep_short] = current2
        ip = ip + rep_length2
        anchor = ip
      }
    }
  }
}

///|
fn should_use_level3_dict_dfast(
  level : Int,
  history_len : Int,
  block_len : Int,
  min_match : Int,
) -> Bool {
  // TODO(zstd-rdl.39.5): enable after full level-3 dict dfast parity validation.
  true &&
  level == 3 &&
  history_len >= 8 &&
  block_len >= 8 &&
  min_match >= 4 &&
  block_len <= 16 << 10
}

///|
fn collect_level_aligned_sequences(
  src : Bytes,
  start : Int,
  block_len : Int,
  level : Int,
  ll_values : Array[Int],
  off_values : Array[Int],
  ml_values : Array[Int],
  max_sequences : Int,
  history? : Bytes = b"",
  search_depth? : Int = 1,
  max_match_offset? : Int = 0,
  rep1? : Int = 1,
  rep2? : Int = 4,
  rep3? : Int = 8,
  min_match? : Int = 3,
) -> Unit {
  if should_use_level3_dict_dfast(level, history.length(), block_len, min_match) {
    collect_level3_dict_dfast_sequences(
      src, start, block_len, ll_values, off_values, ml_values, max_sequences, history,
      max_match_offset, rep1, rep2,
    )
    return
  }
  collect_greedy_sequences(
    src,
    start,
    block_len,
    ll_values,
    off_values,
    ml_values,
    max_sequences,
    history~,
    search_depth~,
    max_match_offset~,
    rep1~,
    rep2~,
    rep3~,
    min_match~,
  )
}
