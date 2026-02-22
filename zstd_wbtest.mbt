///|
test "compress_bound_macro keeps additive bound property around 128KB threshold" {
  let a : UInt64 = (128 : UInt64) << 10
  let b : UInt64 = (128 : UInt64) << 10
  let lhs = compress_bound_macro(a) + compress_bound_macro(b)
  let rhs = compress_bound_macro(a + b)
  assert_true(lhs <= rhs)
}

///|
test "reverse bitstream init for predefined sequence states" {
  let src = b"\x00\x10\x02"
  let br_byte : Ref[Int] = { val: 2 }
  let br_bit : Ref[Int] = { val: -1 }
  init_reverse_bit_reader(src, 0, br_byte, br_bit)
  let ll_state = init_fse_state_reverse(
    src, 0, br_byte, br_bit, ll_predefined_table_log,
  )
  let of_state = init_fse_state_reverse(
    src, 0, br_byte, br_bit, of_predefined_table_log,
  )
  let ml_state = init_fse_state_reverse(
    src, 0, br_byte, br_bit, ml_predefined_table_log,
  )
  assert_eq(ll_state, 2)
  assert_eq(of_state, 0)
  assert_eq(ml_state, 0)
  assert_true(reverse_bits_consumed(0, br_byte, br_bit))
}

///|
test "internal decode of predefined sequence compressed payload" {
  let src = b"\x08\x61\x01\x00\x00\x10\x02"
  let out : Array[Byte] = Array::new()
  let prev_huf_valid : Ref[Bool] = { val: false }
  let prev_huf_max_bits : Ref[Int] = { val: 0 }
  let prev_huf_left : Ref[Array[Int]] = { val: Array::new() }
  let prev_huf_right : Ref[Array[Int]] = { val: Array::new() }
  let prev_huf_symbol : Ref[Array[Int]] = { val: Array::new() }
  let prev_ll_valid : Ref[Bool] = { val: false }
  let prev_ll_kind : Ref[Int] = { val: 0 }
  let prev_ll_code : Ref[UInt] = { val: 0 }
  let prev_ll_table_log : Ref[Int] = { val: 0 }
  let prev_ll_table_next_state : Ref[Array[Int]] = { val: Array::new() }
  let prev_ll_table_nb_add_bits : Ref[Array[Int]] = { val: Array::new() }
  let prev_ll_table_nb_bits : Ref[Array[Int]] = { val: Array::new() }
  let prev_ll_table_base_values : Ref[Array[Int]] = { val: Array::new() }
  let prev_off_valid : Ref[Bool] = { val: false }
  let prev_off_kind : Ref[Int] = { val: 0 }
  let prev_off_code : Ref[UInt] = { val: 0 }
  let prev_off_table_log : Ref[Int] = { val: 0 }
  let prev_off_table_next_state : Ref[Array[Int]] = { val: Array::new() }
  let prev_off_table_nb_add_bits : Ref[Array[Int]] = { val: Array::new() }
  let prev_off_table_nb_bits : Ref[Array[Int]] = { val: Array::new() }
  let prev_off_table_base_values : Ref[Array[Int]] = { val: Array::new() }
  let prev_ml_valid : Ref[Bool] = { val: false }
  let prev_ml_kind : Ref[Int] = { val: 0 }
  let prev_ml_code : Ref[UInt] = { val: 0 }
  let prev_ml_table_log : Ref[Int] = { val: 0 }
  let prev_ml_table_next_state : Ref[Array[Int]] = { val: Array::new() }
  let prev_ml_table_nb_add_bits : Ref[Array[Int]] = { val: Array::new() }
  let prev_ml_table_nb_bits : Ref[Array[Int]] = { val: Array::new() }
  let prev_ml_table_base_values : Ref[Array[Int]] = { val: Array::new() }
  let result = try? decode_compressed_block_minimal(
    src,
    0,
    src.length(),
    out,
    0,
    b"",
    1,
    4,
    8,
    prev_huf_valid,
    prev_huf_max_bits,
    prev_huf_left,
    prev_huf_right,
    prev_huf_symbol,
    prev_ll_valid,
    prev_ll_kind,
    prev_ll_code,
    prev_ll_table_log,
    prev_ll_table_next_state,
    prev_ll_table_nb_add_bits,
    prev_ll_table_nb_bits,
    prev_ll_table_base_values,
    prev_off_valid,
    prev_off_kind,
    prev_off_code,
    prev_off_table_log,
    prev_off_table_next_state,
    prev_off_table_nb_add_bits,
    prev_off_table_nb_bits,
    prev_off_table_base_values,
    prev_ml_valid,
    prev_ml_kind,
    prev_ml_code,
    prev_ml_table_log,
    prev_ml_table_next_state,
    prev_ml_table_nb_add_bits,
    prev_ml_table_nb_bits,
    prev_ml_table_base_values,
  )
  match result {
    Ok((next_pos, produced, _, _, _)) => {
      assert_eq(next_pos, src.length())
      assert_eq(produced, (4 : UInt64))
      assert_eq(Bytes::from_array(out), b"aaaa")
    }
    Err(CorruptionDetected) => fail("unexpected CorruptionDetected")
    Err(SrcSizeWrong) => fail("unexpected SrcSizeWrong")
    Err(BoundOverflow) => fail("unexpected BoundOverflow")
    Err(SrcSizeTooLarge(_)) => fail("unexpected SrcSizeTooLarge")
    Err(DictionaryRequired(dict_id)) =>
      fail("unexpected DictionaryRequired: " + dict_id.to_string())
    Err(UnsupportedFeature(msg)) =>
      fail("unexpected UnsupportedFeature: " + msg)
  }
}

///|
test "predefined state init with non-zero bitstream start" {
  let src = b"\x08\x61\x01\x00\x00\x10\x02"
  let br_byte : Ref[Int] = { val: src.length() - 1 }
  let br_bit : Ref[Int] = { val: -1 }
  init_reverse_bit_reader(src, 4, br_byte, br_bit)
  let ll_state = init_fse_state_reverse(
    src, 4, br_byte, br_bit, ll_predefined_table_log,
  )
  let of_state = init_fse_state_reverse(
    src, 4, br_byte, br_bit, of_predefined_table_log,
  )
  let ml_state = init_fse_state_reverse(
    src, 4, br_byte, br_bit, ml_predefined_table_log,
  )
  assert_eq(ll_state, 2)
  assert_eq(of_state, 0)
  assert_eq(ml_state, 0)
  assert_true(reverse_bits_consumed(4, br_byte, br_bit))
}

///|
test "rewrite RLE sequence modes to repeat after prior-state warmup" {
  let src = Bytes::makei(512, i => if i % 2 == 0 { b"a"[0] } else { b"b"[0] })
  let payload = try? build_best_periodic_payload(src, 0, src.length(), 18)
  match payload {
    Ok(v) => {
      assert_true(v.length() > 0)
      let prev_rle_valid : Ref[Bool] = { val: false }
      let prev_ll_code : Ref[UInt] = { val: 0 }
      let prev_off_code : Ref[UInt] = { val: 0 }
      let prev_ml_code : Ref[UInt] = { val: 0 }
      let prev_predefined_valid : Ref[Bool] = { val: false }
      let prev_compressed_valid : Ref[Bool] = { val: false }
      let prev_ll_header : Ref[Bytes] = { val: b"" }
      let prev_off_header : Ref[Bytes] = { val: b"" }
      let prev_ml_header : Ref[Bytes] = { val: b"" }

      let first = maybe_rewrite_sequence_modes_to_repeat(
        v, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
        prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
      )
      let first_modes_pos = payload_sequence_modes_offset(first)
      assert_true(first_modes_pos >= 0)
      assert_eq(first[first_modes_pos].to_uint(), 0x54)

      let second = maybe_rewrite_sequence_modes_to_repeat(
        v, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
        prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
      )
      let second_modes_pos = payload_sequence_modes_offset(second)
      assert_true(second_modes_pos >= 0)
      assert_eq(second[second_modes_pos].to_uint(), 0xFC)
      assert_eq(first.length() - second.length(), 3)
    }
    Err(_) =>
      fail("failed to build periodic payload for repeat-mode rewrite test")
  }
}

///|
test "rewrite predefined sequence modes to repeat after prior-state warmup" {
  let prefix = Bytes::makei(80, i => {
    ((i * 11 + 29) % 251).reinterpret_as_uint().to_byte()
  })
  let chunk = Bytes::makei(96, i => {
    ((i * 13 + 7) % 241).reinterpret_as_uint().to_byte()
  })
  let mid = Bytes::makei(6000, i => {
    ((i * 17 + 101) % 239).reinterpret_as_uint().to_byte()
  })
  let src = prefix + chunk + b"#" + chunk + mid + chunk + b"@" + chunk
  let payload = try? build_general_predefined_payload(src, 0, src.length(), 14)
  match payload {
    Ok(v) => {
      assert_true(v.length() > 0)
      let prev_rle_valid : Ref[Bool] = { val: false }
      let prev_ll_code : Ref[UInt] = { val: 0 }
      let prev_off_code : Ref[UInt] = { val: 0 }
      let prev_ml_code : Ref[UInt] = { val: 0 }
      let prev_predefined_valid : Ref[Bool] = { val: false }
      let prev_compressed_valid : Ref[Bool] = { val: false }
      let prev_ll_header : Ref[Bytes] = { val: b"" }
      let prev_off_header : Ref[Bytes] = { val: b"" }
      let prev_ml_header : Ref[Bytes] = { val: b"" }

      let first = maybe_rewrite_sequence_modes_to_repeat(
        v, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
        prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
      )
      let first_modes_pos = payload_sequence_modes_offset(first)
      assert_true(first_modes_pos >= 0)
      assert_eq(first[first_modes_pos].to_uint(), 0)

      let second = maybe_rewrite_sequence_modes_to_repeat(
        v, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
        prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
      )
      let second_modes_pos = payload_sequence_modes_offset(second)
      assert_true(second_modes_pos >= 0)
      assert_eq(second[second_modes_pos].to_uint(), 0xFC)
      assert_eq(first.length(), second.length())
    }
    Err(_) =>
      fail("failed to build predefined payload for repeat-mode rewrite test")
  }
}

