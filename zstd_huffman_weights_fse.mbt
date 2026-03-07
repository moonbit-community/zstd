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
let huf_weight_fse_table_log_max = 6

///|
fn read_huffman_weights_fse(
  src : Bytes,
  start : Int,
  end_pos : Int,
) -> Array[Int] raise ZstdError {
  if start >= end_pos {
    raise CorruptionDetected
  }

  let (header_size, table_log, max_symbol, normalized_counter) = read_fse_ncount_header(
    src, start, end_pos, huf_max_nb_bits, huf_weight_fse_table_log_max,
  )

  let (next_state, nb_bits, symbols) = build_fse_symbol_decode_table(
    normalized_counter, max_symbol, table_log,
  )

  let payload_start = start + header_size
  if payload_start >= end_pos {
    raise CorruptionDetected
  }

  decode_fse_symbol_stream_reverse(
    src, payload_start, end_pos, table_log, next_state, nb_bits, symbols, 255,
  )
}

///|
fn decode_fse_symbol_stream_reverse(
  src : Bytes,
  start : Int,
  end_pos : Int,
  table_log : Int,
  next_state : Array[Int],
  nb_bits : Array[Int],
  symbols : Array[Int],
  max_output_size : Int,
) -> Array[Int] raise ZstdError {
  if table_log <= 0 ||
    start >= end_pos ||
    max_output_size <= 0 ||
    next_state.length() == 0 ||
    next_state.length() != nb_bits.length() ||
    next_state.length() != symbols.length() {
    raise CorruptionDetected
  }

  let table_size = (1 : Int) << table_log
  if table_size != next_state.length() {
    raise CorruptionDetected
  }

  let ds_ptr : Ref[Int] = { val: start }
  let ds_limit : Ref[Int] = { val: start + 8 }
  let ds_bits_consumed : Ref[Int] = { val: 0 }
  let ds_bit_container : Ref[UInt64] = { val: (0 : UInt64) }
  init_fse_dstream(
    src, start, end_pos, ds_ptr, ds_limit, ds_bits_consumed, ds_bit_container,
  )

  let state1_ref : Ref[Int] = {
    val: fse_read_bits(ds_bits_consumed, ds_bit_container, table_log).to_int(),
  }
  let state2_ref : Ref[Int] = {
    val: fse_read_bits(ds_bits_consumed, ds_bit_container, table_log).to_int(),
  }
  if state1_ref.val < 0 ||
    state1_ref.val >= table_size ||
    state2_ref.val < 0 ||
    state2_ref.val >= table_size {
    raise CorruptionDetected
  }

  if fse_reload_dstream(
      src, start, ds_ptr, ds_limit, ds_bits_consumed, ds_bit_container,
    ) ==
    fse_dstream_overflow {
    raise CorruptionDetected
  }

  let out : Array[Int] = Array::new()

  while true {
    let (symbol1, next1) = decode_fse_symbol_update(
      ds_bits_consumed,
      ds_bit_container,
      state1_ref.val,
      table_size,
      next_state,
      nb_bits,
      symbols,
    )
    out.push(symbol1)
    if out.length() > max_output_size {
      raise CorruptionDetected
    }
    state1_ref.val = next1

    if fse_reload_dstream(
        src, start, ds_ptr, ds_limit, ds_bits_consumed, ds_bit_container,
      ) ==
      fse_dstream_overflow {
      out.push(read_fse_table_symbol(state2_ref.val, table_size, symbols))
      break
    }

    let (symbol2, next2) = decode_fse_symbol_update(
      ds_bits_consumed,
      ds_bit_container,
      state2_ref.val,
      table_size,
      next_state,
      nb_bits,
      symbols,
    )
    out.push(symbol2)
    if out.length() > max_output_size {
      raise CorruptionDetected
    }
    state2_ref.val = next2

    if fse_reload_dstream(
        src, start, ds_ptr, ds_limit, ds_bits_consumed, ds_bit_container,
      ) ==
      fse_dstream_overflow {
      out.push(read_fse_table_symbol(state1_ref.val, table_size, symbols))
      break
    }
  }

  if out.length() <= 0 || out.length() > max_output_size {
    raise CorruptionDetected
  }
  out
}

