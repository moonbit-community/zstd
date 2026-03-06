///|
fn high_bit_positive_noerr_huf(value : Int) -> Int {
  if value <= 0 {
    return 0
  }
  let mut v = value
  let mut bit = -1
  while v > 0 {
    bit = bit + 1
    v = v >> 1
  }
  bit
}

///|
fn huf_optimal_table_log_cheap(src_size : Int, max_symbol : Int) -> Int {
  let mut table_log = 11
  if src_size <= 1 {
    return table_log
  }
  let max_bits_src = high_bit_positive_noerr_huf(src_size - 1) - 1
  if max_bits_src < table_log {
    table_log = max_bits_src
  }
  let min_bits_src = high_bit_positive_noerr_huf(src_size) + 1
  let min_bits_symbols = high_bit_positive_noerr_huf(max_symbol) + 2
  let min_bits = if min_bits_src < min_bits_symbols {
    min_bits_src
  } else {
    min_bits_symbols
  }
  if min_bits > table_log {
    table_log = min_bits
  }
  if table_log < 5 {
    table_log = 5
  }
  if table_log > huf_max_nb_bits {
    table_log = huf_max_nb_bits
  }
  table_log
}

///|
fn enforce_huffman_max_height(
  sorted_counts : Array[Int],
  nb_bits : Array[Int],
  leaf_count : Int,
  target_nb_bits : Int,
) -> Int {
  if leaf_count <= 0 {
    return 0
  }
  let mut largest_bits = nb_bits[leaf_count - 1]
  if largest_bits <= target_nb_bits {
    return largest_bits
  }

  let mut total_cost = 0
  let base_cost = 1 << (largest_bits - target_nb_bits)
  let mut n = leaf_count - 1
  while n >= 0 && nb_bits[n] > target_nb_bits {
    total_cost = total_cost + base_cost - (1 << (largest_bits - nb_bits[n]))
    nb_bits[n] = target_nb_bits
    n = n - 1
  }
  while n >= 0 && nb_bits[n] == target_nb_bits {
    n = n - 1
  }
  total_cost = total_cost >> (largest_bits - target_nb_bits)

  let no_symbol = -1
  let rank_last = Array::make(huf_max_nb_bits + 2, no_symbol)
  let mut current_nb_bits = target_nb_bits
  let mut pos = n
  while pos >= 0 {
    if nb_bits[pos] < current_nb_bits {
      current_nb_bits = nb_bits[pos]
      let rank = target_nb_bits - current_nb_bits
      if rank >= 0 && rank < rank_last.length() {
        rank_last[rank] = pos
      }
    }
    pos = pos - 1
  }

  while total_cost > 0 {
    let mut n_bits_to_decrease = high_bit_positive_noerr_huf(total_cost) + 1
    while n_bits_to_decrease > 1 {
      let high_pos = if n_bits_to_decrease < rank_last.length() {
        rank_last[n_bits_to_decrease]
      } else {
        no_symbol
      }
      let low_pos = if n_bits_to_decrease - 1 < rank_last.length() {
        rank_last[n_bits_to_decrease - 1]
      } else {
        no_symbol
      }
      if high_pos == no_symbol {
        n_bits_to_decrease = n_bits_to_decrease - 1
      } else if low_pos == no_symbol {
        break
      } else {
        let high_total = sorted_counts[high_pos]
        let low_total = 2 * sorted_counts[low_pos]
        if high_total <= low_total {
          break
        }
        n_bits_to_decrease = n_bits_to_decrease - 1
      }
    }

    while n_bits_to_decrease <= huf_max_nb_bits &&
          (
            n_bits_to_decrease >= rank_last.length() ||
            rank_last[n_bits_to_decrease] == no_symbol
          ) {
      n_bits_to_decrease = n_bits_to_decrease + 1
    }
    if n_bits_to_decrease >= rank_last.length() ||
      rank_last[n_bits_to_decrease] == no_symbol {
      break
    }

    total_cost = total_cost - (1 << (n_bits_to_decrease - 1))
    let hp = rank_last[n_bits_to_decrease]
    nb_bits[hp] = nb_bits[hp] + 1

    if rank_last[n_bits_to_decrease - 1] == no_symbol {
      rank_last[n_bits_to_decrease - 1] = hp
    }
    if hp == 0 {
      rank_last[n_bits_to_decrease] = no_symbol
    } else {
      rank_last[n_bits_to_decrease] = hp - 1
      let expected_bits = target_nb_bits - n_bits_to_decrease
      if nb_bits[rank_last[n_bits_to_decrease]] != expected_bits {
        rank_last[n_bits_to_decrease] = no_symbol
      }
    }
  }

  while total_cost < 0 {
    if rank_last[1] == no_symbol {
      while n >= 0 && nb_bits[n] == target_nb_bits {
        n = n - 1
      }
      if n + 1 < 0 || n + 1 >= leaf_count {
        break
      }
      nb_bits[n + 1] = nb_bits[n + 1] - 1
      rank_last[1] = n + 1
      total_cost = total_cost + 1
      continue
    }
    if rank_last[1] + 1 >= leaf_count {
      break
    }
    nb_bits[rank_last[1] + 1] = nb_bits[rank_last[1] + 1] - 1
    rank_last[1] = rank_last[1] + 1
    total_cost = total_cost + 1
  }

  largest_bits = target_nb_bits
  largest_bits
}