///|
test "rewrite compressed mode2 sequence modes to repeat after prior-state warmup" {
  let prefix = Bytes::makei(80, i => {
    ((i * 11 + 29) % 251).reinterpret_as_uint().to_byte()
  })
  let a = Bytes::makei(180, i => {
    ((i * 13 + 7) % 241).reinterpret_as_uint().to_byte()
  })
  let b = Bytes::makei(220, i => {
    ((i * 17 + 101) % 239).reinterpret_as_uint().to_byte()
  })
  let tail = Bytes::makei(32, i => {
    ((i * 19 + 61) % 233).reinterpret_as_uint().to_byte()
  })
  let src = prefix + a + b + b + a + b + a + b + b + tail
  let payload = try? build_general_compressed_fse_payload(
    src,
    0,
    src.length(),
    14,
  )
  match payload {
    Ok(v) => {
      assert_true(v.length() > 0)
      let prev_rle_valid : Ref[Bool] = { val: false }
      let prev_ll_code : Ref[UInt] = { val: 0 }
      let prev_off_code : Ref[UInt] = { val: 0 }
      let prev_ml_code : Ref[UInt] = { val: 0 }
      let prev_predefined_valid : Ref[Bool] = { val: false }
      let prev_compressed_valid : Ref[Bool] = { val: false }
      let prev_ll_header : Ref[Bytes] = { val: b"" }
      let prev_off_header : Ref[Bytes] = { val: b"" }
      let prev_ml_header : Ref[Bytes] = { val: b"" }

      let first = maybe_rewrite_sequence_modes_to_repeat(
        v, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
        prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
      )
      let first_modes_pos = payload_sequence_modes_offset(first)
      assert_true(first_modes_pos >= 0)
      assert_eq(first[first_modes_pos].to_uint(), 0xA8)

      let second = maybe_rewrite_sequence_modes_to_repeat(
        v, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
        prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
      )
      let second_modes_pos = payload_sequence_modes_offset(second)
      assert_true(second_modes_pos >= 0)
      assert_eq(second[second_modes_pos].to_uint(), 0xFC)
      assert_true(second.length() < first.length())
    }
    Err(_) =>
      fail("failed to build compressed payload for repeat-mode rewrite test")
  }
}

///|
test "rewrite compressed mode2 supports partial repeat per sequence source" {
  let prefix = Bytes::makei(80, i => {
    ((i * 11 + 29) % 251).reinterpret_as_uint().to_byte()
  })
  let a = Bytes::makei(180, i => {
    ((i * 13 + 7) % 241).reinterpret_as_uint().to_byte()
  })
  let b = Bytes::makei(220, i => {
    ((i * 17 + 101) % 239).reinterpret_as_uint().to_byte()
  })
  let tail = Bytes::makei(32, i => {
    ((i * 19 + 61) % 233).reinterpret_as_uint().to_byte()
  })
  let src = prefix + a + b + b + a + b + a + b + b + tail
  let payload = try? build_general_compressed_fse_payload(
    src,
    0,
    src.length(),
    14,
  )
  match payload {
    Ok(v) => {
      assert_true(v.length() > 0)
      let parsed = try? parse_sequence_mode_sources(v)
      match parsed {
        Ok((_, ll_mode, off_mode, ml_mode, _, off_header, ml_header, _)) => {
          assert_eq(ll_mode, 2)
          assert_eq(off_mode, 2)
          assert_eq(ml_mode, 2)
          let prev_rle_valid : Ref[Bool] = { val: false }
          let prev_ll_code : Ref[UInt] = { val: 0 }
          let prev_off_code : Ref[UInt] = { val: 0 }
          let prev_ml_code : Ref[UInt] = { val: 0 }
          let prev_predefined_valid : Ref[Bool] = { val: false }
          let prev_compressed_valid : Ref[Bool] = { val: false }
          let prev_ll_header : Ref[Bytes] = { val: b"" }
          let prev_off_header : Ref[Bytes] = { val: b"" }
          let prev_ml_header : Ref[Bytes] = { val: b"" }

          let warmup = maybe_rewrite_sequence_modes_to_repeat(
            v, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
            prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
          )
          let warmup_modes = payload_sequence_modes_offset(warmup)
          assert_true(warmup_modes >= 0)
          assert_eq(warmup[warmup_modes].to_uint(), 0xA8)

          // Force LL table mismatch while keeping OF/ML matches.
          prev_ll_header.val = b"\x00"
          let partial = maybe_rewrite_sequence_modes_to_repeat(
            v, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
            prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
          )
          let partial_modes = payload_sequence_modes_offset(partial)
          assert_true(partial_modes >= 0)
          assert_eq(partial[partial_modes].to_uint(), 0xBC)
          assert_eq(
            partial.length(),
            v.length() - off_header.length() - ml_header.length(),
          )
        }
        Err(_) =>
          fail("failed to parse compressed mode2 headers for partial test")
      }
    }
    Err(_) => fail("failed to build compressed payload for partial repeat test")
  }
}

///|
test "rewrite mixed sequence payload rewrites compressed sources independently" {
  let prefix = Bytes::makei(80, i => {
    ((i * 11 + 29) % 251).reinterpret_as_uint().to_byte()
  })
  let a = Bytes::makei(180, i => {
    ((i * 13 + 7) % 241).reinterpret_as_uint().to_byte()
  })
  let b = Bytes::makei(220, i => {
    ((i * 17 + 101) % 239).reinterpret_as_uint().to_byte()
  })
  let tail = Bytes::makei(32, i => {
    ((i * 19 + 61) % 233).reinterpret_as_uint().to_byte()
  })
  let src = prefix + a + b + b + a + b + a + b + b + tail
  let payload = try? build_general_compressed_fse_payload(
    src,
    0,
    src.length(),
    14,
  )
  match payload {
    Ok(v) => {
      if v.length() == 0 {
        fail("rep2 payload unexpectedly empty")
      }
      let parsed = try? parse_sequence_mode_sources(v)
      match parsed {
        Ok(
          (
            mode_pos,
            ll_mode,
            off_mode,
            ml_mode,
            _,
            off_header,
            ml_header,
            bitstream_start,
          )
        ) => {
          assert_eq(ll_mode, 2)
          assert_eq(off_mode, 2)
          assert_eq(ml_mode, 2)
          let prev_rle_valid : Ref[Bool] = { val: false }
          let prev_ll_code : Ref[UInt] = { val: 0 }
          let prev_off_code : Ref[UInt] = { val: 0 }
          let prev_ml_code : Ref[UInt] = { val: 0 }
          let prev_predefined_valid : Ref[Bool] = { val: false }
          let prev_compressed_valid : Ref[Bool] = { val: false }
          let prev_ll_header : Ref[Bytes] = { val: b"" }
          let prev_off_header : Ref[Bytes] = { val: b"" }
          let prev_ml_header : Ref[Bytes] = { val: b"" }

          let warmup = maybe_rewrite_sequence_modes_to_repeat(
            v, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
            prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
          )
          let warmup_modes = payload_sequence_modes_offset(warmup)
          assert_true(warmup_modes >= 0)
          assert_eq(warmup[warmup_modes].to_uint(), 0xA8)

          let mixed_arr : Array[Byte] = Array::new()
          append_bytes(mixed_arr, v, 0, mode_pos)
          mixed_arr.push((0x28 : UInt).to_byte())
          append_bytes(mixed_arr, off_header, 0, off_header.length())
          append_bytes(mixed_arr, ml_header, 0, ml_header.length())
          append_bytes(
            mixed_arr,
            v,
            bitstream_start,
            v.length() - bitstream_start,
          )
          let mixed_payload = Bytes::from_array(mixed_arr)

          let rewritten = maybe_rewrite_sequence_modes_to_repeat(
            mixed_payload, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code,
            prev_predefined_valid, prev_compressed_valid, prev_ll_header, prev_off_header,
            prev_ml_header,
          )
          let rewritten_modes = payload_sequence_modes_offset(rewritten)
          assert_true(rewritten_modes >= 0)
          assert_eq(rewritten[rewritten_modes].to_uint(), 0x3C)
          assert_eq(
            rewritten.length(),
            mixed_payload.length() - off_header.length() - ml_header.length(),
          )

          let second = maybe_rewrite_sequence_modes_to_repeat(
            mixed_payload, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code,
            prev_predefined_valid, prev_compressed_valid, prev_ll_header, prev_off_header,
            prev_ml_header,
          )
          let second_modes = payload_sequence_modes_offset(second)
          assert_true(second_modes >= 0)
          assert_eq(second[second_modes].to_uint(), 0x3C)
          assert_eq(
            second.length(),
            mixed_payload.length() - off_header.length() - ml_header.length(),
          )
        }
        Err(_) =>
          fail("failed to parse mode2 payload for mixed sequence rewrite test")
      }
    }
    Err(_) =>
      fail("failed to build compressed payload for mixed sequence rewrite test")
  }
}

///|
test "single-match payload uses RLE literals section when literals are single-value" {
  let src = Bytes::makei(12, _ => b"x"[0])
  let payload = try? build_single_match_payload_rle(
    src, 0, 12, 4, 4, 4, 4, 1, 4,
  )
  match payload {
    Ok(v) => {
      assert_true(v.length() > 0)
      assert_eq(v[0].to_uint() & 0x3, 1)
    }
    Err(_) => fail("failed to build single-match payload")
  }
}

///|
test "single-match payload keeps raw literals section for mixed literals" {
  let src = b"abcabczzz"
  let payload = try? build_single_match_payload_rle(src, 0, 9, 3, 3, 3, 3, 1, 4)
  match payload {
    Ok(v) => {
      assert_true(v.length() > 0)
      assert_eq(v[0].to_uint() & 0x3, 0)
    }
    Err(_) => fail("failed to build mixed-literals payload")
  }
}

///|
test "single-match payload can encode dictionary rep2 with ll=0 as off_code0" {
  let src = b"abcdZ"
  let payload = try? build_single_match_payload_rle(src, 0, 5, 0, 4, 4, 8, 1, 4)
  match payload {
    Ok(v) => {
      assert_true(v.length() >= 4)
      assert_eq(v[v.length() - 4].to_uint(), 0x54)
      assert_eq(v[v.length() - 2].to_uint(), 0) // off_code
    }
    Err(_) => fail("failed to build rep2 single-match payload")
  }
}

///|
test "best literals section can emit compressed Huffman literals and roundtrip decode" {
  let literals = Bytes::makei(512, fn(i) {
    if i % 31 == 0 {
      b"C"[0]
    } else if i % 7 == 0 {
      b"B"[0]
    } else {
      b"A"[0]
    }
  })
  let section_out : Array[Byte] = Array::new()
  let encoded = try? append_best_literals_section(section_out, literals)
  match encoded {
    Ok(_) => {
      let section = Bytes::from_array(section_out)
      assert_true(section.length() > 0)
      assert_eq(section[0].to_uint() & 0x3, 2)

      let prev_huf_valid : Ref[Bool] = { val: false }
      let prev_huf_max_bits : Ref[Int] = { val: 0 }
      let prev_huf_left : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_right : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_symbol : Ref[Array[Int]] = { val: Array::new() }
      let decoded = try? decode_literals_section_minimal(
        section,
        0,
        section.length(),
        prev_huf_valid,
        prev_huf_max_bits,
        prev_huf_left,
        prev_huf_right,
        prev_huf_symbol,
      )
      match decoded {
        Ok((next_pos, restored)) => {
          assert_eq(next_pos, section.length())
          assert_eq(restored, literals)
        }
        Err(_) => fail("failed to decode encoded compressed literals section")
      }
    }
    Err(_) => fail("failed to encode best literals section")
  }
}

