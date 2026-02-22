///|
fn find_smallest_open_huffman_node(
  node_weight : Array[Int],
  node_parent : Array[Int],
  exclude : Int,
) -> Int {
  let mut best = -1
  let mut i = 0
  while i < node_weight.length() {
    if node_parent[i] == -1 && i != exclude {
      if best == -1 ||
        node_weight[i] < node_weight[best] ||
        (node_weight[i] == node_weight[best] && i < best) {
        best = i
      }
    }
    i = i + 1
  }
  best
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
  if leaves.length() < 2 {
    return (false, Array::new(), 0)
  }

  let node_weight : Array[Int] = Array::new()
  let node_parent : Array[Int] = Array::new()
  let node_symbol : Array[Int] = Array::new()
  let mut i = 0
  while i < leaves.length() {
    let symbol = leaves[i]
    node_weight.push(freq[symbol])
    node_parent.push(-1)
    node_symbol.push(symbol)
    i = i + 1
  }

  let mut open_nodes = leaves.length()
  while open_nodes > 1 {
    let first = find_smallest_open_huffman_node(node_weight, node_parent, -1)
    if first < 0 {
      return (false, Array::new(), 0)
    }
    let second = find_smallest_open_huffman_node(
      node_weight, node_parent, first,
    )
    if second < 0 {
      return (false, Array::new(), 0)
    }
    node_weight.push(node_weight[first] + node_weight[second])
    node_parent.push(-1)
    node_symbol.push(-1)
    let parent_idx = node_weight.length() - 1
    node_parent[first] = parent_idx
    node_parent[second] = parent_idx
    open_nodes = open_nodes - 1
  }

  let lengths = Array::make(max_symbol + 1, 0)
  let mut max_len = 0
  i = 0
  while i < leaves.length() {
    let symbol = node_symbol[i]
    if symbol < 0 || symbol > max_symbol {
      return (false, Array::new(), 0)
    }
    let mut depth = 0
    let mut node = i
    while node_parent[node] != -1 {
      depth = depth + 1
      node = node_parent[node]
    }
    if depth <= 0 {
      return (false, Array::new(), 0)
    }
    lengths[symbol] = depth
    if depth > max_len {
      max_len = depth
    }
    i = i + 1
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
fn encode_literals_huffman_single_stream(
  literals : Bytes,
  codes : Array[UInt],
  nb_bits : Array[Int],
) -> Bytes {
  if codes.length() != nb_bits.length() {
    return b""
  }
  let bits : Array[Int] = Array::new()
  let mut i = 0
  while i < literals.length() {
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
fn build_literal_huffman_model(
  literals : Bytes,
) -> (Bool, Int, Array[Int], Array[UInt], Array[Int]) raise ZstdError {
  if literals.length() < 2 || literals.length() > 1023 {
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
fn try_build_compressed_literals_section(
  literals : Bytes,
) -> Bytes raise ZstdError {
  let lit_len = literals.length()
  if lit_len < 2 || lit_len > 1023 {
    return b""
  }
  let (ok, last_symbol, weights, codes, nb_bits) = build_literal_huffman_model(
    literals,
  )
  if !ok {
    return b""
  }
  let tree_desc = build_huffman_direct_weights_description(weights, last_symbol)
  if tree_desc.length() == 0 {
    return b""
  }
  let bitstream = encode_literals_huffman_single_stream(
    literals, codes, nb_bits,
  )
  if bitstream.length() == 0 {
    return b""
  }
  let lit_c_size = tree_desc.length() + bitstream.length()
  if lit_c_size <= 0 || lit_c_size > 1023 {
    return b""
  }

  let out : Array[Byte] = Array::new()
  let header = ((lit_len.reinterpret_as_uint() & 0x3FF) << 4) +
    ((lit_c_size.reinterpret_as_uint() & 0x3FF) << 14) +
    2
  append_u24_le(out, header)
  append_bytes(out, tree_desc, 0, tree_desc.length())
  append_bytes(out, bitstream, 0, bitstream.length())
  Bytes::from_array(out)
}
