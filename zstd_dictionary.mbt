///|
let zstd_dictionary_magic_number : UInt = 0xEC30A437

///|
priv struct DictionaryState {
  has_dictionary : Bool
  dict_id : UInt
  history : Bytes
  rep1 : Int
  rep2 : Int
  rep3 : Int
  huf_valid : Bool
  huf_tree_desc : Bytes
  huf_max_bits : Int
  huf_left : Array[Int]
  huf_right : Array[Int]
  huf_symbol : Array[Int]
  ll_valid : Bool
  ll_kind : Int
  ll_code : UInt
  ll_table_log : Int
  ll_table_next_state : Array[Int]
  ll_table_nb_add_bits : Array[Int]
  ll_table_nb_bits : Array[Int]
  ll_table_base_values : Array[Int]
  ll_header : Bytes
  off_valid : Bool
  off_kind : Int
  off_code : UInt
  off_table_log : Int
  off_table_next_state : Array[Int]
  off_table_nb_add_bits : Array[Int]
  off_table_nb_bits : Array[Int]
  off_table_base_values : Array[Int]
  off_header : Bytes
  ml_valid : Bool
  ml_kind : Int
  ml_code : UInt
  ml_table_log : Int
  ml_table_next_state : Array[Int]
  ml_table_nb_add_bits : Array[Int]
  ml_table_nb_bits : Array[Int]
  ml_table_base_values : Array[Int]
  ml_header : Bytes
}

///|
fn empty_dictionary_state() -> DictionaryState {
  {
    has_dictionary: false,
    dict_id: 0,
    history: b"",
    rep1: 1,
    rep2: 4,
    rep3: 8,
    huf_valid: false,
    huf_tree_desc: b"",
    huf_max_bits: 0,
    huf_left: Array::new(),
    huf_right: Array::new(),
    huf_symbol: Array::new(),
    ll_valid: false,
    ll_kind: 0,
    ll_code: 0,
    ll_table_log: 0,
    ll_table_next_state: Array::new(),
    ll_table_nb_add_bits: Array::new(),
    ll_table_nb_bits: Array::new(),
    ll_table_base_values: Array::new(),
    ll_header: b"",
    off_valid: false,
    off_kind: 0,
    off_code: 0,
    off_table_log: 0,
    off_table_next_state: Array::new(),
    off_table_nb_add_bits: Array::new(),
    off_table_nb_bits: Array::new(),
    off_table_base_values: Array::new(),
    off_header: b"",
    ml_valid: false,
    ml_kind: 0,
    ml_code: 0,
    ml_table_log: 0,
    ml_table_next_state: Array::new(),
    ml_table_nb_add_bits: Array::new(),
    ml_table_nb_bits: Array::new(),
    ml_table_base_values: Array::new(),
    ml_header: b"",
  }
}

///|
fn raw_dictionary_state(dictionary : Bytes) -> DictionaryState {
  {
    ..empty_dictionary_state(),
    has_dictionary: dictionary.length() > 0,
    history: dictionary,
  }
}

