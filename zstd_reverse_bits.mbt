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
fn init_reverse_bit_reader(
  src : Bytes,
  start : Int,
  byte_ref : Ref[Int],
  bit_ref : Ref[Int],
) -> Unit raise ZstdError {
  if byte_ref.val < start {
    raise CorruptionDetected
  }
  let last = src[byte_ref.val].to_uint()
  if last == 0 {
    raise CorruptionDetected
  }
  bit_ref.val = highest_bit_index(last) - 1
  if bit_ref.val < 0 {
    byte_ref.val = byte_ref.val - 1
    bit_ref.val = 7
  }
}

///|
fn read_reverse_bits(
  src : Bytes,
  start : Int,
  byte_ref : Ref[Int],
  bit_ref : Ref[Int],
  count : Int,
) -> UInt raise ZstdError {
  let mut value : UInt = 0
  let mut i = 0
  while i < count {
    let bit = read_reverse_bit(src, start, byte_ref, bit_ref)
    value = (value << 1) + bit
    i = i + 1
  }
  value
}

///|
fn read_reverse_bit(
  src : Bytes,
  start : Int,
  byte_ref : Ref[Int],
  bit_ref : Ref[Int],
) -> UInt raise ZstdError {
  if byte_ref.val < start {
    raise CorruptionDetected
  }
  if bit_ref.val < 0 {
    byte_ref.val = byte_ref.val - 1
    bit_ref.val = 7
    if byte_ref.val < start {
      raise CorruptionDetected
    }
  }
  let bit = (src[byte_ref.val].to_uint() >> bit_ref.val) & 1
  bit_ref.val = bit_ref.val - 1
  bit
}

///|
fn reverse_bits_consumed(
  start : Int,
  byte_ref : Ref[Int],
  bit_ref : Ref[Int],
) -> Bool {
  byte_ref.val < start || (byte_ref.val == start && bit_ref.val < 0)
}

///|
fn highest_bit_index(value : UInt) -> Int raise ZstdError {
  if value == 0 {
    raise CorruptionDetected
  }
  let mut idx = 7
  while idx >= 0 {
    if ((value >> idx) & 1) == 1 {
      return idx
    }
    idx = idx - 1
  }
  raise CorruptionDetected
}
