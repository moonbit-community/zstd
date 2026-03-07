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
pub struct Compressor {
  mut input_buffer : Array[Byte]
  options : CompressOptions
  dictionary : Bytes
}

///|
pub fn new_compressor(level? : Int = 3) -> Compressor {
  new_compressor_with_options(default_compress_options(level~))
}

///|
pub fn new_compressor_with_dictionary(
  dictionary : Bytes,
  level? : Int = 3,
) -> Compressor {
  new_compressor_with_dictionary_and_options(
    dictionary,
    default_compress_options(level~),
  )
}

///|
pub fn new_compressor_with_options(options : CompressOptions) -> Compressor {
  {
    input_buffer: Array::new(),
    options: normalize_compress_options(options),
    dictionary: b"",
  }
}

///|
pub fn new_compressor_with_dictionary_and_options(
  dictionary : Bytes,
  options : CompressOptions,
) -> Compressor {
  {
    input_buffer: Array::new(),
    options: normalize_compress_options(options),
    dictionary,
  }
}

///|
pub fn Compressor::push(self : Compressor, chunk : Bytes) -> Unit {
  append_bytes(self.input_buffer, chunk, 0, chunk.length())
}

///|
pub fn Compressor::pending_input(self : Compressor) -> Int {
  self.input_buffer.length()
}

///|
pub fn Compressor::pull(self : Compressor) -> Bytes raise ZstdError {
  if self.input_buffer.length() == 0 {
    return b""
  }
  let src = Bytes::from_array(self.input_buffer)
  self.input_buffer = Array::new()
  compress_with_dictionary_and_options(src, self.dictionary, self.options)
}

///|
pub fn Compressor::finish(self : Compressor) -> Bytes raise ZstdError {
  self.pull()
}
