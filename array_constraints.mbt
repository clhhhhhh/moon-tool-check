///|
fn prefix_items(schema : Json) -> Array[Json] {
  match field_at(schema, "prefixItems") {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn item_at(schema : Json, index : Int32) -> Json {
  let prefix = prefix_items(schema)
  if index < prefix.length() {
    prefix[index]
  } else {
    tail_item(schema)
  }
}

///|
fn tail_item(schema : Json) -> Json {
  field_at(schema, "items").unwrap_or(Json::boolean(true))
}

///|
fn array_violation(
  schema : Json,
  items : Array[Json],
  path : String,
) -> Violation? {
  if length_violation(schema, items.length(), path, "minItems", "maxItems")
    is Some(problem) {
    return Some(problem)
  }
  let unique = field_at(schema, "uniqueItems") is Some(True)
  let contains_schema = field_at(schema, "contains")
  let mut matched = 0
  for i, value in items {
    let position = path + "/" + i.to_string()
    if invalid_value(item_at(schema, i), value, position) is Some(problem) {
      return Some(problem)
    }
    if unique {
      for previous in 0..<i {
        if exact_equal(items[previous], value) {
          return Some(
            violation(
              position, "uniqueItems", "Value duplicates an earlier array element",
            ),
          )
        }
      }
    }
    if contains_schema is Some(needle) && accepts(needle, value) {
      matched += 1
    }
  }
  if contains_schema is Some(_) {
    let min = limit(schema, "minContains").unwrap_or(1.0)
    if matched.to_double() < min {
      return Some(
        violation(path, "minContains", "Too few array items match contains"),
      )
    }
    if limit(schema, "maxContains") is Some(max) && matched.to_double() > max {
      return Some(
        violation(path, "maxContains", "Too many array items match contains"),
      )
    }
  }
  None
}

///|
fn array_implies(
  source : Json,
  target : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Bool {
  if !bounds_inside(source, target, "minItems", true) ||
    !bounds_inside(source, target, "maxItems", false) {
    return false
  }
  let max = limit(source, "maxItems")
  if field_at(target, "uniqueItems") is Some(True) &&
    !(field_at(source, "uniqueItems") is Some(True)) &&
    !(max is Some(n) && n <= 1.0) {
    return false
  }
  if field_at(target, "contains") is Some(needle) {
    guard field_at(source, "contains") is Some(given) &&
      exact_equal(needle, given) else {
      return false
    }
    if limit(source, "minContains").unwrap_or(1.0) <
      limit(target, "minContains").unwrap_or(1.0) ||
      !bounds_inside(source, target, "maxContains", false) {
      return false
    }
  }
  let a = prefix_items(source).length()
  let b = prefix_items(target).length()
  let span = if a >= b { a } else { b }
  for i in 0..<span {
    if max is Some(n) && n <= i.to_double() {
      return true
    }
    if !implies_at(item_at(source, i), item_at(target, i), depth, budget) {
      return false
    }
  }
  (max is Some(n) && n <= span.to_double()) ||
  implies_at(tail_item(source), tail_item(target), depth, budget)
}

///|
fn tuple_candidates(
  source : Json,
  target : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Array[Json] {
  let width = prefix_items(source).length()
  let target_width = prefix_items(target).length()
  let minimum = limit(source, "minItems").unwrap_or(0.0)
  if width == 0 && target_width == 0 && minimum <= 1.0 {
    return []
  }
  if minimum > 64.0 {
    return []
  }
  let count = minimum.to_int()
  let sizes = [count, count + 1, width, target_width]
  let results : Array[Json] = []
  for size in sizes {
    if size > 64 ||
      (limit(source, "maxItems") is Some(max) && max < size.to_double()) {
      continue
    }
    let values : Array[Json] = []
    let choices : Array[Array[Json]] = []
    for index in 0..<size {
      let samples = candidate_walk(
        item_at(source, index),
        item_at(target, index),
        depth + 1,
        budget,
      )
      if samples.length() == 0 {
        break
      }
      values.push(samples[0])
      choices.push(samples)
    }
    if values.length() != size {
      continue
    }
    results.push(Json::array(values))
    for i, samples in choices {
      for sample in samples {
        let variant = values.copy()
        variant[i] = sample
        results.push(Json::array(variant))
        if results.length() >= 128 {
          return results
        }
      }
    }
  }
  results
}