///|
fn build_literal_huffman_lengths_from_frequencies(
  freq : Array[Int],
  max_symbol : Int,
) -> (Bool, Array[Int], Int) {
  if max_symbol < 0 || max_symbol >= freq.length() {
    return (false, Array::new(), 0)
  }
  let leaves : Array[Int] = Array::new()
  let mut s = 0
  while s <= max_symbol {
    if freq[s] > 0 {
      leaves.push(s)
    }
    s = s + 1
  }
  let leaf_count = leaves.length()
  if leaf_count < 2 {
    return (false, Array::new(), 0)
  }

  let mut i = 1
  while i < leaf_count {
    let key_symbol = leaves[i]
    let key_count = freq[key_symbol]
    let mut j = i - 1
    while j >= 0 && freq[leaves[j]] < key_count {
      leaves[j + 1] = leaves[j]
      j = j - 1
    }
    leaves[j + 1] = key_symbol
    i = i + 1
  }

  let total_nodes = leaf_count * 2
  let node_weight : Array[Int] = Array::make(total_nodes, 0)
  let node_parent : Array[Int] = Array::make(total_nodes, -1)
  let node_depth : Array[Int] = Array::make(total_nodes, 0)
  let node_symbol : Array[Int] = Array::make(total_nodes, -1)

  i = 0
  while i < leaf_count {
    let symbol = leaves[i]
    node_weight[i] = freq[symbol]
    node_symbol[i] = symbol
    i = i + 1
  }

  let mut low_s = leaf_count - 1
  let mut low_n = leaf_count
  let mut node_nb = leaf_count
  let node_root = 2 * leaf_count - 2

  if leaf_count < 2 || node_root >= total_nodes {
    return (false, Array::new(), 0)
  }

  node_weight[node_nb] = node_weight[low_s] + node_weight[low_s - 1]
  node_parent[low_s] = node_nb
  node_parent[low_s - 1] = node_nb
  node_nb = node_nb + 1
  low_s = low_s - 2

  while node_nb <= node_root {
    let n1 = if low_s >= 0 &&
      (low_n >= node_nb || node_weight[low_s] < node_weight[low_n]) {
      let idx = low_s
      low_s = low_s - 1
      idx
    } else {
      let idx = low_n
      low_n = low_n + 1
      idx
    }
    let n2 = if low_s >= 0 &&
      (low_n >= node_nb || node_weight[low_s] < node_weight[low_n]) {
      let idx = low_s
      low_s = low_s - 1
      idx
    } else {
      let idx = low_n
      low_n = low_n + 1
      idx
    }
    if n1 < 0 || n2 < 0 || n1 >= total_nodes || n2 >= total_nodes {
      return (false, Array::new(), 0)
    }
    node_weight[node_nb] = node_weight[n1] + node_weight[n2]
    node_parent[n1] = node_nb
    node_parent[n2] = node_nb
    node_nb = node_nb + 1
  }

  node_depth[node_root] = 0
  let mut n = node_root - 1
  while n >= leaf_count {
    let p = node_parent[n]
    if p < 0 || p >= total_nodes {
      return (false, Array::new(), 0)
    }
    node_depth[n] = node_depth[p] + 1
    n = n - 1
  }

  let mut total = 0
  i = 0
  while i < leaf_count {
    let p = node_parent[i]
    if p < 0 || p >= total_nodes {
      return (false, Array::new(), 0)
    }
    node_depth[i] = node_depth[p] + 1
    total = total + node_weight[i]
    i = i + 1
  }

  let target_nb_bits = huf_optimal_table_log_cheap(total, max_symbol)
  let leaf_nb_bits = Array::make(leaf_count, 0)
  i = 0
  while i < leaf_count {
    leaf_nb_bits[i] = node_depth[i]
    i = i + 1
  }
  let adjusted_max_bits = enforce_huffman_max_height(
    node_weight, leaf_nb_bits, leaf_count, target_nb_bits,
  )

  let lengths = Array::make(max_symbol + 1, 0)
  let mut max_len = 0
  i = 0
  while i < leaf_count {
    let symbol = node_symbol[i]
    if symbol < 0 || symbol > max_symbol {
      return (false, Array::new(), 0)
    }
    let depth = leaf_nb_bits[i]
    if depth <= 0 {
      return (false, Array::new(), 0)
    }
    lengths[symbol] = depth
    if depth > max_len {
      max_len = depth
    }
    i = i + 1
  }
  if adjusted_max_bits > 0 && adjusted_max_bits < max_len {
    max_len = adjusted_max_bits
  }
  (true, lengths, max_len)
}

