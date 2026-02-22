///|
fn collect_predefined_offset_candidates_for_context(
  value : Int,
  ll0 : Bool,
  r1 : Int,
  r2 : Int,
  r3 : Int,
  states : Array[Int],
  extras : Array[UInt],
  nb_add_bits : Array[Int],
  next_states : Array[Int],
  nb_state_bits : Array[Int],
  out_r1 : Array[Int],
  out_r2 : Array[Int],
  out_r3 : Array[Int],
) -> Unit raise ZstdError {
  let mut state = 0
  while state <= 31 {
    let (next_state, add_bits, state_bits, base) = of_predefined_entry(state)
    if add_bits > 1 {
      let span = (((1 : UInt64) << add_bits) - (1 : UInt64)).to_int()
      let limit_value = base + span
      if value >= base && value <= limit_value {
        states.push(state)
        extras.push((value - base).reinterpret_as_uint())
        nb_add_bits.push(add_bits)
        next_states.push(next_state)
        nb_state_bits.push(state_bits)
        out_r1.push(value)
        out_r2.push(r1)
        out_r3.push(r2)
      }
    } else if add_bits == 0 {
      let decoded = if ll0 { r2 } else { r1 }
      if decoded == value && decoded > 0 {
        states.push(state)
        extras.push((0 : UInt))
        nb_add_bits.push(0)
        next_states.push(next_state)
        nb_state_bits.push(state_bits)
        out_r1.push(decoded)
        out_r2.push(if ll0 { r1 } else { r2 })
        out_r3.push(r3)
      }
    } else if add_bits == 1 {
      let mut low = 0
      while low <= 1 {
        let offset_code = base + (if ll0 { 1 } else { 0 }) + low
        let (ok, decoded, nr1, nr2, nr3) = if offset_code == 1 {
          (r2 > 0, r2, r2, r1, r3)
        } else if offset_code == 2 {
          (r3 > 0, r3, r3, r1, r2)
        } else if offset_code == 3 {
          let v = r1 - 1
          (v > 0, v, v, r1, r2)
        } else {
          (false, 0, 0, 0, 0)
        }
        if ok && decoded == value {
          states.push(state)
          extras.push(low.reinterpret_as_uint())
          nb_add_bits.push(1)
          next_states.push(next_state)
          nb_state_bits.push(state_bits)
          out_r1.push(nr1)
          out_r2.push(nr2)
          out_r3.push(nr3)
        }
        low = low + 1
      }
    }
    state = state + 1
  }
}

