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
fn assert_upstream_large_vector(
  name : String,
  frame : Bytes,
  expected_len : Int,
  prefix64 : Bytes,
  suffix64 : Bytes,
) -> Unit raise Error {
  let result = try? decompress(frame)
  match result {
    Ok(out) => {
      assert_eq(out.length(), expected_len)
      assert_eq(out[:64].to_owned(), prefix64)
      assert_eq(out[out.length() - 64:].to_owned(), suffix64)
    }
    Err(SrcSizeTooLarge(_)) =>
      fail("upstream large vector " + name + " decode failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) =>
      fail("upstream large vector " + name + " decode failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail(
        "upstream large vector " + name + " decode failed: CorruptionDetected",
      )
    Err(BoundOverflow) =>
      fail("upstream large vector " + name + " decode failed: BoundOverflow")
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "upstream large vector " +
        name +
        " decode failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail(
        "upstream large vector " +
        name +
        " decode failed: UnsupportedFeature " +
        msg,
      )
  }
}

///|
test "upstream golden-compression PR-3517-block-splitter-corruption-test" {
  assert_upstream_large_vector(
    "pr3517-l19",
    rv_up_pr3517_frame_l19(),
    rv_up_pr3517_len(),
    rv_up_pr3517_prefix_64(),
    rv_up_pr3517_suffix_64(),
  )
}

///|
test "upstream golden-compression large-literal-and-match-lengths" {
  assert_upstream_large_vector(
    "llml-l19-nocheck",
    rv_up_llml_frame_nocheck_l19(),
    rv_up_llml_len(),
    rv_up_llml_prefix_64(),
    rv_up_llml_suffix_64(),
  )
}
