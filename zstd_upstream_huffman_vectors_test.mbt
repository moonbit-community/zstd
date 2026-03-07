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
fn rv_up_huffman_larger_prefix_64() -> Bytes {
  b"\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x60\x7e\x21\x40\x23\x24\x25\x5e\x26\x2a\x28\x29\x5f\x2b"
}

///|
fn rv_up_huffman_larger_suffix_64() -> Bytes {
  b"\x51\x57\x45\x52\x54\x59\x55\x49\x4f\x50\x7b\x7d\x7c\x61\x73\x64\x66\x67\x68\x6a\x6b\x6c\x3b\x27\x41\x53\x44\x46\x47\x48\x4a\x4b\x4c\x3a\x22\x7a\x78\x63\x76\x62\x6e\x6d\x2c\x2e\x2f\x5a\x58\x43\x56\x42\x4e\x4d\x3c\x3e\x3f\x30\x61\x30\x62\x30\x63\x30\x64\x0a"
}

///|
test "upstream golden-compression huffman-compressed-larger direct frame decode" {
  let frame = rv_up_extra_huffman_payload()
  let result = try? decompress(frame)
  match result {
    Ok(out) => {
      assert_eq(out.length(), 142)
      assert_eq(out[:64].to_bytes(), rv_up_huffman_larger_prefix_64())
      assert_eq(
        out[out.length() - 64:].to_bytes(),
        rv_up_huffman_larger_suffix_64(),
      )
    }
    Err(SrcSizeTooLarge(_)) =>
      fail("huffman-compressed-larger direct decode failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) =>
      fail("huffman-compressed-larger direct decode failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail("huffman-compressed-larger direct decode failed: CorruptionDetected")
    Err(BoundOverflow) =>
      fail("huffman-compressed-larger direct decode failed: BoundOverflow")
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "huffman-compressed-larger direct decode failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail(
        "huffman-compressed-larger direct decode failed: UnsupportedFeature " +
        msg,
      )
  }
}

///|
test "upstream golden-compression huffman-compressed-larger bound" {
  let frame = rv_up_extra_huffman_payload()
  let b = try? decompress_bound(frame)
  match b {
    Ok(v) => assert_eq(v, 128 << 10)
    Err(SrcSizeTooLarge(_)) =>
      fail("huffman-compressed-larger bound failed: SrcSizeTooLarge")
    Err(SrcSizeWrong) =>
      fail("huffman-compressed-larger bound failed: SrcSizeWrong")
    Err(CorruptionDetected) =>
      fail("huffman-compressed-larger bound failed: CorruptionDetected")
    Err(BoundOverflow) =>
      fail("huffman-compressed-larger bound failed: BoundOverflow")
    Err(DictionaryRequired(dict_id)) =>
      fail(
        "huffman-compressed-larger bound failed: DictionaryRequired " +
        dict_id.to_string(),
      )
    Err(UnsupportedFeature(msg)) =>
      fail("huffman-compressed-larger bound failed: UnsupportedFeature " + msg)
  }
}