///|
fn infer_last_huffman_weight_from_prefix(
  weights : Array[Int],
  last_symbol : Int,
) -> (Bool, Int, Int) raise ZstdError {
  if last_symbol <= 0 || last_symbol >= weights.length() {
    return (false, 0, 0)
  }
  let mut weight_total = 0
  let mut s = 0
  while s < last_symbol {
    let w = weights[s]
    if w < 0 || w > huf_max_nb_bits {
      return (false, 0, 0)
    }
    if w > 0 {
      weight_total = weight_total + ((1 : Int) << (w - 1))
    }
    s = s + 1
  }
  if weight_total <= 0 {
    return (false, 0, 0)
  }
  let max_bits = high_bit_positive(weight_total) + 1
  if max_bits <= 0 || max_bits > huf_max_nb_bits {
    return (false, 0, 0)
  }
  let total_weight = (1 : Int) << max_bits
  let rest = total_weight - weight_total
  if rest <= 0 || !is_power_of_two(rest) {
    return (false, 0, 0)
  }
  let last_weight = high_bit_positive(rest) + 1
  if last_weight <= 0 || last_weight > huf_max_nb_bits {
    return (false, 0, 0)
  }
  (true, max_bits, last_weight)
}

///|
fn build_huffman_canonical_codes_from_weights(
  weights : Array[Int],
  max_symbol : Int,
  max_bits : Int,
) -> (Bool, Array[UInt], Array[Int]) {
  if max_symbol < 0 || max_symbol >= weights.length() {
    return (false, Array::new(), Array::new())
  }
  if max_bits <= 0 || max_bits > huf_max_nb_bits {
    return (false, Array::new(), Array::new())
  }
  let nb_bits = Array::make(max_symbol + 1, 0)
  let mut s = 0
  while s <= max_symbol {
    let w = weights[s]
    if w < 0 || w > max_bits {
      return (false, Array::new(), Array::new())
    }
    if w > 0 {
      let n = max_bits + 1 - w
      if n <= 0 || n > max_bits {
        return (false, Array::new(), Array::new())
      }
      nb_bits[s] = n
    }
    s = s + 1
  }

  let symbols_by_weight : Array[Int] = Array::new()
  let mut weight = 1
  while weight <= max_bits {
    s = 0
    while s <= max_symbol {
      if weights[s] == weight {
        symbols_by_weight.push(s)
      }
      s = s + 1
    }
    weight = weight + 1
  }
  if symbols_by_weight.length() < 2 {
    return (false, Array::new(), Array::new())
  }

  let codes = Array::make(max_symbol + 1, (0 : UInt))
  let first_symbol = symbols_by_weight[0]
  let current_bits_ref : Ref[Int] = { val: nb_bits[first_symbol] }
  if current_bits_ref.val <= 0 {
    return (false, Array::new(), Array::new())
  }
  let code_ref : Ref[Int] = { val: 0 }
  let mut i = 0
  while i < symbols_by_weight.length() {
    let symbol = symbols_by_weight[i]
    let n = nb_bits[symbol]
    if n <= 0 || n > current_bits_ref.val {
      return (false, Array::new(), Array::new())
    }
    if n < current_bits_ref.val {
      code_ref.val = code_ref.val >> (current_bits_ref.val - n)
      current_bits_ref.val = n
    }
    if code_ref.val < 0 || code_ref.val >= (1 : Int) << n {
      return (false, Array::new(), Array::new())
    }
    codes[symbol] = code_ref.val.reinterpret_as_uint()
    code_ref.val = code_ref.val + 1
    i = i + 1
  }
  (true, codes, nb_bits)
}