///|
fn decode_fse_symbol_update(
  bits_consumed : Ref[Int],
  bit_container : Ref[UInt64],
  state : Int,
  table_size : Int,
  next_state : Array[Int],
  nb_bits : Array[Int],
  symbols : Array[Int],
) -> (Int, Int) raise ZstdError {
  let symbol = read_fse_table_symbol(state, table_size, symbols)

  let bit_count = nb_bits[state]
  if bit_count < 0 || bit_count > 24 {
    raise CorruptionDetected
  }
  let add = fse_read_bits(bits_consumed, bit_container, bit_count).to_int()

  let next = next_state[state] + add
  if next < 0 || next >= table_size {
    raise CorruptionDetected
  }
  (symbol, next)
}

///|
fn read_fse_table_symbol(
  state : Int,
  table_size : Int,
  symbols : Array[Int],
) -> Int raise ZstdError {
  if state < 0 || state >= table_size || state >= symbols.length() {
    raise CorruptionDetected
  }
  symbols[state]
}

///|
let fse_dstream_unfinished = 0

///|
let fse_dstream_end_of_buffer = 1

///|
let fse_dstream_completed = 2

///|
let fse_dstream_overflow = 3

///|
fn init_fse_dstream(
  src : Bytes,
  start : Int,
  end_pos : Int,
  ptr : Ref[Int],
  limit : Ref[Int],
  bits_consumed : Ref[Int],
  bit_container : Ref[UInt64],
) -> Unit raise ZstdError {
  if start < 0 || end_pos <= start || end_pos > src.length() {
    raise CorruptionDetected
  }
  let src_size = end_pos - start
  let last_byte = src[end_pos - 1].to_uint().reinterpret_as_int()
  if last_byte == 0 {
    raise CorruptionDetected
  }

  limit.val = start + 8
  if src_size >= 8 {
    ptr.val = end_pos - 8
    bit_container.val = read_u64_le(src, ptr.val)
    bits_consumed.val = 8 - high_bit_positive(last_byte)
  } else {
    ptr.val = start
    bit_container.val = read_u64_le_padded(src, start, end_pos)
    bits_consumed.val = 8 - high_bit_positive(last_byte) + (8 - src_size) * 8
  }
}

///|
fn read_u64_le_padded(src : Bytes, start : Int, end_pos : Int) -> UInt64 {
  let mut value : UInt64 = 0
  let mut i = 0
  while start + i < end_pos && i < 8 {
    value = value + (src[start + i].to_uint().to_uint64() << (i * 8))
    i = i + 1
  }
  value
}

///|
fn fse_read_bits(
  bits_consumed : Ref[Int],
  bit_container : Ref[UInt64],
  count : Int,
) -> UInt64 raise ZstdError {
  if count < 0 || count > 24 {
    raise CorruptionDetected
  }
  if count == 0 {
    return (0 : UInt64)
  }
  let start = (64 - bits_consumed.val - count) & 63
  let mask = ((1 : UInt64) << count) - (1 : UInt64)
  let value = (bit_container.val >> start) & mask
  bits_consumed.val = bits_consumed.val + count
  value
}

///|
fn fse_reload_dstream(
  src : Bytes,
  start : Int,
  ptr : Ref[Int],
  limit : Ref[Int],
  bits_consumed : Ref[Int],
  bit_container : Ref[UInt64],
) -> Int raise ZstdError {
  if bits_consumed.val > 64 {
    return fse_dstream_overflow
  }
  if ptr.val < start {
    raise CorruptionDetected
  }

  if ptr.val >= limit.val {
    let moved = bits_consumed.val >> 3
    ptr.val = ptr.val - moved
    if ptr.val < start {
      raise CorruptionDetected
    }
    bits_consumed.val = bits_consumed.val & 7
    bit_container.val = read_u64_le(src, ptr.val)
    return fse_dstream_unfinished
  }

  if ptr.val == start {
    if bits_consumed.val < 64 {
      return fse_dstream_end_of_buffer
    }
    return fse_dstream_completed
  }

  let mut nb_bytes = bits_consumed.val >> 3
  let mut result = fse_dstream_unfinished
  if ptr.val - nb_bytes < start {
    nb_bytes = ptr.val - start
    result = fse_dstream_end_of_buffer
  }
  ptr.val = ptr.val - nb_bytes
  bits_consumed.val = bits_consumed.val - nb_bytes * 8
  bit_container.val = read_u64_le(src, ptr.val)
  result
}
