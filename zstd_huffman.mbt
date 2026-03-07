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
let huf_max_nb_bits = 12

///|
fn read_huffman_tree_description(
  src : Bytes,
  start : Int,
  end_pos : Int,
) -> (Int, Int, Array[Int], Array[Int], Array[Int]) raise ZstdError {
  if start >= end_pos {
    raise CorruptionDetected
  }
  let header_byte = src[start].to_uint().reinterpret_as_int()
  let weights : Array[Int] = if header_byte < 128 {
    if start + 1 + header_byte > end_pos {
      raise CorruptionDetected
    }
    read_huffman_weights_fse(src, start + 1, start + 1 + header_byte)
  } else {
    let number_of_weights = header_byte - 127
    if number_of_weights <= 0 || number_of_weights > 128 {
      raise CorruptionDetected
    }
    let packed_size = (number_of_weights + 1) >> 1
    if start + 1 + packed_size > end_pos {
      raise CorruptionDetected
    }

    let parsed_weights : Array[Int] = Array::new()
    let mut i = 0
    while i < number_of_weights {
      parsed_weights.push(0)
      i = i + 1
    }

    i = 0
    while i < number_of_weights {
      let b = src[start + 1 + (i >> 1)].to_uint().reinterpret_as_int()
      if (i & 1) == 0 {
        parsed_weights[i] = (b >> 4) & 0xF
      } else {
        parsed_weights[i] = b & 0xF
      }
      i = i + 1
    }
    parsed_weights
  }
  let consumed_size = if header_byte < 128 {
    1 + header_byte
  } else {
    1 + ((weights.length() + 1) >> 1)
  }

  let mut weight_total = 0
  let mut non_zero_weights = 0
  let mut i = 0
  while i < weights.length() {
    let w = weights[i]
    if w < 0 || w > huf_max_nb_bits {
      raise CorruptionDetected
    }
    if w > 0 {
      weight_total = weight_total + ((1 : Int) << (w - 1))
      non_zero_weights = non_zero_weights + 1
    }
    i = i + 1
  }
  if weight_total <= 0 {
    raise CorruptionDetected
  }

  let max_bits = high_bit_positive(weight_total) + 1
  if max_bits <= 0 || max_bits > huf_max_nb_bits {
    raise CorruptionDetected
  }

  let total_weight = (1 : Int) << max_bits
  let rest = total_weight - weight_total
  if rest <= 0 || !is_power_of_two(rest) {
    raise CorruptionDetected
  }
  let last_weight = high_bit_positive(rest) + 1
  if last_weight <= 0 || last_weight > huf_max_nb_bits {
    raise CorruptionDetected
  }
  weights.push(last_weight)
  non_zero_weights = non_zero_weights + 1

  if non_zero_weights < 2 {
    raise CorruptionDetected
  }

  let (left, right, symbol) = build_huffman_tree_from_weights(weights, max_bits)
  (consumed_size, max_bits, left, right, symbol)
}

///|
fn build_huffman_tree_from_weights(
  weights : Array[Int],
  max_bits : Int,
) -> (Array[Int], Array[Int], Array[Int]) raise ZstdError {
  let nb_bits : Array[Int] = Array::new()
  let mut i = 0
  while i < weights.length() {
    let w = weights[i]
    let n = if w > 0 { max_bits + 1 - w } else { 0 }
    if n < 0 || n > max_bits {
      raise CorruptionDetected
    }
    nb_bits.push(n)
    i = i + 1
  }

  let symbols_by_weight : Array[Int] = Array::new()
  let mut weight = 1
  while weight <= max_bits {
    i = 0
    while i < weights.length() {
      if weights[i] == weight {
        symbols_by_weight.push(i)
      }
      i = i + 1
    }
    weight = weight + 1
  }
  if symbols_by_weight.length() < 2 {
    raise CorruptionDetected
  }

  let codes : Array[Int] = Array::new()
  i = 0
  while i < nb_bits.length() {
    codes.push(0)
    i = i + 1
  }

  let first_symbol = symbols_by_weight[0]
  let first_bits = nb_bits[first_symbol]
  if first_bits <= 0 {
    raise CorruptionDetected
  }

  let code_ref : Ref[Int] = { val: 0 }
  let current_bits_ref : Ref[Int] = { val: first_bits }

  i = 0
  while i < symbols_by_weight.length() {
    let s = symbols_by_weight[i]
    let n = nb_bits[s]
    if n <= 0 {
      raise CorruptionDetected
    }
    if n > current_bits_ref.val {
      raise CorruptionDetected
    }
    if n < current_bits_ref.val {
      code_ref.val = code_ref.val >> (current_bits_ref.val - n)
      current_bits_ref.val = n
    }

    codes[s] = code_ref.val
    code_ref.val = code_ref.val + 1
    i = i + 1
  }

  let left : Array[Int] = Array::new()
  let right : Array[Int] = Array::new()
  let symbol : Array[Int] = Array::new()

  ignore(add_huffman_node(left, right, symbol))

  i = 0
  while i < nb_bits.length() {
    let n = nb_bits[i]
    if n > 0 {
      insert_huffman_code(left, right, symbol, codes[i], n, i)
    }
    i = i + 1
  }

  (left, right, symbol)
}

///|
fn add_huffman_node(
  left : Array[Int],
  right : Array[Int],
  symbol : Array[Int],
) -> Int {
  left.push(-1)
  right.push(-1)
  symbol.push(-1)
  left.length() - 1
}

