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
fn append_literals_header(
  out : Array[Byte],
  lit_len : Int,
  literals_block_type : UInt,
) -> Unit raise ZstdError {
  if literals_block_type != 0 && literals_block_type != 1 {
    raise CorruptionDetected
  }
  if lit_len < 0 || lit_len > 131072 {
    raise CorruptionDetected
  }
  if lit_len <= 31 {
    out.push(
      ((lit_len.reinterpret_as_uint() << 3) + literals_block_type).to_byte(),
    )
  } else if lit_len <= 4095 {
    out.push(
      (((lit_len & 0xF).reinterpret_as_uint() << 4) + 0x04 + literals_block_type).to_byte(),
    )
    out.push(((lit_len >> 4).reinterpret_as_uint() & 0xFF).to_byte())
  } else {
    out.push(
      (((lit_len & 0xF).reinterpret_as_uint() << 4) + 0x0C + literals_block_type).to_byte(),
    )
    out.push(((lit_len >> 4).reinterpret_as_uint() & 0xFF).to_byte())
    out.push(((lit_len >> 12).reinterpret_as_uint() & 0xFF).to_byte())
  }
}

///|
fn append_raw_literals_section_bytes(literals : Bytes) -> Bytes raise ZstdError {
  let out : Array[Byte] = Array::new()
  let lit_len = literals.length()
  append_literals_header(out, lit_len, 0)
  append_bytes(out, literals, 0, lit_len)
  Bytes::from_array(out)
}

///|
fn append_rle_literals_section_bytes(literals : Bytes) -> Bytes raise ZstdError {
  let out : Array[Byte] = Array::new()
  let lit_len = literals.length()
  if lit_len <= 0 {
    raise CorruptionDetected
  }
  append_literals_header(out, lit_len, 1)
  out.push(literals[0])
  Bytes::from_array(out)
}

///|
fn is_single_value_literals(literals : Bytes) -> Bool {
  let lit_len = literals.length()
  if lit_len <= 1 {
    return false
  }
  let first = literals[0]
  let mut i = 1
  while i < lit_len {
    if literals[i] != first {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn append_best_literals_section(
  out : Array[Byte],
  literals : Bytes,
) -> Unit raise ZstdError {
  let mut best = append_raw_literals_section_bytes(literals)
  if is_single_value_literals(literals) {
    let rle = append_rle_literals_section_bytes(literals)
    if rle.length() < best.length() {
      best = rle
    }
  }
  let compressed = try? try_build_compressed_literals_section(literals)
  match compressed {
    Ok(candidate) =>
      if candidate.length() > 0 && candidate.length() < best.length() {
        best = candidate
      }
    Err(_) => ()
  }
  append_bytes(out, best, 0, best.length())
}
