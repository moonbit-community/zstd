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
test "upstream golden dictionary missing-symbols http default level" {
  assert_upstream_gdict_http_vector(
    "http-dict-missing-symbols-default",
    rv_up_gdict_missing_symbols_http_frame_default(),
  )
}

///|
test "upstream golden dictionary missing-symbols http default level no-check" {
  assert_upstream_gdict_http_vector(
    "http-dict-missing-symbols-default-nocheck",
    rv_up_gdict_missing_symbols_http_frame_default_nocheck(),
  )
}

///|
fn assert_missing_symbols_vector_requires_dictionary(
  frame : Bytes,
) -> Unit raise Error {
  let without_dict = try? decompress(frame)
  assert_true(without_dict is Err(DictionaryRequired(_)))

  let wrong_dict = standard_dictionary_fixture_dictionary()
  let with_wrong_dict = try? decompress_with_dictionary(frame, wrong_dict)
  assert_true(with_wrong_dict is Err(DictionaryRequired(_)))
}

///|
test "upstream missing-symbols vector rejects absent and wrong dictionary" {
  assert_missing_symbols_vector_requires_dictionary(
    rv_up_gdict_missing_symbols_http_frame_default(),
  )
}

///|
test "upstream missing-symbols no-check vector rejects absent and wrong dictionary" {
  assert_missing_symbols_vector_requires_dictionary(
    rv_up_gdict_missing_symbols_http_frame_default_nocheck(),
  )
}
