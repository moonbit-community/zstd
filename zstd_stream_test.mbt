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
test "stream decompressor emits when frame becomes complete" {
  let input = b"streaming payload"
  let frame = compress(input)
  let dec = new_decompressor()

  dec.push(frame[:5].to_owned())
  assert_eq(dec.pull(), b"")
  assert_true(dec.pending_input() > 0)

  dec.push(frame[5:].to_owned())
  assert_eq(dec.pull(), input)
  assert_eq(dec.pending_input(), 0)
  assert_eq(dec.finish(), b"")
}

///|
test "stream decompressor handles concatenated frames across chunk boundaries" {
  let frame1 = compress(b"abc")
  let frame2 = compress(b"xyz")
  let dec = new_decompressor()

  dec.push(frame1 + frame2[:3].to_owned())
  assert_eq(dec.pull(), b"abc")
  assert_true(dec.pending_input() > 0)

  dec.push(frame2[3:].to_owned())
  assert_eq(dec.pull(), b"xyz")
  assert_eq(dec.pending_input(), 0)
}

///|
test "stream decompressor handles skippable frame before zstd frame" {
  let skippable = b"\x50\x2A\x4D\x18\x04\x00\x00\x00test"
  let frame = compress(b"moon")
  let dec = new_decompressor()
  dec.push(skippable + frame)
  assert_eq(dec.pull(), b"moon")
  assert_eq(dec.pending_input(), 0)
}

///|
test "stream decompressor finish rejects incomplete tail" {
  let frame = compress(b"abc")
  let dec = new_decompressor()
  dec.push(frame[:frame.length() - 1].to_owned())
  let result = try? dec.finish()
  assert_true(result is Err(SrcSizeWrong))
}

///|
test "stream decompressor supports dictionary-backed history" {
  let frame = b"\x28\xb5\x2f\xfd\x20\x03\x3d\x00\x00\x00\x01\x54\x00\x04\x00\x13"
  let dict = b"0123456789abcdef"
  let dec = new_decompressor_with_dictionary(dict)
  dec.push(frame[:7].to_owned())
  assert_eq(dec.pull(), b"")
  dec.push(frame[7:].to_owned())
  assert_eq(dec.pull(), b"012")
}

///|
test "stream decompressor supports standard zstd dictionary blob" {
  let frame = standard_dictionary_fixture_frame()
  let dict = standard_dictionary_fixture_dictionary()
  let expected = standard_dictionary_fixture_payload()
  let dec = new_decompressor_with_dictionary(dict)

  dec.push(frame[:7].to_owned())
  assert_eq(dec.pull(), b"")
  dec.push(frame[7:15].to_owned())
  assert_eq(dec.pull(), b"")
  dec.push(frame[15:].to_owned())
  assert_eq(dec.pull(), expected)
  assert_eq(dec.pending_input(), 0)
}
