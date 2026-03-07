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
let sequence_table_kind_rle = 0

///|
let sequence_table_kind_predefined = 1

///|
let sequence_table_kind_compressed = 2

///|
fn decode_compressed_block_minimal(
  src : Bytes,
  block_start : Int,
  block_size : Int,
  out : Array[Byte],
  frame_out_start : Int,
  history : Bytes,
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
  prev_huf_valid : Ref[Bool],
  prev_huf_max_bits : Ref[Int],
  prev_huf_left : Ref[Array[Int]],
  prev_huf_right : Ref[Array[Int]],
  prev_huf_symbol : Ref[Array[Int]],
  prev_ll_valid : Ref[Bool],
  prev_ll_kind : Ref[Int],
  prev_ll_code : Ref[UInt],
  prev_ll_table_log : Ref[Int],
  prev_ll_table_next_state : Ref[Array[Int]],
  prev_ll_table_nb_add_bits : Ref[Array[Int]],
  prev_ll_table_nb_bits : Ref[Array[Int]],
  prev_ll_table_base_values : Ref[Array[Int]],
  prev_off_valid : Ref[Bool],
  prev_off_kind : Ref[Int],
  prev_off_code : Ref[UInt],
  prev_off_table_log : Ref[Int],
  prev_off_table_next_state : Ref[Array[Int]],
  prev_off_table_nb_add_bits : Ref[Array[Int]],
  prev_off_table_nb_bits : Ref[Array[Int]],
  prev_off_table_base_values : Ref[Array[Int]],
  prev_ml_valid : Ref[Bool],
  prev_ml_kind : Ref[Int],
  prev_ml_code : Ref[UInt],
  prev_ml_table_log : Ref[Int],
  prev_ml_table_next_state : Ref[Array[Int]],
  prev_ml_table_nb_add_bits : Ref[Array[Int]],
  prev_ml_table_nb_bits : Ref[Array[Int]],
  prev_ml_table_base_values : Ref[Array[Int]],
  window_size? : Int = 0,
) -> (Int, UInt64, Int, Int, Int) raise ZstdError {
  let src_len = src.length()
  if frame_out_start < 0 || frame_out_start > out.length() {
    raise CorruptionDetected
  }
  ensure_range(src_len, block_start, block_size)
  let block_end = block_start + block_size
  let (seq_pos0, literals) = decode_literals_section_minimal(
    src, block_start, block_end, prev_huf_valid, prev_huf_max_bits, prev_huf_left,
    prev_huf_right, prev_huf_symbol,
  )
  let (number_of_sequences, seq_pos0_end) = parse_sequence_count(
    src, seq_pos0, block_end,
  )
  if number_of_sequences == 0 {
    if seq_pos0_end != block_end {
      raise CorruptionDetected
    }
    append_bytes(out, literals, 0, literals.length())
    return (seq_pos0_end, literals.length().to_uint64(), rep1, rep2, rep3)
  }

  ensure_range(src_len, seq_pos0_end, 1)
  let modes = src[seq_pos0_end].to_uint()
  if (modes & 0x3) != 0 {
    raise CorruptionDetected
  }
  let ll_mode = (modes >> 6) & 0x3
  let off_mode = (modes >> 4) & 0x3
  let ml_mode = (modes >> 2) & 0x3

  let seq_pos_ref : Ref[Int] = { val: seq_pos0_end + 1 }
  let (ll_kind, ll_code) = decode_sequence_source(
    src, block_end, seq_pos_ref, ll_mode, prev_ll_valid, prev_ll_kind, prev_ll_code,
    prev_ll_table_log, prev_ll_table_next_state, prev_ll_table_nb_add_bits, prev_ll_table_nb_bits,
    prev_ll_table_base_values, sequence_symbol_literal_length,
  )
  let (off_kind, off_code) = decode_sequence_source(
    src, block_end, seq_pos_ref, off_mode, prev_off_valid, prev_off_kind, prev_off_code,
    prev_off_table_log, prev_off_table_next_state, prev_off_table_nb_add_bits, prev_off_table_nb_bits,
    prev_off_table_base_values, sequence_symbol_offset,
  )
  let (ml_kind, ml_code) = decode_sequence_source(
    src, block_end, seq_pos_ref, ml_mode, prev_ml_valid, prev_ml_kind, prev_ml_code,
    prev_ml_table_log, prev_ml_table_next_state, prev_ml_table_nb_add_bits, prev_ml_table_nb_bits,
    prev_ml_table_base_values, sequence_symbol_match_length,
  )

  let seq_pos = seq_pos_ref.val
  let has_sequence_bitstream = seq_pos < block_end
  if (
      ll_kind != sequence_table_kind_rle ||
      off_kind != sequence_table_kind_rle ||
      ml_kind != sequence_table_kind_rle
    ) &&
    !has_sequence_bitstream {
    raise CorruptionDetected
  }

  let br_start = seq_pos
  let br_byte : Ref[Int] = { val: block_end - 1 }
  let br_bit : Ref[Int] = { val: -1 }
  if has_sequence_bitstream {
    init_reverse_bit_reader(src, br_start, br_byte, br_bit)
  }

  let ll_state : Ref[Int] = { val: 0 }
  let off_state : Ref[Int] = { val: 0 }
  let ml_state : Ref[Int] = { val: 0 }

  if ll_kind == sequence_table_kind_predefined {
    ll_state.val = init_fse_state_reverse(
      src, br_start, br_byte, br_bit, ll_predefined_table_log,
    )
  } else if ll_kind == sequence_table_kind_compressed {
    if prev_ll_table_log.val <= 0 {
      raise CorruptionDetected
    }
    ll_state.val = init_fse_state_reverse(
      src,
      br_start,
      br_byte,
      br_bit,
      prev_ll_table_log.val,
    )
  }

  if off_kind == sequence_table_kind_predefined {
    off_state.val = init_fse_state_reverse(
      src, br_start, br_byte, br_bit, of_predefined_table_log,
    )
  } else if off_kind == sequence_table_kind_compressed {
    if prev_off_table_log.val <= 0 {
      raise CorruptionDetected
    }
    off_state.val = init_fse_state_reverse(
      src,
      br_start,
      br_byte,
      br_bit,
      prev_off_table_log.val,
    )
  }

  if ml_kind == sequence_table_kind_predefined {
    ml_state.val = init_fse_state_reverse(
      src, br_start, br_byte, br_bit, ml_predefined_table_log,
    )
  } else if ml_kind == sequence_table_kind_compressed {
    if prev_ml_table_log.val <= 0 {
      raise CorruptionDetected
    }
    ml_state.val = init_fse_state_reverse(
      src,
      br_start,
      br_byte,
      br_bit,
      prev_ml_table_log.val,
    )
  }

  let mut literal_pos = 0
  let mut r1 = rep1
  let mut r2 = rep2
  let mut r3 = rep3
  let mut produced : UInt64 = 0

  let seq_count = number_of_sequences.reinterpret_as_int()
  let mut seq_idx = 0
  while seq_idx < seq_count {
    let is_last_sequence = seq_idx + 1 == seq_count

    let (ll_next_state, ll_nb_add_bits, ll_nb_state_bits, ll_base) = sequence_symbol_entry(
      ll_kind,
      ll_code,
      ll_state.val,
      prev_ll_table_next_state.val,
      prev_ll_table_nb_add_bits.val,
      prev_ll_table_nb_bits.val,
      prev_ll_table_base_values.val,
      sequence_symbol_literal_length,
    )

    let (ml_next_state, ml_nb_add_bits, ml_nb_state_bits, ml_base) = sequence_symbol_entry(
      ml_kind,
      ml_code,
      ml_state.val,
      prev_ml_table_next_state.val,
      prev_ml_table_nb_add_bits.val,
      prev_ml_table_nb_bits.val,
      prev_ml_table_base_values.val,
      sequence_symbol_match_length,
    )

    let (off_next_state, off_nb_add_bits, off_nb_state_bits, off_base) = sequence_symbol_entry(
      off_kind,
      off_code,
      off_state.val,
      prev_off_table_next_state.val,
      prev_off_table_nb_add_bits.val,
      prev_off_table_nb_bits.val,
      prev_off_table_base_values.val,
      sequence_symbol_offset,
    )

    let ll0 = ll_base == 0
    let offset = if off_nb_add_bits > 1 {
      if !has_sequence_bitstream {
        raise CorruptionDetected
      }
      let off_extra = read_reverse_bits(
        src, br_start, br_byte, br_bit, off_nb_add_bits,
      )
      let value = off_base + off_extra.reinterpret_as_int()
      if value <= 0 {
        raise CorruptionDetected
      }
      r3 = r2
      r2 = r1
      r1 = value
      value
    } else if off_nb_add_bits == 0 {
      let value = if ll0 { r2 } else { r1 }
      if ll0 {
        r2 = r1
      }
      r1 = value
      value
    } else {
      if !has_sequence_bitstream {
        raise CorruptionDetected
      }
      let low = read_reverse_bits(src, br_start, br_byte, br_bit, 1).reinterpret_as_int()
      let offset_code = off_base + (if ll0 { 1 } else { 0 }) + low
      let value = if offset_code == 1 {
        r2
      } else if offset_code == 2 {
        r3
      } else if offset_code == 3 {
        r1 - 1
      } else {
        raise CorruptionDetected
      }
      if value <= 0 {
        raise CorruptionDetected
      }
      if offset_code != 1 {
        r3 = r2
      }
      r2 = r1
      r1 = value
      value
    }

    let ml_extra = if ml_nb_add_bits == 0 {
      (0 : UInt)
    } else if has_sequence_bitstream {
      read_reverse_bits(src, br_start, br_byte, br_bit, ml_nb_add_bits)
    } else {
      raise CorruptionDetected
    }

    let ll_extra = if ll_nb_add_bits == 0 {
      (0 : UInt)
    } else if has_sequence_bitstream {
      read_reverse_bits(src, br_start, br_byte, br_bit, ll_nb_add_bits)
    } else {
      raise CorruptionDetected
    }

    let lit_len = ll_base + ll_extra.reinterpret_as_int()
    let match_len = ml_base + ml_extra.reinterpret_as_int()

    if literal_pos + lit_len > literals.length() {
      raise CorruptionDetected
    }
    append_bytes(out, literals, literal_pos, lit_len)
    literal_pos = literal_pos + lit_len
    produced = produced + lit_len.to_uint64()

    let mut match_i = 0
    while match_i < match_len {
      let value = read_match_byte(
        out,
        frame_out_start,
        history,
        offset,
        window_size~,
      )
      out.push(value)
      match_i = match_i + 1
    }
    produced = produced + match_len.to_uint64()

    if !is_last_sequence {
      if ll_kind != sequence_table_kind_rle {
        ll_state.val = update_fse_state_reverse(
          src, br_start, br_byte, br_bit, ll_next_state, ll_nb_state_bits,
        )
      }
      if ml_kind != sequence_table_kind_rle {
        ml_state.val = update_fse_state_reverse(
          src, br_start, br_byte, br_bit, ml_next_state, ml_nb_state_bits,
        )
      }
      if off_kind != sequence_table_kind_rle {
        off_state.val = update_fse_state_reverse(
          src, br_start, br_byte, br_bit, off_next_state, off_nb_state_bits,
        )
      }
    }

    seq_idx = seq_idx + 1
  }

  let tail_len = literals.length() - literal_pos
  append_bytes(out, literals, literal_pos, tail_len)
  produced = produced + tail_len.to_uint64()
  if has_sequence_bitstream && !reverse_bits_consumed(br_start, br_byte, br_bit) {
    raise CorruptionDetected
  }
  (block_end, produced, r1, r2, r3)
}

