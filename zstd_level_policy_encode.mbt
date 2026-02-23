///|
fn sequence_cap_by_block(base_cap : Int, block_len : Int) -> Int {
  if block_len <= 0 {
    return 1
  }
  let block_cap0 = block_len / 3
  let block_cap = if block_cap0 < 1 {
    1
  } else if block_cap0 > 255 {
    255
  } else {
    block_cap0
  }
  if base_cap < block_cap {
    base_cap
  } else {
    block_cap
  }
}

///|
fn general_rle_sequence_cap(level : Int, block_len : Int) -> Int {
  let base = if level >= 20 { 127 } else if level >= 16 { 63 } else { 31 }
  sequence_cap_by_block(base, block_len)
}

///|
fn compressed_fse_sequence_cap(level : Int, block_len : Int) -> Int {
  let base = if level >= 20 { 24 } else { 16 }
  sequence_cap_by_block(base, block_len)
}

///|
fn mixed_sequence_cap(level : Int, block_len : Int) -> Int {
  let base = if level >= 22 { 32 } else { 20 }
  sequence_cap_by_block(base, block_len)
}

///|
fn predefined_multi_sequence_cap(level : Int, block_len : Int) -> Int {
  let base = if level >= 20 { 24 } else { 12 }
  sequence_cap_by_block(base, block_len)
}

///|
fn level_periodic_target_seq_count(level : Int, block_len : Int) -> Int {
  if block_len < 32 {
    1
  } else if level >= 24 {
    4
  } else if level >= 22 {
    3
  } else if level >= 18 {
    2
  } else {
    1
  }
}

///|
fn prefer_compressed_fse_candidate(level : Int, block_len : Int) -> Bool {
  level >= 22 || (level >= 21 && block_len >= 1024)
}

///|
fn prefer_mixed_candidate(level : Int, block_len : Int) -> Bool {
  level >= 20 || (level >= 19 && block_len >= 768)
}

///|
fn prefer_periodic_candidate(level : Int, block_len : Int) -> Bool {
  level >= 18 || (level >= 17 && block_len >= 384)
}

///|
fn greedy_sequence_search_depth(
  level : Int,
  block_len : Int,
  enable_long_distance_matching? : Bool = false,
) -> Int {
  let base0 = if level >= 22 {
    24
  } else if level >= 18 {
    16
  } else if level >= 14 {
    12
  } else {
    8
  }
  let base = if enable_long_distance_matching {
    if base0 + 6 > 40 {
      40
    } else {
      base0 + 6
    }
  } else {
    base0
  }
  if block_len >= 32768 {
    if base + 8 > 40 {
      40
    } else {
      base + 8
    }
  } else if block_len >= 8192 {
    if base + 4 > 40 {
      40
    } else {
      base + 4
    }
  } else {
    base
  }
}

///|
fn greedy_sequence_min_match(level : Int, block_len : Int) -> Int {
  ignore(block_len)
  if level <= 2 {
    5
  } else if level <= 4 {
    4
  } else {
    3
  }
}