///|
fn build_huffman_direct_weights_description(
  weights : Array[Int],
  last_symbol : Int,
) -> Bytes {
  if last_symbol <= 0 || last_symbol >= weights.length() || last_symbol > 128 {
    return b""
  }
  let out : Array[Byte] = Array::new()
  out.push((127 + last_symbol).reinterpret_as_uint().to_byte())
  let mut i = 0
  while i < last_symbol {
    let w0 = weights[i]
    let w1 = if i + 1 < last_symbol { weights[i + 1] } else { 0 }
    if w0 < 0 || w0 > huf_max_nb_bits || w1 < 0 || w1 > huf_max_nb_bits {
      return b""
    }
    out.push(((w0 << 4) + w1).reinterpret_as_uint().to_byte())
    i = i + 2
  }
  Bytes::from_array(out)
}

///|
fn append_u16_le_checked(out : Array[Byte], value : Int) -> Bool {
  if value < 0 || value > 0xFFFF {
    return false
  }
  out.push((value & 0xFF).reinterpret_as_uint().to_byte())
  out.push(((value >> 8) & 0xFF).reinterpret_as_uint().to_byte())
  true
}

///|
fn encode_literals_huffman_single_stream_range(
  literals : Bytes,
  start : Int,
  len : Int,
  codes : Array[UInt],
  nb_bits : Array[Int],
) -> Bytes {
  if start < 0 || len <= 0 || start + len > literals.length() {
    return b""
  }
  if codes.length() != nb_bits.length() {
    return b""
  }
  let bits : Array[Int] = Array::new()
  let mut i = start
  while i < start + len {
    let symbol = literals[i].to_uint().reinterpret_as_int()
    if symbol < 0 || symbol >= nb_bits.length() {
      return b""
    }
    let n = nb_bits[symbol]
    if n <= 0 || n > huf_max_nb_bits {
      return b""
    }
    append_bits_be(bits, codes[symbol], n)
    i = i + 1
  }
  build_reverse_bitstream(bits)
}

///|
fn encode_literals_huffman_single_stream(
  literals : Bytes,
  codes : Array[UInt],
  nb_bits : Array[Int],
) -> Bytes {
  encode_literals_huffman_single_stream_range(
    literals,
    0,
    literals.length(),
    codes,
    nb_bits,
  )
}