///|
fn parse_dictionary_state(
  dictionary : Bytes,
) -> DictionaryState raise ZstdError {
  if dictionary.length() == 0 {
    return empty_dictionary_state()
  }

  if dictionary.length() < 8 {
    return raw_dictionary_state(dictionary)
  }

  let magic = read_u32_le(dictionary, 0)
  if magic != zstd_dictionary_magic_number {
    return raw_dictionary_state(dictionary)
  }

  let dict_id = read_u32_le(dictionary, 4)
  let dict_len = dictionary.length()
  let mut pos = 8

  let huf_start = pos
  let (huf_size, huf_max_bits, huf_left, huf_right, huf_symbol) = read_huffman_tree_description(
    dictionary, pos, dict_len,
  )
  let huf_tree_desc = dictionary_slice(dictionary, huf_start, huf_size)
  pos = pos + huf_size

  let (
    off_size,
    off_header,
    off_table_log,
    off_table_next_state,
    off_table_nb_add_bits,
    off_table_nb_bits,
    off_table_base_values,
  ) = parse_dictionary_sequence_table(
    dictionary, pos, dict_len, sequence_symbol_offset,
  )
  pos = pos + off_size

  let (
    ml_size,
    ml_header,
    ml_table_log,
    ml_table_next_state,
    ml_table_nb_add_bits,
    ml_table_nb_bits,
    ml_table_base_values,
  ) = parse_dictionary_sequence_table(
    dictionary, pos, dict_len, sequence_symbol_match_length,
  )
  pos = pos + ml_size

  let (
    ll_size,
    ll_header,
    ll_table_log,
    ll_table_next_state,
    ll_table_nb_add_bits,
    ll_table_nb_bits,
    ll_table_base_values,
  ) = parse_dictionary_sequence_table(
    dictionary, pos, dict_len, sequence_symbol_literal_length,
  )
  pos = pos + ll_size

  ensure_range(dict_len, pos, 12)
  let dict_content_size = dict_len - (pos + 12)
  if dict_content_size <= 0 {
    raise CorruptionDetected
  }

  let rep1_u = read_u32_le(dictionary, pos).to_uint64()
  let rep2_u = read_u32_le(dictionary, pos + 4).to_uint64()
  let rep3_u = read_u32_le(dictionary, pos + 8).to_uint64()
  let dict_content_size_u = dict_content_size.to_uint64()
  if rep1_u == 0 ||
    rep2_u == 0 ||
    rep3_u == 0 ||
    rep1_u > dict_content_size_u ||
    rep2_u > dict_content_size_u ||
    rep3_u > dict_content_size_u {
    raise CorruptionDetected
  }
  pos = pos + 12

  {
    has_dictionary: true,
    dict_id,
    history: dictionary[pos:].to_bytes(),
    rep1: rep1_u.to_int(),
    rep2: rep2_u.to_int(),
    rep3: rep3_u.to_int(),
    huf_valid: true,
    huf_tree_desc,
    huf_max_bits,
    huf_left,
    huf_right,
    huf_symbol,
    ll_valid: true,
    ll_kind: sequence_table_kind_compressed,
    ll_code: 0,
    ll_table_log,
    ll_table_next_state,
    ll_table_nb_add_bits,
    ll_table_nb_bits,
    ll_table_base_values,
    ll_header,
    off_valid: true,
    off_kind: sequence_table_kind_compressed,
    off_code: 0,
    off_table_log,
    off_table_next_state,
    off_table_nb_add_bits,
    off_table_nb_bits,
    off_table_base_values,
    off_header,
    ml_valid: true,
    ml_kind: sequence_table_kind_compressed,
    ml_code: 0,
    ml_table_log,
    ml_table_next_state,
    ml_table_nb_add_bits,
    ml_table_nb_bits,
    ml_table_base_values,
    ml_header,
  }
}

///|
fn dictionary_slice(
  src : Bytes,
  start : Int,
  len : Int,
) -> Bytes raise ZstdError {
  ensure_range(src.length(), start, len)
  let out : Array[Byte] = Array::new()
  append_bytes(out, src, start, len)
  Bytes::from_array(out)
}

///|
fn parse_dictionary_sequence_table(
  src : Bytes,
  start : Int,
  end_pos : Int,
  symbol_type : Int,
) -> (Int, Bytes, Int, Array[Int], Array[Int], Array[Int], Array[Int]) raise ZstdError {
  let (max_symbol, table_log_max) = sequence_symbol_limits(symbol_type)
  let (header_size, table_log, decoded_max_symbol, normalized_counter) = read_fse_ncount_header(
    src, start, end_pos, max_symbol, table_log_max,
  )
  let header = dictionary_slice(src, start, header_size)
  let (next_state, nb_add_bits, nb_bits, base_values) = build_sequence_fse_decode_table(
    normalized_counter, decoded_max_symbol, table_log, symbol_type,
  )
  (
    header_size, header, table_log, next_state, nb_add_bits, nb_bits, base_values,
  )
}