///|
test "best literals section falls back to raw when direct-weight range is unsupported" {
  let literals = Bytes::makei(96, fn(i) {
    if (i & 1) == 0 {
      b"\xFF"[0]
    } else {
      b"A"[0]
    }
  })
  let out : Array[Byte] = Array::new()
  let encoded = try? append_best_literals_section(out, literals)
  match encoded {
    Ok(_) => {
      assert_true(out.length() > 0)
      assert_eq(out[0].to_uint() & 0x3, 0)
    }
    Err(_) => fail("failed to append best literals section")
  }
}

///|
test "treeless literals rewrite emits type3 on repeated Huffman tree" {
  let literals = Bytes::makei(512, fn(i) {
    if i % 31 == 0 {
      b"C"[0]
    } else if i % 7 == 0 {
      b"B"[0]
    } else {
      b"A"[0]
    }
  })
  let encoded1 = try? try_build_compressed_literals_section(literals)
  let encoded2 = try? try_build_compressed_literals_section(literals)
  match encoded1 {
    Ok(section1) =>
      match encoded2 {
        Ok(section2) => {
          assert_true(section1.length() > 0)
          assert_true(section2.length() > 0)
          assert_eq(section1[0].to_uint() & 0x3, 2)
          assert_eq(section2[0].to_uint() & 0x3, 2)

          let prev_tree_valid : Ref[Bool] = { val: false }
          let prev_tree_desc : Ref[Bytes] = { val: b"" }
          let rewritten1 = rewrite_literals_section_to_treeless_if_repeat(
            section1, prev_tree_valid, prev_tree_desc,
          )
          let rewritten2 = rewrite_literals_section_to_treeless_if_repeat(
            section2, prev_tree_valid, prev_tree_desc,
          )
          let first_payload = rewritten1
          let second_payload = rewritten2
          assert_eq(first_payload[0].to_uint() & 0x3, 2)
          assert_eq(second_payload[0].to_uint() & 0x3, 3)
          assert_true(second_payload.length() < section2.length())

          let prev_huf_valid : Ref[Bool] = { val: false }
          let prev_huf_max_bits : Ref[Int] = { val: 0 }
          let prev_huf_left : Ref[Array[Int]] = { val: Array::new() }
          let prev_huf_right : Ref[Array[Int]] = { val: Array::new() }
          let prev_huf_symbol : Ref[Array[Int]] = { val: Array::new() }
          let decoded1 = try? decode_literals_section_minimal(
            first_payload,
            0,
            first_payload.length(),
            prev_huf_valid,
            prev_huf_max_bits,
            prev_huf_left,
            prev_huf_right,
            prev_huf_symbol,
          )
          let decoded2 = try? decode_literals_section_minimal(
            second_payload,
            0,
            second_payload.length(),
            prev_huf_valid,
            prev_huf_max_bits,
            prev_huf_left,
            prev_huf_right,
            prev_huf_symbol,
          )
          match decoded1 {
            Ok((next1, out1)) => {
              assert_eq(next1, first_payload.length())
              assert_eq(out1, literals)
            }
            Err(_) => fail("failed to decode first payload")
          }
          match decoded2 {
            Ok((next2, out2)) => {
              assert_eq(next2, second_payload.length())
              assert_eq(out2, literals)
            }
            Err(_) => fail("failed to decode treeless rewritten payload")
          }
        }
        Err(_) => fail("failed to build second compressed literals section")
      }
    Err(_) => fail("failed to build first compressed literals section")
  }
}

///|
test "rewrite predefined sequence modes works with compressed literals payload" {
  let literals = Bytes::makei(512, fn(i) {
    if i % 31 == 0 {
      b"C"[0]
    } else if i % 7 == 0 {
      b"B"[0]
    } else {
      b"A"[0]
    }
  })
  let section = try? try_build_compressed_literals_section(literals)
  match section {
    Ok(lit_section) => {
      assert_true(lit_section.length() > 0)
      assert_true((lit_section[0].to_uint() & 0x3) == 2)
      let payload_arr : Array[Byte] = Array::new()
      append_bytes(payload_arr, lit_section, 0, lit_section.length())
      let encoded_count = try? append_sequence_count(payload_arr, 1)
      match encoded_count {
        Ok(_) => {
          payload_arr.push((0 : UInt).to_byte()) // all predefined sequence modes
          payload_arr.push((0 : UInt).to_byte()) // dummy predefined states
          let payload = Bytes::from_array(payload_arr)

          let prev_rle_valid : Ref[Bool] = { val: false }
          let prev_ll_code : Ref[UInt] = { val: 0 }
          let prev_off_code : Ref[UInt] = { val: 0 }
          let prev_ml_code : Ref[UInt] = { val: 0 }
          let prev_predefined_valid : Ref[Bool] = { val: false }
          let prev_compressed_valid : Ref[Bool] = { val: false }
          let prev_ll_header : Ref[Bytes] = { val: b"" }
          let prev_off_header : Ref[Bytes] = { val: b"" }
          let prev_ml_header : Ref[Bytes] = { val: b"" }

          let first = maybe_rewrite_sequence_modes_to_repeat(
            payload, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
            prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
          )
          let first_modes_pos = payload_sequence_modes_offset(first)
          assert_true(first_modes_pos >= 0)
          assert_eq(first[first_modes_pos].to_uint(), 0)
          assert_true(prev_predefined_valid.val)

          let second = maybe_rewrite_sequence_modes_to_repeat(
            payload, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
            prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
          )
          let second_modes_pos = payload_sequence_modes_offset(second)
          assert_true(second_modes_pos >= 0)
          assert_eq(second[second_modes_pos].to_uint(), 0xFC)
        }
        Err(_) =>
          fail(
            "failed to append sequence count for compressed literals payload",
          )
      }
    }
    Err(_) => fail("failed to build compressed literals section")
  }
}

///|
test "literals-only payload encodes sequence_count zero with compressed literals" {
  let src = Bytes::makei(128, fn(i) {
    if i % 17 == 0 {
      b"B"[0]
    } else {
      b"A"[0]
    }
  })
  let payload = try? build_literals_only_payload(src, 0, src.length(), 12)
  match payload {
    Ok(data) => {
      assert_true(data.length() > 0)
      let seq_count_pos = payload_sequence_count_offset(data)
      assert_true(seq_count_pos >= 0)
      assert_eq(data[seq_count_pos].to_uint(), 0)

      let prev_huf_valid : Ref[Bool] = { val: false }
      let prev_huf_max_bits : Ref[Int] = { val: 0 }
      let prev_huf_left : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_right : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_symbol : Ref[Array[Int]] = { val: Array::new() }
      let lit = try? decode_literals_section_minimal(
        data,
        0,
        data.length(),
        prev_huf_valid,
        prev_huf_max_bits,
        prev_huf_left,
        prev_huf_right,
        prev_huf_symbol,
      )
      match lit {
        Ok((next_pos, literals)) => {
          assert_eq(next_pos, seq_count_pos)
          assert_eq(literals, src)
        }
        Err(_) =>
          fail("failed to decode literals-only payload literals section")
      }
    }
    Err(_) => fail("failed to build literals-only payload")
  }
}

///|
test "compressed literals support four-stream size_format=2 roundtrip" {
  let literals = Bytes::makei(2048, fn(i) {
    if i % 29 == 0 {
      b"C"[0]
    } else if i % 5 == 0 {
      b"B"[0]
    } else {
      b"A"[0]
    }
  })
  let encoded = try? try_build_compressed_literals_section(literals)
  match encoded {
    Ok(section) => {
      assert_true(section.length() > 0)
      assert_eq(section[0].to_uint() & 0x3, 2)
      assert_eq((section[0].to_uint() >> 2) & 0x3, 2)
      let prev_huf_valid : Ref[Bool] = { val: false }
      let prev_huf_max_bits : Ref[Int] = { val: 0 }
      let prev_huf_left : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_right : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_symbol : Ref[Array[Int]] = { val: Array::new() }
      let decoded = try? decode_literals_section_minimal(
        section,
        0,
        section.length(),
        prev_huf_valid,
        prev_huf_max_bits,
        prev_huf_left,
        prev_huf_right,
        prev_huf_symbol,
      )
      match decoded {
        Ok((next_pos, restored)) => {
          assert_eq(next_pos, section.length())
          assert_eq(restored, literals)
        }
        Err(_) => fail("failed to decode size_format=2 literals section")
      }
    }
    Err(_) => fail("failed to encode size_format=2 literals section")
  }
}

///|
test "compressed literals support four-stream size_format=3 roundtrip" {
  let literals = Bytes::makei(20000, fn(i) {
    if i % 37 == 0 {
      b"C"[0]
    } else if i % 3 == 0 {
      b"B"[0]
    } else {
      b"A"[0]
    }
  })
  let encoded = try? try_build_compressed_literals_section(literals)
  match encoded {
    Ok(section) => {
      assert_true(section.length() > 0)
      assert_eq(section[0].to_uint() & 0x3, 2)
      assert_eq((section[0].to_uint() >> 2) & 0x3, 3)
      let prev_huf_valid : Ref[Bool] = { val: false }
      let prev_huf_max_bits : Ref[Int] = { val: 0 }
      let prev_huf_left : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_right : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_symbol : Ref[Array[Int]] = { val: Array::new() }
      let decoded = try? decode_literals_section_minimal(
        section,
        0,
        section.length(),
        prev_huf_valid,
        prev_huf_max_bits,
        prev_huf_left,
        prev_huf_right,
        prev_huf_symbol,
      )
      match decoded {
        Ok((next_pos, restored)) => {
          assert_eq(next_pos, section.length())
          assert_eq(restored, literals)
        }
        Err(_) => fail("failed to decode size_format=3 literals section")
      }
    }
    Err(_) => fail("failed to encode size_format=3 literals section")
  }
}

///|
test "huffman weights FSE payload can roundtrip and beat direct length on sparse prefix" {
  let values = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
  let payload = try? build_huffman_weights_fse_payload(values)
  match payload {
    Ok(data) => {
      assert_true(data.length() > 0)
      let decoded = try? read_huffman_weights_fse(data, 0, data.length())
      match decoded {
        Ok(weights) => {
          assert_eq(weights.length(), values.length())
          let mut i = 0
          while i < values.length() {
            assert_eq(weights[i], values[i])
            i = i + 1
          }
        }
        Err(_) => fail("failed to decode emitted FSE payload")
      }
      let direct_len = 1 + ((values.length() + 1) >> 1)
      assert_true(data.length() + 1 < direct_len)
    }
    Err(_) => fail("failed to build FSE payload for sparse prefix")
  }
}

