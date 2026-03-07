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
fn single_match_default_search_depth(search_limit : Int) -> Int {
  let cap = if search_limit > 0 { search_limit } else { 8192 }
  if cap >= 131072 {
    96
  } else if cap >= 65536 {
    80
  } else if cap >= 32768 {
    64
  } else if cap >= 16384 {
    48
  } else if cap >= 8192 {
    32
  } else if cap >= 4096 {
    24
  } else {
    16
  }
}

///|
fn level_single_match_search_depth(
  level : Int,
  enable_long_distance_matching : Bool,
) -> Int {
  let base = if level >= 22 {
    64
  } else if level >= 18 {
    48
  } else if level >= 14 {
    36
  } else if level >= 10 {
    28
  } else {
    20
  }
  let boosted = if enable_long_distance_matching { base + 24 } else { base }
  if boosted > 96 {
    96
  } else {
    boosted
  }
}
