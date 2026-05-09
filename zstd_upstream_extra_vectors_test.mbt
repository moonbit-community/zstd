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
fn assert_upstream_extra_vector(
  name : String,
  frame : Bytes,
  expected : Bytes,
) -> Unit raise Error {
  let result = try? decompress(frame)
  match result {
    Ok(out) => assert_eq(out, expected)
    Err(SrcSizeTooLarge(_)) =>
      fail("upstream extra vector " + name + " decode failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) =>
      fail("upstream extra vector " + name + " decode failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail(
        "upstream extra vector " + name + " decode failed: CorruptionDetected",
      )
    Err(BoundOverflow) =>
      fail("upstream extra vector " + name + " decode failed: BoundOverflow")
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "upstream extra vector " +
        name +
        " decode failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail(
        "upstream extra vector " +
        name +
        " decode failed: UnsupportedFeature " +
        msg,
      )
  }
}

///|
fn assert_upstream_extra_dict_vector(
  name : String,
  frame : Bytes,
) -> Unit raise Error {
  let result = try? decompress_with_dictionary(frame, rv_up_gdict_http_dict())
  match result {
    Ok(out) => assert_eq(out, rv_up_extra_http_x420_payload())
    Err(SrcSizeTooLarge(_)) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: SrcSizeTooLarge",
      )
    Err(SrcSizeWrong) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: SrcSizeWrong",
      )
    Err(CorruptionDetected) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: CorruptionDetected",
      )
    Err(BoundOverflow) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: BoundOverflow",
      )
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: UnsupportedFeature " +
        msg,
      )
  }
}

///|
fn assert_upstream_extra_dict_large_repeat_vector(
  name : String,
  frame : Bytes,
  repeat_count : Int,
) -> Unit raise Error {
  let unit = rv_up_http_payload()
  let result = try? decompress_with_dictionary(frame, rv_up_gdict_http_dict())
  match result {
    Ok(out) => {
      assert_eq(out.length(), unit.length() * repeat_count)
      assert_eq(out[:64].to_owned(), unit[:64].to_owned())
      assert_eq(
        out[out.length() - 64:].to_owned(),
        unit[unit.length() - 64:].to_owned(),
      )
    }
    Err(SrcSizeTooLarge(_)) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: SrcSizeTooLarge",
      )
    Err(SrcSizeWrong) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: SrcSizeWrong",
      )
    Err(CorruptionDetected) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: CorruptionDetected",
      )
    Err(BoundOverflow) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: BoundOverflow",
      )
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail(
        "upstream extra dictionary vector " +
        name +
        " decode failed: UnsupportedFeature " +
        msg,
      )
  }
}

///|
test "upstream extra huffman payload frame level19 no-check" {
  assert_upstream_extra_vector(
    "huffman-l19-nocheck",
    rv_up_extra_huffman_frame_l19_nocheck(),
    rv_up_extra_huffman_payload(),
  )
}

///|
test "upstream extra dictionary x420 http level19" {
  assert_upstream_extra_dict_vector(
    "http-x420-dict-l19",
    rv_up_extra_http_x420_dict_frame_l19(),
  )
}

///|
test "upstream extra dictionary x420 http level19 no-check" {
  assert_upstream_extra_dict_vector(
    "http-x420-dict-l19-nocheck",
    rv_up_extra_http_x420_dict_frame_l19_nocheck(),
  )
}

///|
test "upstream extra dictionary x420 http level19 target-1k-block" {
  assert_upstream_extra_dict_vector(
    "http-x420-dict-l19-target1k",
    rv_up_extra_http_x420_dict_frame_l19_t1k(),
  )
}

///|
test "upstream extra dictionary x5000 http level19 long27" {
  assert_upstream_extra_dict_large_repeat_vector(
    "http-x5000-dict-l19-long27",
    rv_up_extra_http_x5000_dict_frame_l19_long27(),
    5000,
  )
}

///|
test "upstream extra dictionary x5000 http level19 long27 no-check" {
  assert_upstream_extra_dict_large_repeat_vector(
    "http-x5000-dict-l19-long27-nocheck",
    rv_up_extra_http_x5000_dict_frame_l19_long27_nocheck(),
    5000,
  )
}