///|
test "huffman weights FSE description prefixes payload size and roundtrips payload decode" {
  let weights = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
  let desc = try? try_build_huffman_fse_weights_description(weights, 11)
  match desc {
    Ok(data) => {
      assert_true(data.length() > 1)
      let payload_size = data[0].to_uint().reinterpret_as_int()
      assert_true(payload_size > 0)
      assert_eq(payload_size + 1, data.length())
      let decoded = try? read_huffman_weights_fse(data, 1, data.length())
      match decoded {
        Ok(values) => {
          assert_eq(values.length(), weights.length())
          let mut i = 0
          while i < weights.length() {
            assert_eq(values[i], weights[i])
            i = i + 1
          }
        }
        Err(_) =>
          fail("failed to decode payload behind FSE weights description")
      }
    }
    Err(_) => fail("failed to build FSE weights description")
  }
}

///|
fn encode_sequence_count_for_test(seq_count : Int) -> Bytes raise ZstdError {
  let payload : Array[Byte] = Array::new()
  append_sequence_count(payload, seq_count)
  Bytes::from_array(payload)
}

///|
test "sequence_count encoding supports 1-byte 2-byte and 3-byte forms" {
  let cases = [0, 1, 127, 128, 255, 256, 0x7EFF, 0x7F00, 0x7F01, 0x17EFF]
  let mut i = 0
  while i < cases.length() {
    let expected = cases[i]
    let enc = try? encode_sequence_count_for_test(expected)
    match enc {
      Ok(data) => {
        let parsed = try? parse_sequence_count(data, 0, data.length())
        match parsed {
          Ok((value, pos)) => {
            assert_eq(value.reinterpret_as_int(), expected)
            assert_eq(pos, data.length())
          }
          Err(_) => fail("parse_sequence_count failed on encoded value")
        }
      }
      Err(_) => fail("append_sequence_count failed on boundary value")
    }
    i = i + 1
  }
}

///|
test "sequence_count encoding rejects values above max supported range" {
  let result = try? encode_sequence_count_for_test(0x17EFF + 1)
  match result {
    Ok(_) => fail("expected append_sequence_count to reject out-of-range value")
    Err(CorruptionDetected) => ()
    Err(SrcSizeWrong) => fail("unexpected SrcSizeWrong")
    Err(BoundOverflow) => fail("unexpected BoundOverflow")
    Err(SrcSizeTooLarge(_)) => fail("unexpected SrcSizeTooLarge")
    Err(DictionaryRequired(dict_id)) =>
      fail("unexpected DictionaryRequired: " + dict_id.to_string())
    Err(UnsupportedFeature(msg)) =>
      fail("unexpected UnsupportedFeature: " + msg)
  }
}

///|
test "write_fse_ncount_header roundtrips sparse counters with zero runs" {
  let normalized = [20, 0, 0, 8, 0, 0, 0, 36]
  let header = try? write_fse_ncount_header(normalized, 7, 6)
  match header {
    Ok(bytes) => {
      let parsed = try? read_fse_ncount_header(bytes, 0, bytes.length(), 7, 6)
      match parsed {
        Ok((_, parsed_table_log, parsed_max_symbol, decoded_counter)) => {
          assert_eq(parsed_table_log, 6)
          assert_eq(parsed_max_symbol, 7)
          let mut i = 0
          while i <= 7 {
            assert_eq(decoded_counter[i], normalized[i])
            i = i + 1
          }
        }
        Err(_) => fail("failed to parse encoded ncount header")
      }
    }
    Err(_) => fail("failed to write ncount header")
  }
}

///|
test "write_fse_ncount_header roundtrips counters with low-probability symbol" {
  let normalized = [20, -1, 0, 0, 0, 43]
  let header = try? write_fse_ncount_header(normalized, 5, 6)
  match header {
    Ok(bytes) => {
      let parsed = try? read_fse_ncount_header(bytes, 0, bytes.length(), 5, 6)
      match parsed {
        Ok((_, parsed_table_log, parsed_max_symbol, decoded_counter)) => {
          assert_eq(parsed_table_log, 6)
          assert_eq(parsed_max_symbol, 5)
          let mut i = 0
          while i <= 5 {
            assert_eq(decoded_counter[i], normalized[i])
            i = i + 1
          }
        }
        Err(_) => fail("failed to parse encoded ncount header")
      }
    }
    Err(_) => fail("failed to write ncount header")
  }
}

///|
test "write_fse_ncount_header rejects invalid normalized sum" {
  let normalized = [10, 10, 10]
  let result = try? write_fse_ncount_header(normalized, 2, 6)
  match result {
    Ok(_) => fail("expected write_fse_ncount_header to reject invalid sum")
    Err(CorruptionDetected) => ()
    Err(SrcSizeWrong) => fail("unexpected SrcSizeWrong")
    Err(BoundOverflow) => fail("unexpected BoundOverflow")
    Err(SrcSizeTooLarge(_)) => fail("unexpected SrcSizeTooLarge")
    Err(DictionaryRequired(dict_id)) =>
      fail("unexpected DictionaryRequired: " + dict_id.to_string())
    Err(UnsupportedFeature(msg)) =>
      fail("unexpected UnsupportedFeature: " + msg)
  }
}

///|
test "predefined state path selection keeps valid transitions" {
  let ll_values = [64, 4096, 96]
  let ll = try? select_predefined_state_path(
    ll_values, sequence_symbol_literal_length,
  )
  match ll {
    Ok((ok, states, _, _, _, _)) => {
      assert_true(ok)
      assert_eq(states.length(), ll_values.length())
      let mut i = 0
      while i + 1 < states.length() {
        let entry = try? predefined_sequence_entry(
          sequence_symbol_literal_length,
          states[i],
        )
        match entry {
          Ok((next_state, _, state_bits, _)) => {
            let range = if state_bits == 0 { 1 } else { 1 << state_bits }
            assert_true(states[i + 1] >= next_state)
            assert_true(states[i + 1] < next_state + range)
          }
          Err(_) => fail("failed to read LL predefined entry")
        }
        i = i + 1
      }
    }
    Err(_) => fail("failed to select LL predefined state path")
  }

  let off_values = [128, 8192, 256]
  let off = try? select_predefined_state_path(
    off_values, sequence_symbol_offset,
  )
  match off {
    Ok((ok, states, _, off_extra_bits, _, _)) => {
      assert_true(ok)
      assert_eq(states.length(), off_values.length())
      let mut i = 0
      while i < off_extra_bits.length() {
        assert_true(off_extra_bits[i] > 1)
        i = i + 1
      }
      i = 0
      while i + 1 < states.length() {
        let entry = try? predefined_sequence_entry(
          sequence_symbol_offset,
          states[i],
        )
        match entry {
          Ok((next_state, _, state_bits, _)) => {
            let range = if state_bits == 0 { 1 } else { 1 << state_bits }
            assert_true(states[i + 1] >= next_state)
            assert_true(states[i + 1] < next_state + range)
          }
          Err(_) => fail("failed to read OF predefined entry")
        }
        i = i + 1
      }
    }
    Err(_) => fail("failed to select OF predefined state path")
  }
}

///|
test "predefined offset path can encode rep3 and ll0 repcode combos" {
  let off_values = [300, 302]
  let ll_values = [1, 0]
  let result = try? select_predefined_offset_state_path(
    off_values, ll_values, 301, 302, 300,
  )
  match result {
    Ok((ok, states, extras, off_extra_bits, _, _)) => {
      assert_true(ok)
      assert_eq(states.length(), off_values.length())
      assert_eq(extras.length(), off_values.length())
      assert_eq(off_extra_bits.length(), off_values.length())
      assert_true(off_extra_bits[0] <= 1)
      assert_true(off_extra_bits[1] <= 1)

      let mut r1 = 301
      let mut r2 = 302
      let mut r3 = 300
      let mut i = 0
      while i < states.length() {
        let ll0 = ll_values[i] == 0
        let entry = try? of_predefined_entry(states[i])
        let (_, add_bits, _, base) = match entry {
          Ok(v) => v
          Err(_) => fail("failed to read OF predefined entry")
        }
        let extra = extras[i].reinterpret_as_int()
        let offset = if add_bits > 1 {
          let value = base + extra
          r3 = r2
          r2 = r1
          r1 = value
          value
        } else if add_bits == 0 {
          let value = if ll0 { r2 } else { r1 }
          if ll0 {
            r2 = r1
          }
          r1 = value
          value
        } else {
          let offset_code = base + (if ll0 { 1 } else { 0 }) + extra
          let value = if offset_code == 1 {
            r2
          } else if offset_code == 2 {
            r3
          } else if offset_code == 3 {
            r1 - 1
          } else {
            fail("invalid rep offset_code")
          }
          if offset_code != 1 {
            r3 = r2
          }
          r2 = r1
          r1 = value
          value
        }
        assert_eq(offset, off_values[i])
        i = i + 1
      }
    }
    Err(_) => fail("failed to select rep-aware predefined offset path")
  }
}

///|
test "general predefined payload builder emits parseable multi-sequence payload" {
  let prefix = Bytes::makei(80, i => {
    ((i * 11 + 29) % 251).reinterpret_as_uint().to_byte()
  })
  let chunk = Bytes::makei(96, i => {
    ((i * 13 + 7) % 241).reinterpret_as_uint().to_byte()
  })
  let mid = Bytes::makei(6000, i => {
    ((i * 17 + 101) % 239).reinterpret_as_uint().to_byte()
  })
  let src = prefix + chunk + b"#" + chunk + mid + chunk + b"@" + chunk

  let payload = try? build_general_predefined_payload(src, 0, src.length(), 14)
  match payload {
    Ok(v) => {
      assert_true(v.length() > 0)
      let modes_pos = payload_sequence_modes_offset(v)
      assert_true(modes_pos >= 0)
      assert_eq(v[modes_pos].to_uint(), 0)

      let seq_count_pos = payload_sequence_count_offset(v)
      assert_true(seq_count_pos >= 0)
      let parsed = try? parse_sequence_count(v, seq_count_pos, v.length())
      match parsed {
        Ok((count, _)) => assert_true(count.reinterpret_as_int() >= 2)
        Err(_) => fail("failed to parse sequence_count from predefined payload")
      }
    }
    Err(_) => fail("failed to build general predefined payload")
  }
}