///|
fn read_match_byte(
  out : Array[Byte],
  frame_out_start : Int,
  history : Bytes,
  offset : Int,
  window_size? : Int = 0,
) -> Byte raise ZstdError {
  if offset <= 0 || frame_out_start < 0 || frame_out_start > out.length() {
    raise CorruptionDetected
  }
  if window_size > 0 && offset > window_size {
    raise CorruptionDetected
  }
  let produced = out.length() - frame_out_start
  let history_len = history.length()
  if offset > produced + history_len {
    raise CorruptionDetected
  }

  let from_tail = offset - 1
  if from_tail < produced {
    return out[out.length() - 1 - from_tail]
  }

  let history_from_tail = from_tail - produced
  history[history_len - 1 - history_from_tail]
}

///|
fn sequence_symbol_entry(
  kind : Int,
  code : UInt,
  state : Int,
  table_next_state : Array[Int],
  table_nb_add_bits : Array[Int],
  table_nb_bits : Array[Int],
  table_base_values : Array[Int],
  symbol_type : Int,
) -> (Int, Int, Int, Int) raise ZstdError {
  if kind == sequence_table_kind_rle {
    let (base, nb_add_bits) = sequence_symbol_base_additional_bits(
      symbol_type,
      code.reinterpret_as_int(),
    )
    (0, nb_add_bits, 0, base)
  } else if kind == sequence_table_kind_predefined {
    if symbol_type == sequence_symbol_literal_length {
      ll_predefined_entry(state)
    } else if symbol_type == sequence_symbol_offset {
      of_predefined_entry(state)
    } else if symbol_type == sequence_symbol_match_length {
      ml_predefined_entry(state)
    } else {
      raise CorruptionDetected
    }
  } else if kind == sequence_table_kind_compressed {
    fse_table_entry(
      table_next_state, table_nb_add_bits, table_nb_bits, table_base_values, state,
    )
  } else {
    raise CorruptionDetected
  }
}

