///|
fn rewrite_payload_with_seed_snapshot(
  payload : Bytes,
  seed_rle_valid : Bool,
  seed_ll_code : UInt,
  seed_off_code : UInt,
  seed_ml_code : UInt,
  seed_predefined_valid : Bool,
  seed_compressed_valid : Bool,
  seed_ll_header : Bytes,
  seed_off_header : Bytes,
  seed_ml_header : Bytes,
  seed_lit_huf_valid : Bool,
  seed_lit_huf_tree_desc : Bytes,
) -> Bytes {
  if payload.length() == 0 {
    return b""
  }
  let prev_rle_valid : Ref[Bool] = { val: seed_rle_valid }
  let prev_ll_code : Ref[UInt] = { val: seed_ll_code }
  let prev_off_code : Ref[UInt] = { val: seed_off_code }
  let prev_ml_code : Ref[UInt] = { val: seed_ml_code }
  let prev_predefined_valid : Ref[Bool] = { val: seed_predefined_valid }
  let prev_compressed_valid : Ref[Bool] = { val: seed_compressed_valid }
  let prev_ll_header : Ref[Bytes] = { val: seed_ll_header }
  let prev_off_header : Ref[Bytes] = { val: seed_off_header }
  let prev_ml_header : Ref[Bytes] = { val: seed_ml_header }
  let prev_lit_huf_valid : Ref[Bool] = { val: seed_lit_huf_valid }
  let prev_lit_huf_tree_desc : Ref[Bytes] = { val: seed_lit_huf_tree_desc }
  let payload0 = maybe_rewrite_sequence_modes_to_repeat(
    payload, prev_rle_valid, prev_ll_code, prev_off_code, prev_ml_code, prev_predefined_valid,
    prev_compressed_valid, prev_ll_header, prev_off_header, prev_ml_header,
  )
  rewrite_literals_section_to_treeless_if_repeat(
    payload0, prev_lit_huf_valid, prev_lit_huf_tree_desc,
  )
}

///|
fn consider_seeded_payload_candidate(
  candidate : Bytes,
  best_raw : Ref[Bytes],
  best_preview : Ref[Bytes],
  seed_rle_valid : Bool,
  seed_ll_code : UInt,
  seed_off_code : UInt,
  seed_ml_code : UInt,
  seed_predefined_valid : Bool,
  seed_compressed_valid : Bool,
  seed_ll_header : Bytes,
  seed_off_header : Bytes,
  seed_ml_header : Bytes,
  seed_lit_huf_valid : Bool,
  seed_lit_huf_tree_desc : Bytes,
) -> Unit {
  if candidate.length() == 0 {
    return
  }
  let preview = rewrite_payload_with_seed_snapshot(
    candidate, seed_rle_valid, seed_ll_code, seed_off_code, seed_ml_code, seed_predefined_valid,
    seed_compressed_valid, seed_ll_header, seed_off_header, seed_ml_header, seed_lit_huf_valid,
    seed_lit_huf_tree_desc,
  )
  if preview.length() == 0 {
    return
  }
  if best_preview.val.length() == 0 ||
    preview.length() < best_preview.val.length() ||
    (
      preview.length() == best_preview.val.length() &&
      candidate.length() < best_raw.val.length()
    ) {
    best_raw.val = candidate
    best_preview.val = preview
  }
}

///|
fn choose_seeded_best_payload(
  payload_pref : Bytes,
  periodic_payload : Bytes,
  predefined_payload : Bytes,
  compressed_fse_payload : Bytes,
  mixed_payload : Bytes,
  single_payload : Bytes,
  general_payload : Bytes,
  literals_only_payload : Bytes,
  seed_rle_valid : Bool,
  seed_ll_code : UInt,
  seed_off_code : UInt,
  seed_ml_code : UInt,
  seed_predefined_valid : Bool,
  seed_compressed_valid : Bool,
  seed_ll_header : Bytes,
  seed_off_header : Bytes,
  seed_ml_header : Bytes,
  seed_lit_huf_valid : Bool,
  seed_lit_huf_tree_desc : Bytes,
) -> Bytes {
  let best_raw : Ref[Bytes] = { val: b"" }
  let best_preview : Ref[Bytes] = { val: b"" }
  consider_seeded_payload_candidate(
    payload_pref, best_raw, best_preview, seed_rle_valid, seed_ll_code, seed_off_code,
    seed_ml_code, seed_predefined_valid, seed_compressed_valid, seed_ll_header, seed_off_header,
    seed_ml_header, seed_lit_huf_valid, seed_lit_huf_tree_desc,
  )
  consider_seeded_payload_candidate(
    compressed_fse_payload, best_raw, best_preview, seed_rle_valid, seed_ll_code,
    seed_off_code, seed_ml_code, seed_predefined_valid, seed_compressed_valid, seed_ll_header,
    seed_off_header, seed_ml_header, seed_lit_huf_valid, seed_lit_huf_tree_desc,
  )
  consider_seeded_payload_candidate(
    mixed_payload, best_raw, best_preview, seed_rle_valid, seed_ll_code, seed_off_code,
    seed_ml_code, seed_predefined_valid, seed_compressed_valid, seed_ll_header, seed_off_header,
    seed_ml_header, seed_lit_huf_valid, seed_lit_huf_tree_desc,
  )
  consider_seeded_payload_candidate(
    periodic_payload, best_raw, best_preview, seed_rle_valid, seed_ll_code, seed_off_code,
    seed_ml_code, seed_predefined_valid, seed_compressed_valid, seed_ll_header, seed_off_header,
    seed_ml_header, seed_lit_huf_valid, seed_lit_huf_tree_desc,
  )
  consider_seeded_payload_candidate(
    single_payload, best_raw, best_preview, seed_rle_valid, seed_ll_code, seed_off_code,
    seed_ml_code, seed_predefined_valid, seed_compressed_valid, seed_ll_header, seed_off_header,
    seed_ml_header, seed_lit_huf_valid, seed_lit_huf_tree_desc,
  )
  consider_seeded_payload_candidate(
    general_payload, best_raw, best_preview, seed_rle_valid, seed_ll_code, seed_off_code,
    seed_ml_code, seed_predefined_valid, seed_compressed_valid, seed_ll_header, seed_off_header,
    seed_ml_header, seed_lit_huf_valid, seed_lit_huf_tree_desc,
  )
  consider_seeded_payload_candidate(
    predefined_payload, best_raw, best_preview, seed_rle_valid, seed_ll_code, seed_off_code,
    seed_ml_code, seed_predefined_valid, seed_compressed_valid, seed_ll_header, seed_off_header,
    seed_ml_header, seed_lit_huf_valid, seed_lit_huf_tree_desc,
  )
  consider_seeded_payload_candidate(
    literals_only_payload, best_raw, best_preview, seed_rle_valid, seed_ll_code,
    seed_off_code, seed_ml_code, seed_predefined_valid, seed_compressed_valid, seed_ll_header,
    seed_off_header, seed_ml_header, seed_lit_huf_valid, seed_lit_huf_tree_desc,
  )
  if best_raw.val.length() > 0 {
    best_raw.val
  } else {
    payload_pref
  }
}