///|
test "general compressed FSE payload builder emits mode2 and decodes" {
  let prefix = Bytes::makei(80, i => {
    ((i * 11 + 29) % 251).reinterpret_as_uint().to_byte()
  })
  let a = Bytes::makei(180, i => {
    ((i * 13 + 7) % 241).reinterpret_as_uint().to_byte()
  })
  let b = Bytes::makei(220, i => {
    ((i * 17 + 101) % 239).reinterpret_as_uint().to_byte()
  })
  let tail = Bytes::makei(32, i => {
    ((i * 19 + 61) % 233).reinterpret_as_uint().to_byte()
  })
  let src = prefix + a + b + b + a + b + a + b + b + tail

  let payload = try? build_general_compressed_fse_payload(
    src,
    0,
    src.length(),
    14,
  )
  match payload {
    Ok(v) => {
      assert_true(v.length() > 0)
      let modes_pos = payload_sequence_modes_offset(v)
      assert_true(modes_pos >= 0)
      assert_eq(v[modes_pos].to_uint(), 0xA8)

      let out : Array[Byte] = Array::new()
      let prev_huf_valid : Ref[Bool] = { val: false }
      let prev_huf_max_bits : Ref[Int] = { val: 0 }
      let prev_huf_left : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_right : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_symbol : Ref[Array[Int]] = { val: Array::new() }
      let prev_ll_valid : Ref[Bool] = { val: false }
      let prev_ll_kind : Ref[Int] = { val: 0 }
      let prev_ll_code : Ref[UInt] = { val: 0 }
      let prev_ll_table_log : Ref[Int] = { val: 0 }
      let prev_ll_table_next_state : Ref[Array[Int]] = { val: Array::new() }
      let prev_ll_table_nb_add_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_ll_table_nb_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_ll_table_base_values : Ref[Array[Int]] = { val: Array::new() }
      let prev_off_valid : Ref[Bool] = { val: false }
      let prev_off_kind : Ref[Int] = { val: 0 }
      let prev_off_code : Ref[UInt] = { val: 0 }
      let prev_off_table_log : Ref[Int] = { val: 0 }
      let prev_off_table_next_state : Ref[Array[Int]] = { val: Array::new() }
      let prev_off_table_nb_add_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_off_table_nb_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_off_table_base_values : Ref[Array[Int]] = { val: Array::new() }
      let prev_ml_valid : Ref[Bool] = { val: false }
      let prev_ml_kind : Ref[Int] = { val: 0 }
      let prev_ml_code : Ref[UInt] = { val: 0 }
      let prev_ml_table_log : Ref[Int] = { val: 0 }
      let prev_ml_table_next_state : Ref[Array[Int]] = { val: Array::new() }
      let prev_ml_table_nb_add_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_ml_table_nb_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_ml_table_base_values : Ref[Array[Int]] = { val: Array::new() }

      let decoded = try? decode_compressed_block_minimal(
        v,
        0,
        v.length(),
        out,
        0,
        b"",
        1,
        4,
        8,
        prev_huf_valid,
        prev_huf_max_bits,
        prev_huf_left,
        prev_huf_right,
        prev_huf_symbol,
        prev_ll_valid,
        prev_ll_kind,
        prev_ll_code,
        prev_ll_table_log,
        prev_ll_table_next_state,
        prev_ll_table_nb_add_bits,
        prev_ll_table_nb_bits,
        prev_ll_table_base_values,
        prev_off_valid,
        prev_off_kind,
        prev_off_code,
        prev_off_table_log,
        prev_off_table_next_state,
        prev_off_table_nb_add_bits,
        prev_off_table_nb_bits,
        prev_off_table_base_values,
        prev_ml_valid,
        prev_ml_kind,
        prev_ml_code,
        prev_ml_table_log,
        prev_ml_table_next_state,
        prev_ml_table_nb_add_bits,
        prev_ml_table_nb_bits,
        prev_ml_table_base_values,
      )
      match decoded {
        Ok((next_pos, produced, _, _, _)) => {
          assert_eq(next_pos, v.length())
          assert_eq(produced, src.length().to_uint64())
          assert_eq(Bytes::from_array(out), src)
        }
        Err(_) =>
          fail("decode_compressed_block_minimal failed on mode2 payload")
      }
    }
    Err(_) => fail("failed to build general compressed FSE payload")
  }
}

///|
test "compressed sequence source can use adaptive table_log above 5" {
  let values : Array[Int] = Array::new()
  let mut i = 0
  while i < 72 {
    let v = if i % 4 == 0 {
      1 + i % 31
    } else if i % 4 == 1 {
      32 + i * 3 % 1024
    } else if i % 4 == 2 {
      2048 + i * 11 % 8192
    } else {
      64 + i * 7 % 4096
    }
    values.push(v)
    i = i + 1
  }
  let result = try? build_compressed_sequence_source(
    values, sequence_symbol_literal_length,
  )
  match result {
    Ok((ok, header, _, table_log, _, _, _, _)) => {
      assert_true(ok)
      assert_true(table_log > 5)
      let parsed = try? read_fse_ncount_header(
        header,
        0,
        header.length(),
        35,
        9,
      )
      match parsed {
        Ok((_, parsed_table_log, _, _)) =>
          assert_eq(parsed_table_log, table_log)
        Err(_) => fail("failed to parse adaptive table_log header")
      }
    }
    Err(_) => fail("failed to build compressed sequence source")
  }
}

///|
test "mixed source chooser can select different modes per sequence source" {
  let ll_values = [1, 20, 300, 4096]
  let off_values = [64, 64, 64, 64]
  let ml_values = [9, 9, 9, 9]

  let ll_choice = try? choose_sequence_source_mode(
    ll_values, sequence_symbol_literal_length, 20,
  )
  let off_choice = try? choose_sequence_source_mode(
    off_values, sequence_symbol_offset, 20,
  )
  let ml_choice = try? choose_sequence_source_mode(
    ml_values, sequence_symbol_match_length, 20,
  )

  match ll_choice {
    Ok((ll_ok, ll_mode, _, _, _, _, _, _, _)) => {
      assert_true(ll_ok)
      match off_choice {
        Ok((off_ok, off_mode, _, _, _, _, _, _, _)) => {
          assert_true(off_ok)
          assert_eq(off_mode, 1)
          assert_true(ll_mode != off_mode)
          match ml_choice {
            Ok((ml_ok, _, _, _, _, _, _, _, _)) => assert_true(ml_ok)
            Err(_) => fail("failed to choose ML source mode")
          }
        }
        Err(_) => fail("failed to choose OF source mode")
      }
    }
    Err(_) => fail("failed to choose LL source mode")
  }
}

///|
test "general mixed payload builder emits parseable payload and decodes" {
  let prefix = Bytes::makei(70, i => {
    ((i * 11 + 29) % 251).reinterpret_as_uint().to_byte()
  })
  let a = Bytes::makei(180, i => {
    ((i * 13 + 7) % 241).reinterpret_as_uint().to_byte()
  })
  let b = Bytes::makei(220, i => {
    ((i * 17 + 101) % 239).reinterpret_as_uint().to_byte()
  })
  let c = Bytes::makei(140, i => {
    ((i * 19 + 61) % 233).reinterpret_as_uint().to_byte()
  })
  let src = prefix + a + b + a + c + b + a + c + b + a

  let payload = try? build_general_mixed_sequence_payload(
    src,
    0,
    src.length(),
    20,
  )
  match payload {
    Ok(v) => {
      assert_true(v.length() > 0)
      let modes_pos = payload_sequence_modes_offset(v)
      assert_true(modes_pos >= 0)
      assert_eq(v[modes_pos].to_uint() & 0x3, 0)

      let out : Array[Byte] = Array::new()
      let prev_huf_valid : Ref[Bool] = { val: false }
      let prev_huf_max_bits : Ref[Int] = { val: 0 }
      let prev_huf_left : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_right : Ref[Array[Int]] = { val: Array::new() }
      let prev_huf_symbol : Ref[Array[Int]] = { val: Array::new() }
      let prev_ll_valid : Ref[Bool] = { val: false }
      let prev_ll_kind : Ref[Int] = { val: 0 }
      let prev_ll_code : Ref[UInt] = { val: 0 }
      let prev_ll_table_log : Ref[Int] = { val: 0 }
      let prev_ll_table_next_state : Ref[Array[Int]] = { val: Array::new() }
      let prev_ll_table_nb_add_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_ll_table_nb_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_ll_table_base_values : Ref[Array[Int]] = { val: Array::new() }
      let prev_off_valid : Ref[Bool] = { val: false }
      let prev_off_kind : Ref[Int] = { val: 0 }
      let prev_off_code : Ref[UInt] = { val: 0 }
      let prev_off_table_log : Ref[Int] = { val: 0 }
      let prev_off_table_next_state : Ref[Array[Int]] = { val: Array::new() }
      let prev_off_table_nb_add_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_off_table_nb_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_off_table_base_values : Ref[Array[Int]] = { val: Array::new() }
      let prev_ml_valid : Ref[Bool] = { val: false }
      let prev_ml_kind : Ref[Int] = { val: 0 }
      let prev_ml_code : Ref[UInt] = { val: 0 }
      let prev_ml_table_log : Ref[Int] = { val: 0 }
      let prev_ml_table_next_state : Ref[Array[Int]] = { val: Array::new() }
      let prev_ml_table_nb_add_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_ml_table_nb_bits : Ref[Array[Int]] = { val: Array::new() }
      let prev_ml_table_base_values : Ref[Array[Int]] = { val: Array::new() }

      let decoded = try? decode_compressed_block_minimal(
        v,
        0,
        v.length(),
        out,
        0,
        b"",
        1,
        4,
        8,
        prev_huf_valid,
        prev_huf_max_bits,
        prev_huf_left,
        prev_huf_right,
        prev_huf_symbol,
        prev_ll_valid,
        prev_ll_kind,
        prev_ll_code,
        prev_ll_table_log,
        prev_ll_table_next_state,
        prev_ll_table_nb_add_bits,
        prev_ll_table_nb_bits,
        prev_ll_table_base_values,
        prev_off_valid,
        prev_off_kind,
        prev_off_code,
        prev_off_table_log,
        prev_off_table_next_state,
        prev_off_table_nb_add_bits,
        prev_off_table_nb_bits,
        prev_off_table_base_values,
        prev_ml_valid,
        prev_ml_kind,
        prev_ml_code,
        prev_ml_table_log,
        prev_ml_table_next_state,
        prev_ml_table_nb_add_bits,
        prev_ml_table_nb_bits,
        prev_ml_table_base_values,
      )
      match decoded {
        Ok((next_pos, produced, _, _, _)) => {
          assert_eq(next_pos, v.length())
          assert_eq(produced, src.length().to_uint64())
          assert_eq(Bytes::from_array(out), src)
        }
        Err(_) =>
          fail("decode_compressed_block_minimal failed on mixed payload")
      }
    }
    Err(_) => fail("failed to build general mixed payload")
  }
}

///|
test "decode literals section with 4 Huffman streams" {
  let frame = b"\x28\xb5\x2f\xfd\x64\x08\x06\x05\x03\x00\x96\x50\x13\x82\x11\x10\x11\x00\x11\x00\x11\x00\xb1\xb1\xb1\xb1\xb1\xb1\xb1\xb1\xb1\xb1\xb1\xb1\xb1\xb1\xb1\xb1\x41\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x5b\x01\x00\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x1b\x01\x81\x00\x98\x10\xf0\x07\x00\x10\x12\x3f\xd5\xaa\x55\xeb\x14\xa4\xfd\xf8\x0e\xdf"
  let prev_huf_valid : Ref[Bool] = { val: false }
  let prev_huf_max_bits : Ref[Int] = { val: 0 }
  let prev_huf_left : Ref[Array[Int]] = { val: Array::new() }
  let prev_huf_right : Ref[Array[Int]] = { val: Array::new() }
  let prev_huf_symbol : Ref[Array[Int]] = { val: Array::new() }
  let result = try? decode_literals_section_minimal(
    frame, 10, 106, prev_huf_valid, prev_huf_max_bits, prev_huf_left, prev_huf_right,
    prev_huf_symbol,
  )
  match result {
    Ok((next_pos, literals)) => {
      assert_eq(next_pos, 90)
      assert_eq(literals.length(), 265)
      assert_true(prev_huf_valid.val)
    }
    Err(_) => fail("expected successful literals decode")
  }
}