///|
fn fse_table_entry(
  table_next_state : Array[Int],
  table_nb_add_bits : Array[Int],
  table_nb_bits : Array[Int],
  table_base_values : Array[Int],
  state : Int,
) -> (Int, Int, Int, Int) raise ZstdError {
  if state < 0 ||
    state >= table_next_state.length() ||
    state >= table_nb_add_bits.length() ||
    state >= table_nb_bits.length() ||
    state >= table_base_values.length() {
    raise CorruptionDetected
  }
  (
    table_next_state[state],
    table_nb_add_bits[state],
    table_nb_bits[state],
    table_base_values[state],
  )
}

///|
fn decode_sequence_source(
  src : Bytes,
  block_end : Int,
  seq_pos_ref : Ref[Int],
  mode : UInt,
  prev_valid : Ref[Bool],
  prev_kind : Ref[Int],
  prev_code : Ref[UInt],
  prev_table_log : Ref[Int],
  prev_table_next_state : Ref[Array[Int]],
  prev_table_nb_add_bits : Ref[Array[Int]],
  prev_table_nb_bits : Ref[Array[Int]],
  prev_table_base_values : Ref[Array[Int]],
  symbol_type : Int,
) -> (Int, UInt) raise ZstdError {
  if mode == 1 {
    if seq_pos_ref.val >= block_end {
      raise CorruptionDetected
    }
    ensure_range(src.length(), seq_pos_ref.val, 1)
    let code = src[seq_pos_ref.val].to_uint()
    seq_pos_ref.val = seq_pos_ref.val + 1
    prev_valid.val = true
    prev_kind.val = sequence_table_kind_rle
    prev_code.val = code
    (sequence_table_kind_rle, code)
  } else if mode == 0 {
    prev_valid.val = true
    prev_kind.val = sequence_table_kind_predefined
    prev_code.val = 0
    (sequence_table_kind_predefined, (0 : UInt))
  } else if mode == 2 {
    let (
      table_header_size,
      table_log,
      table_next_state,
      table_nb_add_bits,
      table_nb_bits,
      table_base_values,
    ) = build_sequence_fse_table_from_header(
      src,
      seq_pos_ref.val,
      block_end,
      symbol_type,
    )
    seq_pos_ref.val = seq_pos_ref.val + table_header_size

    prev_valid.val = true
    prev_kind.val = sequence_table_kind_compressed
    prev_code.val = 0
    prev_table_log.val = table_log
    prev_table_next_state.val = table_next_state
    prev_table_nb_add_bits.val = table_nb_add_bits
    prev_table_nb_bits.val = table_nb_bits
    prev_table_base_values.val = table_base_values

    (sequence_table_kind_compressed, (0 : UInt))
  } else if mode == 3 {
    if !prev_valid.val {
      raise CorruptionDetected
    }
    if prev_kind.val == sequence_table_kind_compressed &&
      prev_table_log.val <= 0 {
      raise CorruptionDetected
    }
    (prev_kind.val, prev_code.val)
  } else {
    raise CorruptionDetected
  }
}