///|
fn insert_huffman_code(
  left : Array[Int],
  right : Array[Int],
  symbol : Array[Int],
  code : Int,
  nb_bits : Int,
  value : Int,
) -> Unit raise ZstdError {
  let mut node = 0
  let mut bit_index = nb_bits - 1
  while bit_index >= 0 {
    let bit = (code >> bit_index) & 1
    let last_bit = bit_index == 0

    if bit == 0 {
      let next = left[node]
      if last_bit {
        if next != -1 {
          raise CorruptionDetected
        }
        let leaf = add_huffman_node(left, right, symbol)
        symbol[leaf] = value
        left[node] = leaf
      } else if next == -1 {
        let created = add_huffman_node(left, right, symbol)
        left[node] = created
        node = created
      } else {
        node = next
      }
    } else {
      let next = right[node]
      if last_bit {
        if next != -1 {
          raise CorruptionDetected
        }
        let leaf = add_huffman_node(left, right, symbol)
        symbol[leaf] = value
        right[node] = leaf
      } else if next == -1 {
        let created = add_huffman_node(left, right, symbol)
        right[node] = created
        node = created
      } else {
        node = next
      }
    }

    bit_index = bit_index - 1
  }
}

///|
fn decode_huffman_single_stream(
  src : Bytes,
  start : Int,
  end_pos : Int,
  output_size : Int,
  max_bits : Int,
  left : Array[Int],
  right : Array[Int],
  symbol : Array[Int],
) -> Bytes raise ZstdError {
  ignore(max_bits)
  if output_size < 0 || start >= end_pos {
    raise CorruptionDetected
  }

  let out : Array[Byte] = Array::new()
  let br_byte : Ref[Int] = { val: end_pos - 1 }
  let br_bit : Ref[Int] = { val: -1 }
  init_reverse_bit_reader(src, start, br_byte, br_bit)

  let mut i = 0
  while i < output_size {
    let decoded = decode_one_huffman_symbol(
      src, start, br_byte, br_bit, left, right, symbol,
    )
    out.push(decoded.reinterpret_as_uint().to_byte())
    i = i + 1
  }

  if !reverse_bits_consumed(start, br_byte, br_bit) {
    raise CorruptionDetected
  }

  Bytes::from_array(out)
}

///|
fn decode_huffman_four_streams(
  src : Bytes,
  start : Int,
  end_pos : Int,
  output_size : Int,
  max_bits : Int,
  left : Array[Int],
  right : Array[Int],
  symbol : Array[Int],
) -> Bytes raise ZstdError {
  if output_size < 0 || start + 6 > end_pos {
    raise CorruptionDetected
  }

  let stream1_size = src[start].to_uint().reinterpret_as_int() +
    (src[start + 1].to_uint().reinterpret_as_int() << 8)
  let stream2_size = src[start + 2].to_uint().reinterpret_as_int() +
    (src[start + 3].to_uint().reinterpret_as_int() << 8)
  let stream3_size = src[start + 4].to_uint().reinterpret_as_int() +
    (src[start + 5].to_uint().reinterpret_as_int() << 8)

  let streams_start = start + 6
  let remaining = end_pos - streams_start
  let stream4_size = remaining - stream1_size - stream2_size - stream3_size

  if stream1_size <= 0 ||
    stream2_size <= 0 ||
    stream3_size <= 0 ||
    stream4_size <= 0 {
    raise CorruptionDetected
  }

  let stream1_start = streams_start
  let stream1_end = stream1_start + stream1_size
  let stream2_start = stream1_end
  let stream2_end = stream2_start + stream2_size
  let stream3_start = stream2_end
  let stream3_end = stream3_start + stream3_size
  let stream4_start = stream3_end
  let stream4_end = stream4_start + stream4_size

  if stream4_end != end_pos {
    raise CorruptionDetected
  }

  let segment_size = (output_size + 3) / 4
  let out1_size = segment_size
  let out2_size = segment_size
  let out3_size = segment_size
  let out4_size = output_size - 3 * segment_size
  if out4_size < 0 {
    raise CorruptionDetected
  }

  let out1 = decode_huffman_single_stream(
    src, stream1_start, stream1_end, out1_size, max_bits, left, right, symbol,
  )
  let out2 = decode_huffman_single_stream(
    src, stream2_start, stream2_end, out2_size, max_bits, left, right, symbol,
  )
  let out3 = decode_huffman_single_stream(
    src, stream3_start, stream3_end, out3_size, max_bits, left, right, symbol,
  )
  let out4 = decode_huffman_single_stream(
    src, stream4_start, stream4_end, out4_size, max_bits, left, right, symbol,
  )

  let out : Array[Byte] = Array::new()
  append_bytes(out, out1, 0, out1.length())
  append_bytes(out, out2, 0, out2.length())
  append_bytes(out, out3, 0, out3.length())
  append_bytes(out, out4, 0, out4.length())
  Bytes::from_array(out)
}

///|
fn decode_one_huffman_symbol(
  src : Bytes,
  start : Int,
  br_byte : Ref[Int],
  br_bit : Ref[Int],
  left : Array[Int],
  right : Array[Int],
  symbol : Array[Int],
) -> Int raise ZstdError {
  let mut node = 0
  while true {
    if node < 0 ||
      node >= left.length() ||
      node >= right.length() ||
      node >= symbol.length() {
      raise CorruptionDetected
    }

    let s = symbol[node]
    if s >= 0 {
      return s
    }

    let bit = read_reverse_bit(src, start, br_byte, br_bit)
    node = if bit == 0 { left[node] } else { right[node] }
  }
  raise CorruptionDetected
}

///|
fn is_power_of_two(value : Int) -> Bool {
  value > 0 && (value & (value - 1)) == 0
}