///|
test "decode FSE-compressed Huffman weights stream" {
  let frame = b"\x28\xb5\x2f\xfd\x24\x40\x55\x01\x00\x02\x84\x09\x05\x30\xfa\x36\x64\x0b\x57\x73\x78\x62\x90\x58\x55\xcd\x78\x86\xdc\xa9\xfd\xe8\x84\x40\x94\xe7\xdd\x3a\xc3\x8c\x64\x99\xf9\xbb\xfa\xb9\x4e\xb9\xcc\x01\x00\x6b\x71\xa5\xdd"
  let h = try? read_fse_ncount_header(
    frame, 13, 18, huf_max_nb_bits, huf_weight_fse_table_log_max,
  )
  match h {
    Ok((header_size, table_log, max_symbol, normalized_counter)) => {
      let t = try? build_fse_symbol_decode_table(
        normalized_counter, max_symbol, table_log,
      )
      match t {
        Ok((next_state, nb_bits, symbols)) => {
          let payload_start = 13 + header_size
          let d = try? decode_fse_symbol_stream_reverse(
            frame, payload_start, 18, table_log, next_state, nb_bits, symbols, 255,
          )
          match d {
            Ok(weights) =>
              assert_eq(weights, [1, 2, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1])
            Err(_) => fail("decode_fse_symbol_stream_reverse failed")
          }
        }
        Err(_) => fail("build_fse_symbol_decode_table failed")
      }
    }
    Err(_) => fail("read_fse_ncount_header failed")
  }
}

///|
test "decode literals section with FSE-compressed Huffman tree description" {
  let frame = b"\x28\xb5\x2f\xfd\x24\x40\x55\x01\x00\x02\x84\x09\x05\x30\xfa\x36\x64\x0b\x57\x73\x78\x62\x90\x58\x55\xcd\x78\x86\xdc\xa9\xfd\xe8\x84\x40\x94\xe7\xdd\x3a\xc3\x8c\x64\x99\xf9\xbb\xfa\xb9\x4e\xb9\xcc\x01\x00\x6b\x71\xa5\xdd"
  let prev_huf_valid : Ref[Bool] = { val: false }
  let prev_huf_max_bits : Ref[Int] = { val: 0 }
  let prev_huf_left : Ref[Array[Int]] = { val: Array::new() }
  let prev_huf_right : Ref[Array[Int]] = { val: Array::new() }
  let prev_huf_symbol : Ref[Array[Int]] = { val: Array::new() }
  let result = try? decode_literals_section_minimal(
    frame, 9, 51, prev_huf_valid, prev_huf_max_bits, prev_huf_left, prev_huf_right,
    prev_huf_symbol,
  )
  match result {
    Ok((next_pos, literals)) => {
      assert_eq(next_pos, 50)
      assert_eq(literals.length(), 64)
    }
    Err(_) => fail("expected literals decode success")
  }
}

///|
test "read Huffman tree description with FSE-compressed weights" {
  let frame = b"\x28\xb5\x2f\xfd\x24\x40\x55\x01\x00\x02\x84\x09\x05\x30\xfa\x36\x64\x0b\x57\x73\x78\x62\x90\x58\x55\xcd\x78\x86\xdc\xa9\xfd\xe8\x84\x40\x94\xe7\xdd\x3a\xc3\x8c\x64\x99\xf9\xbb\xfa\xb9\x4e\xb9\xcc\x01\x00\x6b\x71\xa5\xdd"
  let result = try? read_huffman_tree_description(frame, 12, 50)
  match result {
    Ok((tree_size, _, _, _, _)) => assert_eq(tree_size, 6)
    Err(_) => fail("expected tree description decode success")
  }
}

///|
test "offset code 31 is supported in base calculation" {
  assert_eq(offset_base_from_code(31), 2147483645)
  let result = try? offset_base_from_code(32)
  assert_true(result is Err(CorruptionDetected))
}

///|
test "invalid LL and ML code ranges are treated as corruption" {
  let ll_result = try? literal_length_base_bits(36)
  assert_true(ll_result is Err(CorruptionDetected))
  let ml_result = try? match_length_base_bits(53)
  assert_true(ml_result is Err(CorruptionDetected))
}

///|
fn wb_standard_dictionary_fixture_dictionary() -> Bytes {
  b"\x37\xa4\x30\xec\xdb\xc3\xd0\x3f\x2d\x10\x90\x1d\x3a\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x40\x31\xdb\x14\xb3\x4d\x31\xdb\x14\x1b\xb7\x94\x52\xca\x24\xf5\x15\xa5\x5e" +
  b"\x51\xea\x15\xa5\xde\xfb\xa3\x04\x00\x00\x00\x2b\xd4\x9c\x00\x00\x00\x34\x60\xc0\x80\x1e\x44\x12\x06\x06\x06\x06\x7a\x06\x08\x06\x98\x06\x83\xc1\x60\x30\x18\x0c\x06\x83\xc1\xcf\x60\x30\x18\x0c" +
  b"\x06\xc8\x31\x26\x32\xc6\xcc\xcc\xcc\xcc\xb6\x0d\x44\xf3\xca\x36\x0c\xc3\x30\xc6\x18\x63\x8c\x31\xc6\x18\x63\x8c\x31\x33\x33\x33\xb3\x6d\x03\x01\x00\x00\x00\x04\x00\x00\x00\x08\x00\x00\x00" +
  b"\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x61\x62\x63\x64\x65\x66"
}

///|
fn wb_standard_dictionary_fixture_frame() -> Bytes {
  b"\x28\xb5\x2f\xfd\x23\xdb\xc3\xd0\x3f\x03\x3d\x00\x00\x00\x01\x54\x00\x04\x00\x13"
}

///|
fn wb_seeded_mode2_payload_from_state(state : DictionaryState) -> Bytes {
  let out : Array[Byte] = Array::new()
  out.push((0 : UInt).to_byte()) // raw literals, empty
  out.push((1 : UInt).to_byte()) // sequence count
  out.push((0xA8 : UInt).to_byte()) // all mode2 sequence sources
  append_bytes(out, state.ll_header, 0, state.ll_header.length())
  append_bytes(out, state.off_header, 0, state.off_header.length())
  append_bytes(out, state.ml_header, 0, state.ml_header.length())
  out.push((1 : UInt).to_byte()) // reverse bitstream terminator
  Bytes::from_array(out)
}

///|
test "parse standard dictionary fixture state" {
  let dict = wb_standard_dictionary_fixture_dictionary()
  let result = try? parse_dictionary_state(dict)
  match result {
    Ok(state) => {
      assert_true(state.has_dictionary)
      assert_eq(state.dict_id, (0x3FD0C3DB : UInt))
      assert_true(state.history.length() > 0)
      assert_true(state.huf_valid)
      assert_true(state.ll_valid)
      assert_true(state.off_valid)
      assert_true(state.ml_valid)
      assert_true(state.huf_tree_desc.length() > 0)
      assert_true(state.ll_header.length() > 0)
      assert_true(state.off_header.length() > 0)
      assert_true(state.ml_header.length() > 0)
      assert_eq(state.rep1, 1)
      assert_eq(state.rep2, 4)
      assert_eq(state.rep3, 8)
    }
    Err(_) => fail("expected dictionary parser success")
  }
}

///|
test "seeded payload chooser prefers candidate with smaller rewritten size" {
  let parsed = try? parse_dictionary_state(
    wb_standard_dictionary_fixture_dictionary(),
  )
  let state = match parsed {
    Ok(v) => v
    Err(_) => fail("parse_dictionary_state failed")
  }
  let payload_pref = b"\x00\x01\x54\x01\x02\x03\x01"
  let candidate_mode2 = wb_seeded_mode2_payload_from_state(state)
  let chosen = choose_seeded_best_payload(
    payload_pref,
    b"",
    b"",
    candidate_mode2,
    b"",
    b"",
    b"",
    b"",
    false,
    (0 : UInt),
    (0 : UInt),
    (0 : UInt),
    false,
    true,
    state.ll_header,
    state.off_header,
    state.ml_header,
    false,
    b"",
  )
  assert_eq(chosen, candidate_mode2)
}

///|
test "dictionary sequence headers can seed repeat-mode rewrite for first payload" {
  let parsed = try? parse_dictionary_state(
    wb_standard_dictionary_fixture_dictionary(),
  )
  let state = match parsed {
    Ok(v) => v
    Err(_) => fail("parse_dictionary_state failed")
  }
  let payload_arr : Array[Byte] = Array::new()
  payload_arr.push((0 : UInt).to_byte()) // raw literals, empty
  payload_arr.push((1 : UInt).to_byte()) // sequence count = 1
  payload_arr.push((0xA8 : UInt).to_byte()) // all mode2 sequence sources
  append_bytes(payload_arr, state.ll_header, 0, state.ll_header.length())
  append_bytes(payload_arr, state.off_header, 0, state.off_header.length())
  append_bytes(payload_arr, state.ml_header, 0, state.ml_header.length())
  payload_arr.push((1 : UInt).to_byte()) // reverse bitstream terminator byte
  let payload = Bytes::from_array(payload_arr)

  let prev_rle_valid : Ref[Bool] = { val: false }
  let prev_ll_code : Ref[UInt] = { val: 0 }
  let prev_off_code : Ref[UInt] = { val: 0 }
  let prev_ml_code : Ref[UInt] = { val: 0 }
  let prev_predefined_valid : Ref[Bool] = { val: false }
  let prev_compressed_valid : Ref[Bool] = { val: true }
  let prev_ll_header : Ref[Bytes] = { val: state.ll_header }
  let prev_off_header : Ref[Bytes] = { val: state.off_header }
  let prev_ml_header : Ref[Bytes] = { val: state.ml_header }
  let rewritten = maybe_rewrite_sequence_modes_to_repeat(
    payload, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
    prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
  )
  let modes_pos = payload_sequence_modes_offset(rewritten)
  assert_true(modes_pos >= 0)
  assert_eq(rewritten[modes_pos].to_uint(), 0xFC)
  assert_eq(
    rewritten.length(),
    payload.length() -
    state.ll_header.length() -
    state.off_header.length() -
    state.ml_header.length(),
  )
}