///|
fn encode_literals_huffman_four_stream(
  literals : Bytes,
  codes : Array[UInt],
  nb_bits : Array[Int],
) -> Bytes {
  let lit_len = literals.length()
  if lit_len < 8 {
    return b""
  }
  let segment_size = (lit_len + 3) / 4
  let out1_size = segment_size
  let out2_size = segment_size
  let out3_size = segment_size
  let out4_size = lit_len - 3 * segment_size
  if out1_size <= 0 || out2_size <= 0 || out3_size <= 0 || out4_size <= 0 {
    return b""
  }
  let stream1 = encode_literals_huffman_single_stream_range(
    literals, 0, out1_size, codes, nb_bits,
  )
  let stream2 = encode_literals_huffman_single_stream_range(
    literals, out1_size, out2_size, codes, nb_bits,
  )
  let stream3 = encode_literals_huffman_single_stream_range(
    literals,
    out1_size + out2_size,
    out3_size,
    codes,
    nb_bits,
  )
  let stream4 = encode_literals_huffman_single_stream_range(
    literals,
    out1_size + out2_size + out3_size,
    out4_size,
    codes,
    nb_bits,
  )
  if stream1.length() == 0 ||
    stream2.length() == 0 ||
    stream3.length() == 0 ||
    stream4.length() == 0 {
    return b""
  }
  let payload : Array[Byte] = Array::new()
  if !append_u16_le_checked(payload, stream1.length()) ||
    !append_u16_le_checked(payload, stream2.length()) ||
    !append_u16_le_checked(payload, stream3.length()) {
    return b""
  }
  append_bytes(payload, stream1, 0, stream1.length())
  append_bytes(payload, stream2, 0, stream2.length())
  append_bytes(payload, stream3, 0, stream3.length())
  append_bytes(payload, stream4, 0, stream4.length())
  Bytes::from_array(payload)
}

///|
fn build_literal_huffman_model(
  literals : Bytes,
) -> (Bool, Int, Array[Int], Array[UInt], Array[Int]) raise ZstdError {
  if literals.length() < 2 || literals.length() > 128 << 10 {
    return (false, 0, Array::new(), Array::new(), Array::new())
  }
  let freq = Array::make(256, 0)
  let mut max_symbol = -1
  let mut i = 0
  while i < literals.length() {
    let symbol = literals[i].to_uint().reinterpret_as_int()
    freq[symbol] = freq[symbol] + 1
    if symbol > max_symbol {
      max_symbol = symbol
    }
    i = i + 1
  }
  if max_symbol <= 0 || max_symbol > 128 {
    return (false, 0, Array::new(), Array::new(), Array::new())
  }

  let (len_ok, lengths, max_len) = build_literal_huffman_lengths_from_frequencies(
    freq, max_symbol,
  )
  if !len_ok || max_len <= 0 || max_len > huf_max_nb_bits {
    return (false, 0, Array::new(), Array::new(), Array::new())
  }

  let weights = Array::make(max_symbol + 1, 0)
  let mut s = 0
  while s <= max_symbol {
    let len = lengths[s]
    if len > 0 {
      let w = max_len + 1 - len
      if w <= 0 || w > huf_max_nb_bits {
        return (false, 0, Array::new(), Array::new(), Array::new())
      }
      weights[s] = w
    }
    s = s + 1
  }

  let mut last_symbol = max_symbol
  while last_symbol > 0 && weights[last_symbol] == 0 {
    last_symbol = last_symbol - 1
  }
  if last_symbol <= 0 || last_symbol > 128 || weights[last_symbol] <= 0 {
    return (false, 0, Array::new(), Array::new(), Array::new())
  }

  let (infer_ok, inferred_max_bits, inferred_last_weight) = infer_last_huffman_weight_from_prefix(
    weights, last_symbol,
  )
  if !infer_ok ||
    inferred_max_bits != max_len ||
    inferred_last_weight != weights[last_symbol] {
    return (false, 0, Array::new(), Array::new(), Array::new())
  }

  let (codes_ok, codes, nb_bits) = build_huffman_canonical_codes_from_weights(
    weights, max_symbol, max_len,
  )
  if !codes_ok {
    return (false, 0, Array::new(), Array::new(), Array::new())
  }
  (true, last_symbol, weights, codes, nb_bits)
}

