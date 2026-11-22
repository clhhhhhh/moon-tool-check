///|
fn all_values(schema : Json) -> Json? {
  match field_at(schema, "const") {
    Some(value) => Some(Json::array([value]))
    None => field_at(schema, "enum")
  }
}

///|
fn bounds_inside(
  source : Json,
  target : Json,
  key : String,
  lower : Bool,
) -> Bool {
  match limit(target, key) {
    None => true
    Some(wanted) =>
      match limit(source, key) {
        Some(actual) if lower => actual >= wanted
        Some(actual) => actual <= wanted
        None => false
      }
  }
}

///|
fn implies(source : Json, target : Json, depth : Int32) -> Bool {
  implies_at(source, target, depth, Ref(8192))
}

///|
fn implies_at(
  source : Json,
  target : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Bool {
  budget.val -= 1
  if budget.val < 0 || depth > 48 {
    return false
  }
  if exact_equal(source, target) || source is False || target is True {
    return true
  }
  if all_values(source) is Some(Array(values)) {
    return values.all(value => !accepts(source, value) || accepts(target, value))
  }
  if composed_implication(source, target, depth, budget) is Some(answer) {
    return answer
  }
  if conditional_implies(source, target, depth, budget) is Some(answer) {
    return answer
  }
  if target is False || all_values(target) is Some(_) {
    return false
  }
  for
    kind in [
      "null", "boolean", "integer", "number", "string", "array", "object",
    ] {
    if !permits_type(source, kind) {
      continue
    }
    if !permits_type(target, kind) {
      return false
    }
    let holds = match kind {
      "number" | "integer" => numeric_implies(source, target)
      "string" =>
        bounds_inside(source, target, "minLength", true) &&
        bounds_inside(source, target, "maxLength", false)
      "array" => array_implies(source, target, depth + 1, budget)
      "object" => object_implies(source, target, depth + 1, budget)
      _ => true
    }
    if !holds {
      return false
    }
  }
  true
}

///|
fn object_implies(
  source : Json,
  target : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Bool {
  if !object_constraints_imply(source, target) ||
    !shape_implication(source, target, depth, budget) {
    return false
  }
  if field_at(target, "required") is Some(Array(keys)) {
    for key in keys {
      if key is String(name) && !requires(source, name) {
        return false
      }
    }
  }
  for schema in [source, target] {
    if field_at(schema, "properties") is Some(Object(fields)) {
      for name, _ in fields {
        if !implies_at(prop(source, name), prop(target, name), depth, budget) {
          return false
        }
      }
    }
  }
  implies_at(
    field_at(source, "additionalProperties").unwrap_or(Json::boolean(true)),
    field_at(target, "additionalProperties").unwrap_or(Json::boolean(true)),
    depth,
    budget,
  )
}

///|
fn candidates(source : Json, target : Json, depth : Int32) -> Array[Json] {
  candidate_walk(source, target, depth, Ref(2048))
}

///|
fn candidate_walk(
  source : Json,
  target : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Array[Json] {
  budget.val -= 1
  if budget.val < 0 || depth > 12 || source is False {
    return []
  }
  if all_values(source) is Some(Array(values)) {
    return values.filter(value => accepts(source, value))
  }
  let result : Array[Json] = []
  let basic : Array[Json] = [
    Json::null(),
    Json::boolean(false),
    Json::boolean(true),
    Json::string(""),
    Json::string("x"),
    Json::number(0.0),
    Json::number(1.0),
    Json::number(-1.0),
    Json::array([]),
    Json::object(Map([])),
  ]
  result.append(basic)
  if permits_type(source, "number") || permits_type(source, "integer") {
    result.append(numeric_candidates(source, target))
  }
  if permits_type(source, "array") {
    result.append(tuple_candidates(source, target, depth, budget))
  }
  for key in ["anyOf", "allOf", "oneOf"] {
    if field_at(source, key) is Some(Array(branches)) {
      for branch in branches {
        result.append(candidate_walk(branch, target, depth + 1, budget))
        if result.length() >= 240 {
          break
        }
      }
    }
  }
  for schema in [source, target] {
    for key in ["minLength", "maxLength", "minItems", "maxItems"] {
      if limit(schema, key) is Some(bound) && bound <= 64.0 {
        for delta in [-1, 0, 1] {
          let length = bound.to_int() + delta
          if length < 0 {
            continue
          }
          if key.has_suffix("Length") {
            result.push(Json::string("x".repeat(length)))
          } else {
            let items = candidate_walk(
              field_at(source, "items").unwrap_or(Json::boolean(true)),
              field_at(target, "items").unwrap_or(Json::boolean(true)),
              depth + 1,
              budget,
            )
            for item in items {
              result.push(Json::array(Array::make(length, item)))
              if result.length() >= 200 {
                break
              }
            }
          }
        }
      }
    }
  }
  if permits_type(source, "object") {
    result.append(object_domain_candidates(source, target, depth, budget))
  }
  result.filter(value => exact_value(value) && accepts(source, value))
}

///|
pub(all) enum Compatibility {
  Compatible
  Incompatible(Json)
  Unknown(String)
}

///|
pub fn compare_schemas(source : Json, target : Json) -> Compatibility {
  let source = expand_schema(source)
  let target = expand_schema(target)
  if !supports(source, 0) || !supports(target, 0) {
    return Unknown("Unsupported schema keyword or value")
  }
  if implies(source, target, 0) {
    return Compatible
  }
  for sample in candidates(source, target, 0) {
    if !accepts(target, sample) {
      return Incompatible(sample)
    }
  }
  Unknown("No proof or verified counterexample")
}