///|
test "dictionary Huffman tree can seed treeless literals rewrite for first payload" {
  let parsed = try? parse_dictionary_state(
    wb_standard_dictionary_fixture_dictionary(),
  )
  let state = match parsed {
    Ok(v) => v
    Err(_) => fail("parse_dictionary_state failed")
  }
  let lit_size = 1
  let lit_c_size = state.huf_tree_desc.length() + 1
  let header : UInt = ((lit_size.reinterpret_as_uint() & 0x3FF) << 4) +
    ((lit_c_size.reinterpret_as_uint() & 0x3FF) << 14) +
    2
  let payload_arr : Array[Byte] = Array::new()
  append_u24_le(payload_arr, header)
  append_bytes(
    payload_arr,
    state.huf_tree_desc,
    0,
    state.huf_tree_desc.length(),
  )
  payload_arr.push((1 : UInt).to_byte()) // synthetic compressed literal bitstream
  payload_arr.push((0 : UInt).to_byte()) // sequence count = 0
  let payload = Bytes::from_array(payload_arr)

  let prev_huf_valid : Ref[Bool] = { val: true }
  let prev_huf_tree_desc : Ref[Bytes] = { val: state.huf_tree_desc }
  let rewritten = rewrite_literals_section_to_treeless_if_repeat(
    payload, prev_huf_valid, prev_huf_tree_desc,
  )
  assert_eq(rewritten[0].to_uint() & 0x3, 3)
  assert_eq(rewritten.length(), payload.length() - state.huf_tree_desc.length())
}

///|
test "standard dictionary internal paths comparison" {
  let dict = wb_standard_dictionary_fixture_dictionary()
  let frame = wb_standard_dictionary_fixture_frame()
  let parsed_state = try? parse_dictionary_state(dict)
  let state = match parsed_state {
    Ok(v) => v
    Err(_) => fail("parse_dictionary_state failed")
  }

  let out_history : Array[Byte] = Array::new()
  let history_result = try? decode_frame_into_with_history(
    frame,
    0,
    out_history,
    state.history,
  )
  let out_dict : Array[Byte] = Array::new()
  let dict_result = try? decode_frame_into_with_dictionary(
    frame, 0, out_dict, dict,
  )
  assert_true(dict_result is Ok(_))
  assert_true(history_result is Ok(_))
}

///|
test "real dictionary-compressed frame parses sequence header states" {
  let dict = b"\x37\xa4\x30\xec\xdb\xc3\xd0\x3f\x2d\x10\x90\x1d\x3a\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x00\x0c\x40\x31\xdb\x14\xb3\x4d\x31\xdb\x14\x1b\xb7\x94\x52\xca\x24\xf5\x15\xa5\x5e" +
    b"\x51\xea\x15\xa5\xde\xfb\xa3\x04\x00\x00\x00\x2b\xd4\x9c\x00\x00\x00\x34\x60\xc0\x80\x1e\x44\x12\x06\x06\x06\x06\x7a\x06\x08\x06\x98\x06\x83\xc1\x60\x30\x18\x0c\x06\x83\xc1\xcf\x60\x30\x18\x0c" +
    b"\x06\xc8\x31\x26\x32\xc6\xcc\xcc\xcc\xcc\xb6\x0d\x44\xf3\xca\x36\x0c\xc3\x30\xc6\x18\x63\x8c\x31\xc6\x18\x63\x8c\x31\x33\x33\x33\xb3\x6d\x03\x01\x00\x00\x00\x04\x00\x00\x00\x08\x00\x00\x00\x6b" +
    b"\x65\x6e\x2d\x34\x36\x20\x72\x65\x70\x65\x61\x74\x65\x64\x20\x61\x6c\x70\x68\x61\x20\x62\x65\x74\x61\x20\x67\x61\x6d\x6d\x61\x20\x73\x65\x63\x74\x69\x6f\x6e\x2d\x30\x31\x20\x61\x6e\x64\x20\x65" +
    b"\x78\x6b\x65\x6e\x2d\x33\x39\x20\x72\x65\x70\x65\x61\x74\x65\x64\x20\x61\x6c\x70\x68\x61\x20\x62\x65\x74\x61\x20\x67\x61\x6d\x6d\x61\x20\x73\x65\x63\x74\x69\x6f\x6e\x2d\x30\x33\x20\x61\x6e\x64" +
    b"\x20\x65\x78\x74\x69\x6f\x6e\x61\x72\x79\x20\x73\x74\x61\x62\x69"
  let block = b"\xf4\x02\x63\x6f\x6d\x70\x72\x65\x73\x73\x20\x77\x69\x74\x68\x20\x64\x69\x63\x61\x6d\x70\x6c\x65\x20\x70\x61\x79\x6c\x6f\x61\x74\x6f\x6b\x65\x6e\x2d\x30\x35\x35\x72\x61\x20\x77\x6f\x72\x64\x73\x0a\x04\xfc\x62\x8f\x80\xca\x2a\x9b\x8c\x5e\x67\x87\xf3\xc1\xcb\x02"
  let parsed_state = try? parse_dictionary_state(dict)
  let state = match parsed_state {
    Ok(v) => v
    Err(_) => fail("parse_dictionary_state failed")
  }

  let prev_huf_valid : Ref[Bool] = { val: state.huf_valid }
  let prev_huf_max_bits : Ref[Int] = { val: state.huf_max_bits }
  let prev_huf_left : Ref[Array[Int]] = { val: state.huf_left }
  let prev_huf_right : Ref[Array[Int]] = { val: state.huf_right }
  let prev_huf_symbol : Ref[Array[Int]] = { val: state.huf_symbol }
  let lit = try? decode_literals_section_minimal(
    block,
    0,
    block.length(),
    prev_huf_valid,
    prev_huf_max_bits,
    prev_huf_left,
    prev_huf_right,
    prev_huf_symbol,
  )
  let (seq_pos0, literals) = match lit {
    Ok(v) => v
    Err(_) => fail("decode_literals_section_minimal failed")
  }
  let seq_cnt = try? parse_sequence_count(block, seq_pos0, block.length())
  let (number_of_sequences, seq_pos0_end) = match seq_cnt {
    Ok(v) => v
    Err(_) => fail("parse_sequence_count failed")
  }
  let modes = block[seq_pos0_end].to_uint()
  let ll_mode = (modes >> 6) & 0x3
  let off_mode = (modes >> 4) & 0x3
  let ml_mode = (modes >> 2) & 0x3
  assert_eq(ll_mode, (3 : UInt))
  assert_eq(off_mode, (3 : UInt))
  assert_eq(ml_mode, (3 : UInt))

  let prev_ll_valid : Ref[Bool] = { val: state.ll_valid }
  let prev_ll_kind : Ref[Int] = { val: state.ll_kind }
  let prev_ll_code : Ref[UInt] = { val: state.ll_code }
  let prev_ll_table_log : Ref[Int] = { val: state.ll_table_log }
  let prev_ll_table_next_state : Ref[Array[Int]] = {
    val: state.ll_table_next_state,
  }
  let prev_ll_table_nb_add_bits : Ref[Array[Int]] = {
    val: state.ll_table_nb_add_bits,
  }
  let prev_ll_table_nb_bits : Ref[Array[Int]] = { val: state.ll_table_nb_bits }
  let prev_ll_table_base_values : Ref[Array[Int]] = {
    val: state.ll_table_base_values,
  }
  let prev_off_valid : Ref[Bool] = { val: state.off_valid }
  let prev_off_kind : Ref[Int] = { val: state.off_kind }
  let prev_off_code : Ref[UInt] = { val: state.off_code }
  let prev_off_table_log : Ref[Int] = { val: state.off_table_log }
  let prev_off_table_next_state : Ref[Array[Int]] = {
    val: state.off_table_next_state,
  }
  let prev_off_table_nb_add_bits : Ref[Array[Int]] = {
    val: state.off_table_nb_add_bits,
  }
  let prev_off_table_nb_bits : Ref[Array[Int]] = {
    val: state.off_table_nb_bits,
  }
  let prev_off_table_base_values : Ref[Array[Int]] = {
    val: state.off_table_base_values,
  }
  let prev_ml_valid : Ref[Bool] = { val: state.ml_valid }
  let prev_ml_kind : Ref[Int] = { val: state.ml_kind }
  let prev_ml_code : Ref[UInt] = { val: state.ml_code }
  let prev_ml_table_log : Ref[Int] = { val: state.ml_table_log }
  let prev_ml_table_next_state : Ref[Array[Int]] = {
    val: state.ml_table_next_state,
  }
  let prev_ml_table_nb_add_bits : Ref[Array[Int]] = {
    val: state.ml_table_nb_add_bits,
  }
  let prev_ml_table_nb_bits : Ref[Array[Int]] = { val: state.ml_table_nb_bits }
  let prev_ml_table_base_values : Ref[Array[Int]] = {
    val: state.ml_table_base_values,
  }

  let seq_pos_ref : Ref[Int] = { val: seq_pos0_end + 1 }
  let ll_src = try? decode_sequence_source(
    block,
    block.length(),
    seq_pos_ref,
    ll_mode,
    prev_ll_valid,
    prev_ll_kind,
    prev_ll_code,
    prev_ll_table_log,
    prev_ll_table_next_state,
    prev_ll_table_nb_add_bits,
    prev_ll_table_nb_bits,
    prev_ll_table_base_values,
    sequence_symbol_literal_length,
  )
  let off_src = try? decode_sequence_source(
    block,
    block.length(),
    seq_pos_ref,
    off_mode,
    prev_off_valid,
    prev_off_kind,
    prev_off_code,
    prev_off_table_log,
    prev_off_table_next_state,
    prev_off_table_nb_add_bits,
    prev_off_table_nb_bits,
    prev_off_table_base_values,
    sequence_symbol_offset,
  )
  let ml_src = try? decode_sequence_source(
    block,
    block.length(),
    seq_pos_ref,
    ml_mode,
    prev_ml_valid,
    prev_ml_kind,
    prev_ml_code,
    prev_ml_table_log,
    prev_ml_table_next_state,
    prev_ml_table_nb_add_bits,
    prev_ml_table_nb_bits,
    prev_ml_table_base_values,
    sequence_symbol_match_length,
  )
  assert_true(ll_src is Ok(_))
  assert_true(off_src is Ok(_))
  assert_true(ml_src is Ok(_))

  let br_start = seq_pos_ref.val
  let br_byte : Ref[Int] = { val: block.length() - 1 }
  let br_bit : Ref[Int] = { val: -1 }
  init_reverse_bit_reader(block, br_start, br_byte, br_bit)

  let ll_state = try? init_fse_state_reverse(
    block,
    br_start,
    br_byte,
    br_bit,
    prev_ll_table_log.val,
  )
  let off_state = try? init_fse_state_reverse(
    block,
    br_start,
    br_byte,
    br_bit,
    prev_off_table_log.val,
  )
  let ml_state = try? init_fse_state_reverse(
    block,
    br_start,
    br_byte,
    br_bit,
    prev_ml_table_log.val,
  )
  assert_true(ll_state is Ok(_))
  assert_true(off_state is Ok(_))
  assert_true(ml_state is Ok(_))
  let (ll_kind, ll_code) = match ll_src {
    Ok(v) => v
    Err(_) => fail("ll_src failed")
  }
  let (off_kind, off_code) = match off_src {
    Ok(v) => v
    Err(_) => fail("off_src failed")
  }
  let (ml_kind, ml_code) = match ml_src {
    Ok(v) => v
    Err(_) => fail("ml_src failed")
  }
  let ll_state_v = match ll_state {
    Ok(v) => v
    Err(_) => fail("ll_state failed")
  }
  let off_state_v = match off_state {
    Ok(v) => v
    Err(_) => fail("off_state failed")
  }
  let ml_state_v = match ml_state {
    Ok(v) => v
    Err(_) => fail("ml_state failed")
  }
  let ll_entry_result = try? sequence_symbol_entry(
    ll_kind,
    ll_code,
    ll_state_v,
    prev_ll_table_next_state.val,
    prev_ll_table_nb_add_bits.val,
    prev_ll_table_nb_bits.val,
    prev_ll_table_base_values.val,
    sequence_symbol_literal_length,
  )
  let ml_entry_result = try? sequence_symbol_entry(
    ml_kind,
    ml_code,
    ml_state_v,
    prev_ml_table_next_state.val,
    prev_ml_table_nb_add_bits.val,
    prev_ml_table_nb_bits.val,
    prev_ml_table_base_values.val,
    sequence_symbol_match_length,
  )
  let off_entry_result = try? sequence_symbol_entry(
    off_kind,
    off_code,
    off_state_v,
    prev_off_table_next_state.val,
    prev_off_table_nb_add_bits.val,
    prev_off_table_nb_bits.val,
    prev_off_table_base_values.val,
    sequence_symbol_offset,
  )
  assert_true(ll_entry_result is Ok(_))
  assert_true(ml_entry_result is Ok(_))
  assert_true(off_entry_result is Ok(_))
  let (_, ll_nb_add_bits, _, ll_base) = match ll_entry_result {
    Ok(v) => v
    Err(_) => fail("ll entry failed")
  }
  let (_, ml_nb_add_bits, _, ml_base) = match ml_entry_result {
    Ok(v) => v
    Err(_) => fail("ml entry failed")
  }
  let (_, off_nb_add_bits, _, off_base) = match off_entry_result {
    Ok(v) => v
    Err(_) => fail("off entry failed")
  }
  let ll0 = ll_base == 0
  let first_offset = if off_nb_add_bits > 1 {
    let off_extra_result = try? read_reverse_bits(
      block, br_start, br_byte, br_bit, off_nb_add_bits,
    )
    let off_extra = match off_extra_result {
      Ok(v) => v
      Err(_) => fail("off extra failed")
    }
    off_base + off_extra.reinterpret_as_int()
  } else if off_nb_add_bits == 0 {
    if ll0 {
      state.rep2
    } else {
      state.rep1
    }
  } else {
    let low_result = try? read_reverse_bits(block, br_start, br_byte, br_bit, 1)
    let low = match low_result {
      Ok(v) => v.reinterpret_as_int()
      Err(_) => fail("off short extra failed")
    }
    let idx = off_base + (if ll0 { 1 } else { 0 }) + low
    if idx == 1 {
      state.rep1
    } else if idx == 2 {
      state.rep2
    } else if idx == 3 {
      state.rep1 - 1
    } else {
      fail("invalid short rep idx")
    }
  }
  let ml_extra = if ml_nb_add_bits == 0 {
    (0 : UInt)
  } else {
    let ml_extra_result = try? read_reverse_bits(
      block, br_start, br_byte, br_bit, ml_nb_add_bits,
    )
    match ml_extra_result {
      Ok(v) => v
      Err(_) => fail("ml extra failed")
    }
  }
  let ll_extra = if ll_nb_add_bits == 0 {
    (0 : UInt)
  } else {
    let ll_extra_result = try? read_reverse_bits(
      block, br_start, br_byte, br_bit, ll_nb_add_bits,
    )
    match ll_extra_result {
      Ok(v) => v
      Err(_) => fail("ll extra failed")
    }
  }
  let first_lit_len = ll_base + ll_extra.reinterpret_as_int()
  let first_match_len = ml_base + ml_extra.reinterpret_as_int()
  assert_true(first_lit_len >= 0)
  assert_true(first_match_len > 0)
  assert_true(first_offset > 0)
  if first_offset > first_lit_len + state.history.length() {
    fail(
      "first_offset=" +
      first_offset.to_string() +
      " first_lit_len=" +
      first_lit_len.to_string() +
      " history=" +
      state.history.length().to_string() +
      " off_nb_add_bits=" +
      off_nb_add_bits.to_string() +
      " off_base=" +
      off_base.to_string() +
      " ll_nb_add_bits=" +
      ll_nb_add_bits.to_string() +
      " ll_base=" +
      ll_base.to_string() +
      " ml_nb_add_bits=" +
      ml_nb_add_bits.to_string() +
      " ml_base=" +
      ml_base.to_string(),
    )
  }
  ignore(number_of_sequences)
  ignore(literals)
}