///|
fn offset_candidate_index(
  states : Array[Int],
  extras : Array[UInt],
  nb_add_bits : Array[Int],
  next_states : Array[Int],
  nb_state_bits : Array[Int],
  out_r1 : Array[Int],
  out_r2 : Array[Int],
  out_r3 : Array[Int],
  state : Int,
  extra : UInt,
  add_bits : Int,
  next_state : Int,
  state_bits : Int,
  nr1 : Int,
  nr2 : Int,
  nr3 : Int,
) -> Int {
  let mut i = 0
  while i < states.length() {
    if states[i] == state &&
      extras[i] == extra &&
      nb_add_bits[i] == add_bits &&
      next_states[i] == next_state &&
      nb_state_bits[i] == state_bits &&
      out_r1[i] == nr1 &&
      out_r2[i] == nr2 &&
      out_r3[i] == nr3 {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn select_predefined_offset_state_path(
  off_values : Array[Int],
  ll_values : Array[Int],
  rep1 : Int,
  rep2 : Int,
  rep3 : Int,
) -> (Bool, Array[Int], Array[UInt], Array[Int], Array[Int], Array[Int]) raise ZstdError {
  let n = off_values.length()
  if n <= 0 || ll_values.length() != n {
    return (
      false,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }
  let inf = 1 << 30

  let states_per_pos : Array[Array[Int]] = Array::new()
  let extras_per_pos : Array[Array[UInt]] = Array::new()
  let add_bits_per_pos : Array[Array[Int]] = Array::new()
  let next_states_per_pos : Array[Array[Int]] = Array::new()
  let state_bits_per_pos : Array[Array[Int]] = Array::new()
  let out_r1_per_pos : Array[Array[Int]] = Array::new()
  let out_r2_per_pos : Array[Array[Int]] = Array::new()
  let out_r3_per_pos : Array[Array[Int]] = Array::new()
  let cost_per_pos : Array[Array[Int]] = Array::new()
  let parent_idx_per_pos : Array[Array[Int]] = Array::new()
  let parent_trans_bits_per_pos : Array[Array[Int]] = Array::new()
  let parent_trans_nb_bits_per_pos : Array[Array[Int]] = Array::new()

  // pos = 0
  {
    let states : Array[Int] = Array::new()
    let extras : Array[UInt] = Array::new()
    let add_bits : Array[Int] = Array::new()
    let next_states : Array[Int] = Array::new()
    let state_bits : Array[Int] = Array::new()
    let out_r1 : Array[Int] = Array::new()
    let out_r2 : Array[Int] = Array::new()
    let out_r3 : Array[Int] = Array::new()
    collect_predefined_offset_candidates_for_context(
      off_values[0],
      ll_values[0] == 0,
      rep1,
      rep2,
      rep3,
      states,
      extras,
      add_bits,
      next_states,
      state_bits,
      out_r1,
      out_r2,
      out_r3,
    )
    if states.length() == 0 {
      return (
        false,
        Array::new(),
        Array::new(),
        Array::new(),
        Array::new(),
        Array::new(),
      )
    }
    let costs : Array[Int] = Array::new()
    let parents : Array[Int] = Array::new()
    let trans_bits : Array[Int] = Array::new()
    let trans_nb_bits : Array[Int] = Array::new()
    let mut i = 0
    while i < states.length() {
      costs.push(add_bits[i])
      parents.push(-1)
      trans_bits.push(0)
      trans_nb_bits.push(0)
      i = i + 1
    }
    states_per_pos.push(states)
    extras_per_pos.push(extras)
    add_bits_per_pos.push(add_bits)
    next_states_per_pos.push(next_states)
    state_bits_per_pos.push(state_bits)
    out_r1_per_pos.push(out_r1)
    out_r2_per_pos.push(out_r2)
    out_r3_per_pos.push(out_r3)
    cost_per_pos.push(costs)
    parent_idx_per_pos.push(parents)
    parent_trans_bits_per_pos.push(trans_bits)
    parent_trans_nb_bits_per_pos.push(trans_nb_bits)
  }

  let mut pos = 1
  while pos < n {
    let prev_states = states_per_pos[pos - 1]
    let prev_costs = cost_per_pos[pos - 1]
    let prev_next_states = next_states_per_pos[pos - 1]
    let prev_state_bits = state_bits_per_pos[pos - 1]
    let prev_out_r1 = out_r1_per_pos[pos - 1]
    let prev_out_r2 = out_r2_per_pos[pos - 1]
    let prev_out_r3 = out_r3_per_pos[pos - 1]

    let curr_states : Array[Int] = Array::new()
    let curr_extras : Array[UInt] = Array::new()
    let curr_add_bits : Array[Int] = Array::new()
    let curr_next_states : Array[Int] = Array::new()
    let curr_state_bits : Array[Int] = Array::new()
    let curr_out_r1 : Array[Int] = Array::new()
    let curr_out_r2 : Array[Int] = Array::new()
    let curr_out_r3 : Array[Int] = Array::new()
    let curr_costs : Array[Int] = Array::new()
    let curr_parents : Array[Int] = Array::new()
    let curr_trans_bits : Array[Int] = Array::new()
    let curr_trans_nb_bits : Array[Int] = Array::new()

    let mut p = 0
    while p < prev_states.length() {
      let p_cost = prev_costs[p]
      if p_cost < inf {
        let cand_states : Array[Int] = Array::new()
        let cand_extras : Array[UInt] = Array::new()
        let cand_add_bits : Array[Int] = Array::new()
        let cand_next_states : Array[Int] = Array::new()
        let cand_state_bits : Array[Int] = Array::new()
        let cand_out_r1 : Array[Int] = Array::new()
        let cand_out_r2 : Array[Int] = Array::new()
        let cand_out_r3 : Array[Int] = Array::new()
        collect_predefined_offset_candidates_for_context(
          off_values[pos],
          ll_values[pos] == 0,
          prev_out_r1[p],
          prev_out_r2[p],
          prev_out_r3[p],
          cand_states,
          cand_extras,
          cand_add_bits,
          cand_next_states,
          cand_state_bits,
          cand_out_r1,
          cand_out_r2,
          cand_out_r3,
        )
        let mut c = 0
        while c < cand_states.length() {
          let range = if prev_state_bits[p] == 0 {
            1
          } else {
            1 << prev_state_bits[p]
          }
          let state_c = cand_states[c]
          let prev_next = prev_next_states[p]
          if state_c >= prev_next && state_c < prev_next + range {
            let trans_bits = state_c - prev_next
            let new_cost = p_cost + cand_add_bits[c] + prev_state_bits[p]
            let existing = offset_candidate_index(
              curr_states,
              curr_extras,
              curr_add_bits,
              curr_next_states,
              curr_state_bits,
              curr_out_r1,
              curr_out_r2,
              curr_out_r3,
              state_c,
              cand_extras[c],
              cand_add_bits[c],
              cand_next_states[c],
              cand_state_bits[c],
              cand_out_r1[c],
              cand_out_r2[c],
              cand_out_r3[c],
            )
            if existing >= 0 {
              if new_cost < curr_costs[existing] {
                curr_costs[existing] = new_cost
                curr_parents[existing] = p
                curr_trans_bits[existing] = trans_bits
                curr_trans_nb_bits[existing] = prev_state_bits[p]
              }
            } else {
              curr_states.push(state_c)
              curr_extras.push(cand_extras[c])
              curr_add_bits.push(cand_add_bits[c])
              curr_next_states.push(cand_next_states[c])
              curr_state_bits.push(cand_state_bits[c])
              curr_out_r1.push(cand_out_r1[c])
              curr_out_r2.push(cand_out_r2[c])
              curr_out_r3.push(cand_out_r3[c])
              curr_costs.push(new_cost)
              curr_parents.push(p)
              curr_trans_bits.push(trans_bits)
              curr_trans_nb_bits.push(prev_state_bits[p])
            }
          }
          c = c + 1
        }
      }
      p = p + 1
    }

    if curr_states.length() == 0 {
      return (
        false,
        Array::new(),
        Array::new(),
        Array::new(),
        Array::new(),
        Array::new(),
      )
    }
    states_per_pos.push(curr_states)
    extras_per_pos.push(curr_extras)
    add_bits_per_pos.push(curr_add_bits)
    next_states_per_pos.push(curr_next_states)
    state_bits_per_pos.push(curr_state_bits)
    out_r1_per_pos.push(curr_out_r1)
    out_r2_per_pos.push(curr_out_r2)
    out_r3_per_pos.push(curr_out_r3)
    cost_per_pos.push(curr_costs)
    parent_idx_per_pos.push(curr_parents)
    parent_trans_bits_per_pos.push(curr_trans_bits)
    parent_trans_nb_bits_per_pos.push(curr_trans_nb_bits)
    pos = pos + 1
  }

  let last_costs = cost_per_pos[n - 1]
  let mut best_idx = -1
  let mut best_cost = inf
  let mut i = 0
  while i < last_costs.length() {
    if last_costs[i] < best_cost {
      best_cost = last_costs[i]
      best_idx = i
    }
    i = i + 1
  }
  if best_idx < 0 || best_cost >= inf {
    return (
      false,
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
      Array::new(),
    )
  }

  let states = Array::make(n, 0)
  let extras = Array::make(n, (0 : UInt))
  let extra_bits = Array::make(n, 0)
  let trans_bits = if n > 1 { Array::make(n - 1, 0) } else { Array::new() }
  let trans_nb_bits = if n > 1 { Array::make(n - 1, 0) } else { Array::new() }

  let mut idx = best_idx
  pos = n - 1
  while pos >= 0 {
    states[pos] = states_per_pos[pos][idx]
    extras[pos] = extras_per_pos[pos][idx]
    extra_bits[pos] = add_bits_per_pos[pos][idx]
    if pos > 0 {
      trans_bits[pos - 1] = parent_trans_bits_per_pos[pos][idx]
      trans_nb_bits[pos - 1] = parent_trans_nb_bits_per_pos[pos][idx]
      let parent = parent_idx_per_pos[pos][idx]
      if parent < 0 {
        return (
          false,
          Array::new(),
          Array::new(),
          Array::new(),
          Array::new(),
          Array::new(),
        )
      }
      idx = parent
    }
    pos = pos - 1
  }

  (true, states, extras, extra_bits, trans_bits, trans_nb_bits)
}