///|
fn init_fse_state_reverse(
  src : Bytes,
  br_start : Int,
  br_byte : Ref[Int],
  br_bit : Ref[Int],
  table_log : Int,
) -> Int raise ZstdError {
  read_reverse_bits(src, br_start, br_byte, br_bit, table_log).reinterpret_as_int()
}

///|
fn update_fse_state_reverse(
  src : Bytes,
  br_start : Int,
  br_byte : Ref[Int],
  br_bit : Ref[Int],
  next_state : Int,
  nb_bits : Int,
) -> Int raise ZstdError {
  next_state +
  read_reverse_bits(src, br_start, br_byte, br_bit, nb_bits).reinterpret_as_int()
}

///|
fn offset_base_from_code(code : UInt) -> Int raise ZstdError {
  if code == 0 {
    0
  } else if code == 1 {
    1
  } else if code <= 31 {
    (((1 : UInt64) << code.reinterpret_as_int()) - (3 : UInt64)).to_int()
  } else {
    raise CorruptionDetected
  }
}

///|
fn parse_sequence_count(
  src : Bytes,
  seq_start : Int,
  block_end : Int,
) -> (UInt, Int) raise ZstdError {
  if seq_start >= block_end {
    raise CorruptionDetected
  }
  let byte0 = src[seq_start].to_uint()
  let mut seq_pos = seq_start + 1
  let count : UInt = if byte0 < 128 {
    byte0
  } else if byte0 < 255 {
    ensure_range(src.length(), seq_pos, 1)
    let byte1 = src[seq_pos].to_uint()
    seq_pos = seq_pos + 1
    ((byte0 - 0x80) << 8) + byte1
  } else {
    ensure_range(src.length(), seq_pos, 2)
    let byte1 = src[seq_pos].to_uint()
    let byte2 = src[seq_pos + 1].to_uint()
    seq_pos = seq_pos + 2
    byte1 + (byte2 << 8) + 0x7F00
  }
  (count, seq_pos)
}