///|
test "dictionary single-match search limit controls long-distance visibility" {
  let dict = Bytes::makei(512, i => {
    let x = i.reinterpret_as_uint() * (2654435761 : UInt) + (2246822519 : UInt)
    (128 + ((x >> 16) & 0x7F).reinterpret_as_int())
    .reinterpret_as_uint()
    .to_byte()
  })
  let prefix = Bytes::makei(9000, i => {
    let x = i.reinterpret_as_uint() * (1103515245 : UInt) + (12345 : UInt)
    ((x >> 16) & 0x7F).to_byte()
  })
  let tail = dict[120:440].to_bytes()
  let src = prefix + tail
  let (ll_short, off_short, ml_short) = detect_best_single_match_with_dictionary_history(
    src,
    0,
    src.length(),
    dict,
    search_limit=8192,
  )
  let (ll_long, off_long, ml_long) = detect_best_single_match_with_dictionary_history(
    src,
    0,
    src.length(),
    dict,
    search_limit=32768,
  )
  if ml_short >= 3 {
    assert_true(off_short <= ll_short)
  }
  assert_true(ml_long >= 300)
  assert_true(off_long > ll_long)
}

///|
test "dictionary single-match wide search reaches matches beyond fixed 32768 prefix" {
  let dict = Bytes::makei(1024, i => {
    let x = i.reinterpret_as_uint() * (2246822519 : UInt) + (2654435761 : UInt)
    (128 + ((x >> 16) & 0x7F).reinterpret_as_int())
    .reinterpret_as_uint()
    .to_byte()
  })
  let prefix = Bytes::makei(70000, i => {
    let x = i.reinterpret_as_uint() * (1103515245 : UInt) + (12345 : UInt)
    ((x >> 24) & 0x7F).to_byte()
  })
  let tail = dict[200:520].to_bytes()
  let src = prefix + tail

  let (_, _, ml_narrow) = detect_best_single_match_with_dictionary_history(
    src,
    0,
    src.length(),
    dict,
    search_limit=32768,
    allow_internal=false,
  )
  let (ll_wide, off_wide, ml_wide) = detect_best_single_match_with_dictionary_history(
    src,
    0,
    src.length(),
    dict,
    search_limit=src.length(),
    allow_internal=false,
  )
  assert_true(ml_narrow < 3)
  assert_true(ml_wide >= 300)
  assert_true(off_wide > ll_wide)
}

///|
test "hash-chain single-match search can find offsets beyond 2048" {
  let lead = Bytes::makei(6000, i => {
    let x = i.reinterpret_as_uint() * (1664525 : UInt) + (1013904223 : UInt)
    ((x >> 24) & 0xFF).to_byte()
  })
  let repeated = lead[900:1600].to_bytes()
  let gap = Bytes::makei(2600, i => {
    let x = i.reinterpret_as_uint() * (22695477 : UInt) + (1 : UInt)
    ((x >> 23) & 0xFF).to_byte()
  })
  let src = lead + gap + repeated + b"tail"
  let (ll, offset, ml) = detect_best_single_match(
    src,
    0,
    src.length(),
    search_limit=src.length(),
    search_depth=64,
  )
  assert_true(ml >= 680)
  assert_true(offset > 2048)
  assert_true(offset <= ll)
}

///|
test "single-match search depth grows with level and long-distance mode" {
  assert_true(
    level_single_match_search_depth(22, false) >
    level_single_match_search_depth(10, false),
  )
  assert_true(
    level_single_match_search_depth(18, true) >
    level_single_match_search_depth(18, false),
  )
}

///|
test "dictionary multi-candidate chain can recover longer older match" {
  let dict_head = b"ABCD1234567890abcdefghijklmnop"
  let dict_gap = Bytes::makei(96, i => {
    let x = i.reinterpret_as_uint() * (1103515245 : UInt) + (12345 : UInt)
    ((x >> 16) & 0xFF).to_byte()
  })
  let dict_tail = b"ABCDz"
  let dict = dict_head + dict_gap + dict_tail
  let src = b"xxABCD1234567890abcdefghijklmnop-tail"
  let (ll, offset, ml) = detect_best_single_match_with_dictionary_history(
    src,
    0,
    src.length(),
    dict,
    search_limit=src.length(),
    search_depth=64,
    allow_internal=false,
  )
  assert_eq(ll, 2)
  assert_true(ml >= dict_head.length())
  assert_true(offset > dict.length() - dict_tail.length())
}

///|
test "dictionary match can continue beyond dictionary bytes via virtual prefix" {
  let dict = b"abcde"
  let src = b"abcdeabcdeabcdeXYZ"
  let (ll, offset, ml) = detect_best_single_match_with_dictionary_history(
    src,
    0,
    src.length(),
    dict,
    search_limit=src.length(),
    search_depth=64,
    allow_internal=false,
  )
  assert_eq(ll, 0)
  assert_eq(offset, dict.length())
  assert_true(ml >= 15)
}

///|
test "level policy enables richer candidates only for sufficiently large blocks" {
  assert_true(!prefer_compressed_fse_candidate(21, 512))
  assert_true(prefer_compressed_fse_candidate(21, 1400))
  assert_true(!prefer_mixed_candidate(19, 512))
  assert_true(prefer_mixed_candidate(19, 900))
  assert_true(!prefer_periodic_candidate(17, 128))
  assert_true(prefer_periodic_candidate(17, 512))
}

///|
test "sequence cap policy is bounded by block length" {
  assert_true(general_rle_sequence_cap(20, 30) <= 10)
  assert_true(compressed_fse_sequence_cap(20, 24) <= 8)
  assert_true(mixed_sequence_cap(22, 18) <= 6)
  assert_true(predefined_multi_sequence_cap(20, 15) <= 5)
}
