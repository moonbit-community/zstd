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
test "stream parity: dictionary-required error is surfaced from pull" {
  let dec = new_decompressor()
  dec.push(standard_dictionary_fixture_frame())
  let result = try? dec.pull()
  assert_true(result is Err(DictionaryRequired(_)))
  assert_true(dec.pending_input() > 0)
}

///|
test "stream parity: pull returns complete prefix frame with incomplete tail buffered" {
  let frame1 = compress(b"first")
  let frame2 = compress(b"second")
  let dec = new_decompressor()
  dec.push(frame1 + frame2[:frame2.length() - 2].to_bytes())
  let out = dec.pull()
  assert_eq(out, b"first")
  assert_true(dec.pending_input() > 0)
  let finish_result = try? dec.finish()
  assert_true(finish_result is Err(SrcSizeWrong))
}

///|
test "stream parity: dictionary decoder handles concatenated dictionary frames" {
  let frame = standard_dictionary_fixture_frame()
  let dict = standard_dictionary_fixture_dictionary()
  let dec = new_decompressor_with_dictionary(dict)
  dec.push(frame + frame)
  let out = dec.pull()
  assert_eq(
    out,
    standard_dictionary_fixture_payload() +
    standard_dictionary_fixture_payload(),
  )
  assert_eq(dec.pending_input(), 0)
}

///|
fn decode_stream_chunks(frame : Bytes, chunk_step : Int) -> Bytes raise Error {
  let dec = new_decompressor()
  let mut pos = 0
  while pos < frame.length() {
    let remain = frame.length() - pos
    let size = if remain < chunk_step { remain } else { chunk_step }
    dec.push(frame[pos:pos + size].to_bytes())
    pos = pos + size
  }
  let out = dec.pull()
  let tail = dec.finish()
  assert_eq(dec.pending_input(), 0)
  out + tail
}

///|
fn decode_stream_chunks_with_dictionary(
  frame : Bytes,
  dictionary : Bytes,
  chunk_step : Int,
) -> Bytes raise Error {
  let dec = new_decompressor_with_dictionary(dictionary)
  let mut pos = 0
  while pos < frame.length() {
    let remain = frame.length() - pos
    let size = if remain < chunk_step { remain } else { chunk_step }
    dec.push(frame[pos:pos + size].to_bytes())
    pos = pos + size
  }
  let out = dec.pull()
  let tail = dec.finish()
  assert_eq(dec.pending_input(), 0)
  out + tail
}

///|
test "stream parity: matrix plain long27 frame decodes across small chunks" {
  let frame = rv_up_matrix_http_x420_frame_l9_long27()
  let out = decode_stream_chunks(frame, 9)
  assert_eq(out, rv_up_extra_http_x420_payload())
}

///|
test "stream parity: matrix dictionary long27 frame decodes across small chunks" {
  let frame = rv_up_matrix_http_x420_dict_frame_l9_long27()
  let out = decode_stream_chunks_with_dictionary(
    frame,
    rv_up_gdict_http_dict(),
    11,
  )
  assert_eq(out, rv_up_extra_http_x420_payload())
}

///|
test "stream parity: matrix plain concatenated frames decode in chunked flow" {
  let frame = rv_up_matrix_http_x420_frame_l9() +
    rv_up_matrix_http_x420_frame_l9_nocheck()
  let out = decode_stream_chunks(frame, 13)
  assert_eq(
    out,
    rv_up_extra_http_x420_payload() + rv_up_extra_http_x420_payload(),
  )
}
