///|
fn sum_int_array(values : Array[Int]) -> Int {
  let mut total = 0
  let mut i = 0
  while i < values.length() {
    total = total + values[i]
    i = i + 1
  }
  total
}

///|
fn make_constant_int_array(len : Int, value : Int) -> Array[Int] {
  let out : Array[Int] = Array::new()
  let mut i = 0
  while i < len {
    out.push(value)
    i = i + 1
  }
  out
}

///|
fn source_option_score_bits(
  source_bytes : Bytes,
  init_bits : Int,
  extra_bits : Array[Int],
  trans_nb_bits : Array[Int],
) -> Int {
  source_bytes.length() * 8 +
  init_bits +
  sum_int_array(extra_bits) +
  sum_int_array(trans_nb_bits)
}

///|
fn choose_sequence_source_mode(
  values : Array[Int],
  symbol_type : Int,
  level : Int,
) -> (
  Bool,
  UInt,
  Bytes,
  Int,
  Int,
  Array[UInt],
  Array[Int],
  Array[Int],
  Array[Int],
) raise ZstdError {
  if values.length() <= 0 {
    return (
      false,
      0,
      b"",
      0,
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }
  let mut have = false
  let mut best_mode : UInt = 0
  let mut best_source = b""
  let mut best_init_state = 0
  let mut best_init_bits = 0
  let mut best_extras : Array[UInt] = Array::new()
  let mut best_extra_bits : Array[Int] = Array::new()
  let mut best_trans_bits : Array[Int] = Array::new()
  let mut best_trans_nb_bits : Array[Int] = Array::new()
  let mut best_score = 0

  // RLE mode (01)
  let rle = if symbol_type == sequence_symbol_offset {
    try_encode_common_offset_symbol(values)
  } else {
    let max_code = if symbol_type == sequence_symbol_literal_length {
      35
    } else if symbol_type == sequence_symbol_match_length {
      52
    } else {
      raise CorruptionDetected
    }
    try_encode_common_symbol(symbol_type, max_code, values)
  }
  match rle {
    (true, code, extras, bits) => {
      let source_arr : Array[Byte] = Array::new()
      source_arr.push(code.to_byte())
      let source = Bytes::from_array(source_arr)
      let extra_bits = make_constant_int_array(values.length(), bits)
      let score = source_option_score_bits(source, 0, extra_bits, Array::new())
      have = true
      best_mode = 1
      best_source = source
      best_init_state = 0
      best_init_bits = 0
      best_extras = extras
      best_extra_bits = extra_bits
      best_trans_bits = Array::new()
      best_trans_nb_bits = Array::new()
      best_score = score
    }
    _ => ()
  }

  // Predefined mode (00)
  let predefined = select_predefined_state_path(values, symbol_type)
  match predefined {
    (true, states, extras, extra_bits, trans_bits, trans_nb_bits) => {
      let init_bits = if symbol_type == sequence_symbol_literal_length {
        ll_predefined_table_log
      } else if symbol_type == sequence_symbol_offset {
        of_predefined_table_log
      } else if symbol_type == sequence_symbol_match_length {
        ml_predefined_table_log
      } else {
        raise CorruptionDetected
      }
      let score = source_option_score_bits(
        b"", init_bits, extra_bits, trans_nb_bits,
      )
      if !have || score < best_score || (score == best_score && best_mode != 0) {
        have = true
        best_mode = 0
        best_source = b""
        best_init_state = states[0]
        best_init_bits = init_bits
        best_extras = extras
        best_extra_bits = extra_bits
        best_trans_bits = trans_bits
        best_trans_nb_bits = trans_nb_bits
        best_score = score
      }
    }
    _ => ()
  }

  // Compressed mode (10)
  if level >= 13 {
    let compressed = build_compressed_sequence_source(values, symbol_type)
    match compressed {
      (
        true,
        header,
        init_state,
        table_log,
        extras,
        extra_bits,
        trans_bits,
        trans_nb_bits,
      ) => {
        let score = source_option_score_bits(
          header, table_log, extra_bits, trans_nb_bits,
        )
        if !have ||
          score < best_score ||
          (
            score == best_score &&
            (
              (level >= 22 && best_mode != 2) ||
              (best_mode != 2 && best_mode != 0)
            )
          ) {
          have = true
          best_mode = 2
          best_source = header
          best_init_state = init_state
          best_init_bits = table_log
          best_extras = extras
          best_extra_bits = extra_bits
          best_trans_bits = trans_bits
          best_trans_nb_bits = trans_nb_bits
          best_score = score
        }
      }
      _ => ()
    }
  }

  if have {
    (
      true, best_mode, best_source, best_init_state, best_init_bits, best_extras,
      best_extra_bits, best_trans_bits, best_trans_nb_bits,
    )
  } else {
    (
      false,
      0,
      b"",
      0,
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }
}

///|
fn choose_offset_source_mode_with_repcodes(
  off_values : Array[Int],
  ll_values : Array[Int],
  level : Int,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (
  Bool,
  UInt,
  Bytes,
  Int,
  Int,
  Array[UInt],
  Array[Int],
  Array[Int],
  Array[Int],
) raise ZstdError {
  if off_values.length() <= 0 || ll_values.length() != off_values.length() {
    return (
      false,
      0,
      b"",
      0,
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }
  let mut have = false
  let mut best_mode : UInt = 0
  let mut best_source = b""
  let mut best_init_state = 0
  let mut best_init_bits = 0
  let mut best_extras : Array[UInt] = Array::new()
  let mut best_extra_bits : Array[Int] = Array::new()
  let mut best_trans_bits : Array[Int] = Array::new()
  let mut best_trans_nb_bits : Array[Int] = Array::new()
  let mut best_score = 0

  // RLE mode (01)
  let rle = try_encode_common_offset_symbol_with_repcodes(
    off_values, ll_values, rep1, rep2, rep3,
  )
  match rle {
    (true, code, extras, bits) => {
      let source_arr : Array[Byte] = Array::new()
      source_arr.push(code.to_byte())
      let source = Bytes::from_array(source_arr)
      let extra_bits = make_constant_int_array(off_values.length(), bits)
      let score = source_option_score_bits(source, 0, extra_bits, Array::new())
      have = true
      best_mode = 1
      best_source = source
      best_init_state = 0
      best_init_bits = 0
      best_extras = extras
      best_extra_bits = extra_bits
      best_trans_bits = Array::new()
      best_trans_nb_bits = Array::new()
      best_score = score
    }
    _ => ()
  }

  // Predefined mode (00)
  let predefined = select_predefined_offset_state_path(
    off_values, ll_values, rep1, rep2, rep3,
  )
  match predefined {
    (true, states, extras, extra_bits, trans_bits, trans_nb_bits) => {
      let init_bits = of_predefined_table_log
      let score = source_option_score_bits(
        b"", init_bits, extra_bits, trans_nb_bits,
      )
      if !have || score < best_score || (score == best_score && best_mode != 0) {
        have = true
        best_mode = 0
        best_source = b""
        best_init_state = states[0]
        best_init_bits = init_bits
        best_extras = extras
        best_extra_bits = extra_bits
        best_trans_bits = trans_bits
        best_trans_nb_bits = trans_nb_bits
        best_score = score
      }
    }
    _ => ()
  }

  // Compressed mode (10)
  if level >= 13 {
    let compressed = build_compressed_sequence_source(
      off_values, sequence_symbol_offset,
    )
    match compressed {
      (
        true,
        header,
        init_state,
        table_log,
        extras,
        extra_bits,
        trans_bits,
        trans_nb_bits,
      ) => {
        let score = source_option_score_bits(
          header, table_log, extra_bits, trans_nb_bits,
        )
        if !have ||
          score < best_score ||
          (
            score == best_score &&
            (
              (level >= 22 && best_mode != 2) ||
              (best_mode != 2 && best_mode != 0)
            )
          ) {
          have = true
          best_mode = 2
          best_source = header
          best_init_state = init_state
          best_init_bits = table_log
          best_extras = extras
          best_extra_bits = extra_bits
          best_trans_bits = trans_bits
          best_trans_nb_bits = trans_nb_bits
          best_score = score
        }
      }
      _ => ()
    }
  }

  if have {
    (
      true, best_mode, best_source, best_init_state, best_init_bits, best_extras,
      best_extra_bits, best_trans_bits, best_trans_nb_bits,
    )
  } else {
    (
      false,
      0,
      b"",
      0,
      0,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }
}

///|
fn build_general_mixed_sequence_payload(
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
  if level < 15 || block_len < 96 {
    return b""
  }
  let ll_values : Array[Int] = Array::new()
  let off_values : Array[Int] = Array::new()
  let ml_values : Array[Int] = Array::new()
  let max_sequences = mixed_sequence_cap(level, block_len)
  let search_depth = greedy_sequence_search_depth(
    level,
    block_len,
    enable_long_distance_matching~,
  )
  collect_greedy_sequences(
    src,
    start,
    block_len,
    ll_values,
    off_values,
    ml_values,
    max_sequences,
    history=dictionary_history,
    search_depth~,
    max_match_offset~,
  )
  let seq_count = ll_values.length()
  if seq_count < 2 {
    return b""
  }
  let (
    ll_ok,
    ll_mode,
    ll_source,
    ll_init_state,
    ll_init_bits,
    ll_extras,
    ll_extra_bits,
    ll_trans_bits,
    ll_trans_nb_bits,
  ) = choose_sequence_source_mode(
    ll_values, sequence_symbol_literal_length, level,
  )
  if !ll_ok {
    return b""
  }
  let (
    off_ok,
    off_mode,
    off_source,
    off_init_state,
    off_init_bits,
    off_extras,
    off_extra_bits,
    off_trans_bits,
    off_trans_nb_bits,
  ) = choose_offset_source_mode_with_repcodes(
    off_values, ll_values, level, rep1, rep2, rep3,
  )
  if !off_ok {
    return b""
  }
  let (
    ml_ok,
    ml_mode,
    ml_source,
    ml_init_state,
    ml_init_bits,
    ml_extras,
    ml_extra_bits,
    ml_trans_bits,
    ml_trans_nb_bits,
  ) = choose_sequence_source_mode(
    ml_values, sequence_symbol_match_length, level,
  )
  if !ml_ok {
    return b""
  }

  let literals = build_literals_from_sequences(
    src, start, block_len, ll_values, ml_values,
  )
  let bits : Array[Int] = Array::new()

  if ll_mode != 1 {
    append_bits_be(bits, ll_init_state.reinterpret_as_uint(), ll_init_bits)
  }
  if off_mode != 1 {
    append_bits_be(bits, off_init_state.reinterpret_as_uint(), off_init_bits)
  }
  if ml_mode != 1 {
    append_bits_be(bits, ml_init_state.reinterpret_as_uint(), ml_init_bits)
  }

  let mut i = 0
  while i < seq_count {
    append_bits_be(bits, off_extras[i], off_extra_bits[i])
    append_bits_be(bits, ml_extras[i], ml_extra_bits[i])
    append_bits_be(bits, ll_extras[i], ll_extra_bits[i])
    if i + 1 < seq_count {
      if ll_mode != 1 {
        append_bits_be(
          bits,
          ll_trans_bits[i].reinterpret_as_uint(),
          ll_trans_nb_bits[i],
        )
      }
      if ml_mode != 1 {
        append_bits_be(
          bits,
          ml_trans_bits[i].reinterpret_as_uint(),
          ml_trans_nb_bits[i],
        )
      }
      if off_mode != 1 {
        append_bits_be(
          bits,
          off_trans_bits[i].reinterpret_as_uint(),
          off_trans_nb_bits[i],
        )
      }
    }
    i = i + 1
  }
  let bitstream = build_reverse_bitstream(bits)

  let payload : Array[Byte] = Array::new()
  append_best_literals_section(payload, literals)
  append_sequence_count(payload, seq_count)
  let modes = (ll_mode << 6) + (off_mode << 4) + (ml_mode << 2)
  payload.push(modes.to_byte())
  if ll_mode == 1 || ll_mode == 2 {
    append_bytes(payload, ll_source, 0, ll_source.length())
  }
  if off_mode == 1 || off_mode == 2 {
    append_bytes(payload, off_source, 0, off_source.length())
  }
  if ml_mode == 1 || ml_mode == 2 {
    append_bytes(payload, ml_source, 0, ml_source.length())
  }
  append_bytes(payload, bitstream, 0, bitstream.length())
  Bytes::from_array(payload)
}
