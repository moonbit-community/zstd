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
test "upstream missing-symbol dictionary encode byte parity default checksum" {
  let frame = compress_with_dictionary_and_options(
    rv_up_http_payload(),
    rv_up_gdict_http_dict(),
    default_compress_options(level=3).with_checksum(true),
  )
  assert_eq(frame, rv_up_gdict_missing_symbols_http_frame_default())
}

///|
test "upstream missing-symbol dictionary encode byte parity default no-check" {
  let frame = compress_with_dictionary_and_options(
    rv_up_http_payload(),
    rv_up_gdict_http_dict(),
    default_compress_options(level=3).with_checksum(false),
  )
  assert_eq(frame, rv_up_gdict_missing_symbols_http_frame_default_nocheck())
}
