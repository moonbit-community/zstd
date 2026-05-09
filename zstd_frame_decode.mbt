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
fn decode_frame_into(
  src : Bytes,
  start : Int,
  out : Array[Byte],
) -> Int raise ZstdError {
  decode_frame_into_with_history(src, start, out, b"")
}

///|
fn decode_frame_into_with_history(
  src : Bytes,
  start : Int,
  out : Array[Byte],
  history : Bytes,
) -> Int raise ZstdError {
  decode_frame_into_with_dictionary_state(
    src,
    start,
    out,
    raw_dictionary_state(history),
  )
}

///|
fn decode_frame_into_with_dictionary(
  src : Bytes,
  start : Int,
  out : Array[Byte],
  dictionary : Bytes,
) -> Int raise ZstdError {
  decode_frame_into_with_dictionary_state(
    src,
    start,
    out,
    parse_dictionary_state(dictionary),
  )
}

///|
fn decode_frame_into_with_dictionary_state(
  src : Bytes,
  start : Int,
  out : Array[Byte],
  dictionary_state : DictionaryState,
) -> Int raise ZstdError {
  let src_len = src.length()
  ensure_range(src_len, start, 4)
  let magic = read_u32_le(src, start)

  if (magic & skippable_magic_mask) == skippable_magic_start {
    ensure_range(src_len, start, 8)
    let user_size = read_u32_le(src, start + 4).to_uint64()
    let frame_size = user_size + (8 : UInt64)
    let remaining = (src_len - start).to_uint64()
    if frame_size > remaining {
      raise SrcSizeWrong
    }
    return start + frame_size.to_int()
  }

  if magic != zstd_magic_number {
    raise CorruptionDetected
  }

  ensure_range(src_len, start, 5)
  let descriptor = src[start + 4].to_uint()
  if ((descriptor >> 3) & 1) == 1 {
    raise CorruptionDetected
  }

  let frame_content_size_flag = descriptor >> 6
  let single_segment = ((descriptor >> 5) & 1) == 1
  let checksum_flag = ((descriptor >> 2) & 1) == 1
  let dict_id_flag = descriptor & 0x3

  let mut pos = start + 5
  let mut frame_window_size = 0
  if !single_segment {
    ensure_range(src_len, pos, 1)
    let window_size_u = window_size_from_descriptor(src[pos].to_uint())
    if window_size_u == 0 || window_size_u > (1 : UInt64) << 62 {
      raise CorruptionDetected
    }
    frame_window_size = window_size_u.to_int()
    pos = pos + 1
  }

  let dict_size = dict_id_size(dict_id_flag)
  ensure_range(src_len, pos, dict_size)
  let frame_dict_id = if dict_size == 0 {
    (0 : UInt)
  } else if dict_size == 1 {
    src[pos].to_uint()
  } else if dict_size == 2 {
    src[pos].to_uint() + (src[pos + 1].to_uint() << 8)
  } else if dict_size == 4 {
    read_u32_le(src, pos)
  } else {
    raise CorruptionDetected
  }
  pos = pos + dict_size
  if dict_size > 0 {
    if !dictionary_state.has_dictionary {
      raise DictionaryRequired(frame_dict_id)
    }
    if dictionary_state.dict_id != 0 &&
      dictionary_state.dict_id != frame_dict_id {
      raise DictionaryRequired(frame_dict_id)
    }
  }

  let fcs_size = frame_content_size_size(
    frame_content_size_flag, single_segment,
  )
  ensure_range(src_len, pos, fcs_size)
  let mut has_content_size = false
  let mut content_size : UInt64 = 0
  match fcs_size {
    0 => ()
    1 => {
      has_content_size = true
      content_size = src[pos].to_uint().to_uint64()
    }
    2 => {
      has_content_size = true
      content_size = src[pos].to_uint().to_uint64() +
        (src[pos + 1].to_uint().to_uint64() << 8) +
        (256 : UInt64)
    }
    4 => {
      has_content_size = true
      content_size = read_u32_le(src, pos).to_uint64()
    }
    8 => {
      has_content_size = true
      content_size = read_u64_le(src, pos)
    }
    _ => raise CorruptionDetected
  }
  pos = pos + fcs_size

  let mut decoded_size : UInt64 = 0
  let mut last_block = false
  let mut rep1 = dictionary_state.rep1
  let mut rep2 = dictionary_state.rep2
  let mut rep3 = dictionary_state.rep3
  let frame_out_start = out.length()
  let prev_huf_valid : Ref[Bool] = { val: dictionary_state.huf_valid }
  let prev_huf_max_bits : Ref[Int] = { val: dictionary_state.huf_max_bits }
  let prev_huf_left : Ref[Array[Int]] = { val: dictionary_state.huf_left }
  let prev_huf_right : Ref[Array[Int]] = { val: dictionary_state.huf_right }
  let prev_huf_symbol : Ref[Array[Int]] = { val: dictionary_state.huf_symbol }
  let prev_ll_valid : Ref[Bool] = { val: dictionary_state.ll_valid }
  let prev_ll_kind : Ref[Int] = { val: dictionary_state.ll_kind }
  let prev_off_valid : Ref[Bool] = { val: dictionary_state.off_valid }
  let prev_off_kind : Ref[Int] = { val: dictionary_state.off_kind }
  let prev_ml_valid : Ref[Bool] = { val: dictionary_state.ml_valid }
  let prev_ml_kind : Ref[Int] = { val: dictionary_state.ml_kind }
  let prev_ll_code : Ref[UInt] = { val: dictionary_state.ll_code }
  let prev_off_code : Ref[UInt] = { val: dictionary_state.off_code }
  let prev_ml_code : Ref[UInt] = { val: dictionary_state.ml_code }
  let prev_ll_table_log : Ref[Int] = { val: dictionary_state.ll_table_log }
  let prev_off_table_log : Ref[Int] = { val: dictionary_state.off_table_log }
  let prev_ml_table_log : Ref[Int] = { val: dictionary_state.ml_table_log }
  let prev_ll_table_next_state : Ref[Array[Int]] = {
    val: dictionary_state.ll_table_next_state,
  }
  let prev_ll_table_nb_add_bits : Ref[Array[Int]] = {
    val: dictionary_state.ll_table_nb_add_bits,
  }
  let prev_ll_table_nb_bits : Ref[Array[Int]] = {
    val: dictionary_state.ll_table_nb_bits,
  }
  let prev_ll_table_base_values : Ref[Array[Int]] = {
    val: dictionary_state.ll_table_base_values,
  }
  let prev_off_table_next_state : Ref[Array[Int]] = {
    val: dictionary_state.off_table_next_state,
  }
  let prev_off_table_nb_add_bits : Ref[Array[Int]] = {
    val: dictionary_state.off_table_nb_add_bits,
  }
  let prev_off_table_nb_bits : Ref[Array[Int]] = {
    val: dictionary_state.off_table_nb_bits,
  }
  let prev_off_table_base_values : Ref[Array[Int]] = {
    val: dictionary_state.off_table_base_values,
  }
  let prev_ml_table_next_state : Ref[Array[Int]] = {
    val: dictionary_state.ml_table_next_state,
  }
  let prev_ml_table_nb_add_bits : Ref[Array[Int]] = {
    val: dictionary_state.ml_table_nb_add_bits,
  }
  let prev_ml_table_nb_bits : Ref[Array[Int]] = {
    val: dictionary_state.ml_table_nb_bits,
  }
  let prev_ml_table_base_values : Ref[Array[Int]] = {
    val: dictionary_state.ml_table_base_values,
  }
  while !last_block {
    ensure_range(src_len, pos, 3)
    let block_header : UInt = src[pos].to_uint() +
      (src[pos + 1].to_uint() << 8) +
      (src[pos + 2].to_uint() << 16)
    pos = pos + 3

    last_block = (block_header & 1) == 1
    let block_type = (block_header >> 1) & 0x3
    let block_size_u = (block_header >> 3).to_uint64()
    if block_size_u > zstd_block_size_max {
      raise CorruptionDetected
    }
    let block_size = block_size_u.to_int()

    match block_type {
      0 => {
        ensure_range(src_len, pos, block_size)
        let mut i = 0
        while i < block_size {
          out.push(src[pos + i])
          i = i + 1
        }
        pos = pos + block_size
        decoded_size = decoded_size + block_size_u
      }
      1 => {
        ensure_range(src_len, pos, 1)
        let value = src[pos]
        pos = pos + 1
        let mut i = 0
        while i < block_size {
          out.push(value)
          i = i + 1
        }
        decoded_size = decoded_size + block_size_u
      }
      2 => {
        let (next_pos, produced, next_rep1, next_rep2, next_rep3) = decode_compressed_block_minimal(
          src,
          pos,
          block_size,
          out,
          frame_out_start,
          dictionary_state.history,
          rep1,
          rep2,
          rep3,
          prev_huf_valid,
          prev_huf_max_bits,
          prev_huf_left,
          prev_huf_right,
          prev_huf_symbol,
          prev_ll_valid,
          prev_ll_kind,
          prev_ll_code,
          prev_ll_table_log,
          prev_ll_table_next_state,
          prev_ll_table_nb_add_bits,
          prev_ll_table_nb_bits,
          prev_ll_table_base_values,
          prev_off_valid,
          prev_off_kind,
          prev_off_code,
          prev_off_table_log,
          prev_off_table_next_state,
          prev_off_table_nb_add_bits,
          prev_off_table_nb_bits,
          prev_off_table_base_values,
          prev_ml_valid,
          prev_ml_kind,
          prev_ml_code,
          prev_ml_table_log,
          prev_ml_table_next_state,
          prev_ml_table_nb_add_bits,
          prev_ml_table_nb_bits,
          prev_ml_table_base_values,
          window_size=frame_window_size,
        )
        pos = next_pos
        decoded_size = decoded_size + produced
        rep1 = next_rep1
        rep2 = next_rep2
        rep3 = next_rep3
      }
      _ => raise CorruptionDetected
    }
  }

  if checksum_flag {
    ensure_range(src_len, pos, 4)
    let expected_checksum = read_u32_le(src, pos)
    let frame_bytes = Bytes::from_array(out)[frame_out_start:].to_owned()
    let actual_checksum = (xxh64(frame_bytes) & (0xFFFF_FFFF : UInt64)).to_uint()
    if actual_checksum != expected_checksum {
      raise CorruptionDetected
    }
    pos = pos + 4
  }
  if has_content_size && decoded_size != content_size {
    raise CorruptionDetected
  }
  pos
}