///|
fn build_compressed_literals_section_with_stream_payload(
  lit_len : Int,
  tree_desc : Bytes,
  stream_payload : Bytes,
  single_stream : Bool,
) -> Bytes {
  if lit_len <= 0 || tree_desc.length() == 0 || stream_payload.length() == 0 {
    return b""
  }
  let lit_c_size = tree_desc.length() + stream_payload.length()
  let literals_block_type : UInt = 2
  let out : Array[Byte] = Array::new()
  if single_stream {
    if lit_len > 1023 || lit_c_size > 1023 {
      return b""
    }
    let header = ((lit_len.reinterpret_as_uint() & 0x3FF) << 4) +
      ((lit_c_size.reinterpret_as_uint() & 0x3FF) << 14) +
      literals_block_type
    append_u24_le(out, header)
  } else if lit_len >= 6 && lit_len <= 1023 && lit_c_size <= 1023 {
    let size_format_1 : UInt = 1
    let header = ((lit_len.reinterpret_as_uint() & 0x3FF) << 4) +
      ((lit_c_size.reinterpret_as_uint() & 0x3FF) << 14) +
      (size_format_1 << 2) +
      literals_block_type
    append_u24_le(out, header)
  } else if lit_len <= 0x3FFF && lit_c_size <= 0x3FFF {
    let size_format_2 : UInt = 2
    let header = ((lit_len.reinterpret_as_uint() & 0x3FFF) << 4) +
      ((lit_c_size.reinterpret_as_uint() & 0x3FFF) << 18) +
      (size_format_2 << 2) +
      literals_block_type
    append_u32_le(out, header)
  } else if lit_len <= 0x3FFFF && lit_c_size <= 0x3FFFF {
    let size_format_3 : UInt = 3
    let lit_c_low = lit_c_size & 0x3FF
    let lit_c_high = lit_c_size >> 10
    if lit_c_high < 0 || lit_c_high > 0xFF {
      return b""
    }
    let header = ((lit_len.reinterpret_as_uint() & 0x3FFFF) << 4) +
      ((lit_c_low.reinterpret_as_uint() & 0x3FF) << 22) +
      (size_format_3 << 2) +
      literals_block_type
    append_u32_le(out, header)
    out.push(lit_c_high.reinterpret_as_uint().to_byte())
  } else {
    return b""
  }
  append_bytes(out, tree_desc, 0, tree_desc.length())
  append_bytes(out, stream_payload, 0, stream_payload.length())
  Bytes::from_array(out)
}

///|
fn try_build_compressed_literals_section(
  literals : Bytes,
) -> Bytes raise ZstdError {
  let lit_len = literals.length()
  if lit_len < 2 || lit_len > 128 << 10 {
    return b""
  }
  let (ok, last_symbol, weights, codes, nb_bits) = build_literal_huffman_model(
    literals,
  )
  if !ok {
    return b""
  }
  let direct_tree_desc = build_huffman_direct_weights_description(
    weights, last_symbol,
  )
  let fse_tree_desc = try_build_huffman_fse_weights_description(
    weights,
    last_symbol,
    allow_ctable_fallback=lit_len >= 384,
  )
  let tree_desc = if direct_tree_desc.length() == 0 {
    fse_tree_desc
  } else if fse_tree_desc.length() == 0 {
    direct_tree_desc
  } else if fse_tree_desc.length() < direct_tree_desc.length() {
    fse_tree_desc
  } else {
    direct_tree_desc
  }
  if tree_desc.length() == 0 {
    return b""
  }
  let single_stream_payload = encode_literals_huffman_single_stream(
    literals, codes, nb_bits,
  )
  let single_section = if single_stream_payload.length() > 0 {
    build_compressed_literals_section_with_stream_payload(
      lit_len, tree_desc, single_stream_payload, true,
    )
  } else {
    b""
  }
  let four_stream_payload = encode_literals_huffman_four_stream(
    literals, codes, nb_bits,
  )
  let four_section = if four_stream_payload.length() > 0 {
    build_compressed_literals_section_with_stream_payload(
      lit_len, tree_desc, four_stream_payload, false,
    )
  } else {
    b""
  }
  if single_section.length() == 0 {
    return four_section
  }
  if four_section.length() == 0 {
    return single_section
  }
  if lit_len >= 256 {
    four_section
  } else {
    single_section
  }
}
