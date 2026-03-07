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
fn read_u32_le(src : Bytes, offset : Int) -> UInt raise ZstdError {
  ensure_range(src.length(), offset, 4)
  src[offset].to_uint() +
  (src[offset + 1].to_uint() << 8) +
  (src[offset + 2].to_uint() << 16) +
  (src[offset + 3].to_uint() << 24)
}

///|
fn read_u64_le(src : Bytes, offset : Int) -> UInt64 raise ZstdError {
  ensure_range(src.length(), offset, 8)
  src[offset].to_uint().to_uint64() +
  (src[offset + 1].to_uint().to_uint64() << 8) +
  (src[offset + 2].to_uint().to_uint64() << 16) +
  (src[offset + 3].to_uint().to_uint64() << 24) +
  (src[offset + 4].to_uint().to_uint64() << 32) +
  (src[offset + 5].to_uint().to_uint64() << 40) +
  (src[offset + 6].to_uint().to_uint64() << 48) +
  (src[offset + 7].to_uint().to_uint64() << 56)
}

///|
fn ensure_range(total : Int, offset : Int, size : Int) -> Unit raise ZstdError {
  if offset < 0 || size < 0 || offset > total || size > total - offset {
    raise SrcSizeWrong
  }
}

///|
fn min_u64(a : UInt64, b : UInt64) -> UInt64 {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn append_bytes(out : Array[Byte], src : Bytes, start : Int, len : Int) -> Unit {
  if len <= 0 {
    return
  }
  let mut i = 0
  while i < len {
    out.push(src[start + i])
    i = i + 1
  }
}

///|
fn append_u24_le(out : Array[Byte], value : UInt) -> Unit {
  out.push((value & 0xFF).to_byte())
  out.push(((value >> 8) & 0xFF).to_byte())
  out.push(((value >> 16) & 0xFF).to_byte())
}

///|
fn append_u32_le(out : Array[Byte], value : UInt) -> Unit {
  out.push((value & 0xFF).to_byte())
  out.push(((value >> 8) & 0xFF).to_byte())
  out.push(((value >> 16) & 0xFF).to_byte())
  out.push(((value >> 24) & 0xFF).to_byte())
}
