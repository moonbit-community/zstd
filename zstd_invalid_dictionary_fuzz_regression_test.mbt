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
fn assert_decode_error(result : Result[Bytes, ZstdError]) -> Unit raise Error {
  assert_true(
    result is Err(CorruptionDetected) ||
    result is Err(SrcSizeWrong) ||
    result is Err(BoundOverflow),
  )
}

///|
test "invalid dictionary: zero rep offsets is rejected" {
  let dict = standard_dictionary_fixture_dictionary()
  let arr = dict.to_array()
  let rep_start = dict.length() - 28
  arr[rep_start] = b'\x00'
  arr[rep_start + 1] = b'\x00'
  arr[rep_start + 2] = b'\x00'
  arr[rep_start + 3] = b'\x00'
  let bad_dict = Bytes::from_array(arr)
  let result = try? decompress_with_dictionary(
    standard_dictionary_fixture_frame(),
    bad_dict,
  )
  assert_true(result is Err(CorruptionDetected))
}

///|
test "invalid dictionary: truncated dict content is rejected" {
  let dict = standard_dictionary_fixture_dictionary()
  let truncated = dict[:dict.length() - 16].to_owned()
  let result = try? decompress_with_dictionary(
    standard_dictionary_fixture_frame(),
    truncated,
  )
  assert_true(result is Err(CorruptionDetected))
}

///|
test "fuzz regression: malformed frame with random descriptor flags errors cleanly" {
  // Well-formed magic, but malformed descriptor / payload layout.
  let frame = b"\x28\xb5\x2f\xfd\xff\xff\xff\xff\xff\x00\x01\x02\x03"
  let result = try? decompress(frame)
  assert_decode_error(result)
}

///|
test "fuzz regression: corrupted compressed block payload errors cleanly" {
  // Derived from a valid subset frame, then flipped one payload byte.
  let frame = b"\x28\xb5\x2f\xfd\x20\x04\x3d\x00\x00\x08\x61\x01\x54\x01\x00\x00"
  let arr = frame.to_array()
  arr[12] = (arr[12].to_uint() ^ 0x7F).to_byte()
  let corrupted = Bytes::from_array(arr)
  let result = try? decompress(corrupted)
  assert_decode_error(result)
}
