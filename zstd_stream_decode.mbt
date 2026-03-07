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
pub struct Decompressor {
  mut input_buffer : Array[Byte]
  dictionary : Bytes
}

///|
pub fn new_decompressor() -> Decompressor {
  { input_buffer: Array::new(), dictionary: b"" }
}

///|
pub fn new_decompressor_with_dictionary(dictionary : Bytes) -> Decompressor {
  { input_buffer: Array::new(), dictionary }
}

///|
pub fn Decompressor::push(self : Decompressor, chunk : Bytes) -> Unit {
  append_bytes(self.input_buffer, chunk, 0, chunk.length())
}

///|
pub fn Decompressor::pending_input(self : Decompressor) -> Int {
  self.input_buffer.length()
}

///|
pub fn Decompressor::pull(self : Decompressor) -> Bytes raise ZstdError {
  self.drain_complete_frames(false)
}

///|
pub fn Decompressor::finish(self : Decompressor) -> Bytes raise ZstdError {
  self.drain_complete_frames(true)
}

///|
fn Decompressor::drain_complete_frames(
  self : Decompressor,
  require_complete : Bool,
) -> Bytes raise ZstdError {
  if self.input_buffer.length() == 0 {
    return b""
  }

  let src = Bytes::from_array(self.input_buffer)
  let src_len = src.length()
  let out : Array[Byte] = Array::new()
  let mut pos = 0

  while pos < src_len {
    let result = try? decode_frame_into_with_dictionary(
      src,
      pos,
      out,
      self.dictionary,
    )
    match result {
      Ok(next) => {
        if next <= pos {
          raise CorruptionDetected
        }
        pos = next
      }
      Err(SrcSizeWrong) => {
        if require_complete {
          raise SrcSizeWrong
        }
        break
      }
      Err(CorruptionDetected) => raise CorruptionDetected
      Err(BoundOverflow) => raise BoundOverflow
      Err(SrcSizeTooLarge(size)) => raise SrcSizeTooLarge(size)
      Err(DictionaryRequired(dict_id)) => raise DictionaryRequired(dict_id)
      Err(UnsupportedFeature(msg)) => raise UnsupportedFeature(msg)
    }
  }

  if pos > 0 {
    let next_buffer : Array[Byte] = Array::new()
    append_bytes(next_buffer, src, pos, src_len - pos)
    self.input_buffer = next_buffer
  } else if require_complete && src_len > 0 {
    raise SrcSizeWrong
  }

  Bytes::from_array(out)
}
