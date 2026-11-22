///|
fn array_index(token : String) -> Int32? {
  let digits = token.to_array()
  if digits.length() == 0 ||
    digits.length() > 9 ||
    (digits.length() > 1 && digits[0] == '0') {
    return None
  }
  let mut value = 0
  for digit in digits {
    if digit < '0' || digit > '9' {
      return None
    }
    value = value * 10 + digit.to_int() - '0'.to_int()
  }
  Some(value)
}

///|
fn schema_for_index(schema : Json, token : String) -> (Json, Bool) {
  guard array_index(token) is Some(index) else {
    return (Json::boolean(false), false)
  }
  if limit(schema, "maxItems") is Some(maximum) && index.to_double() >= maximum {
    return (Json::boolean(false), false)
  }
  let item = item_at(schema, index)
  let guaranteed = limit(schema, "minItems").unwrap_or(0.0) > index.to_double()
  (item, guaranteed)
}

///|
fn schema_for_token(schema : Json, token : String) -> (Json, Bool) {
  if schema is False {
    return (schema, false)
  }
  let object_possible = permits_type(schema, "object")
  let array_possible = permits_type(schema, "array") &&
    array_index(token) is Some(_)
  if object_possible && array_possible {
    // The two branches may have different constraints. Widen conservatively.
    return (Json::boolean(true), false)
  }
  if object_possible {
    let object_only = field_at(schema, "type") == Some(Json::string("object"))
    return (prop(schema, token), object_only && requires(schema, token))
  }
  if array_possible {
    let array_only = field_at(schema, "type") == Some(Json::string("array"))
    let (item, present) = schema_for_index(schema, token)
    return (item, array_only && present)
  }
  (Json::boolean(false), false)
}

///|
fn project(schema : Json, path : Array[String]) -> (Json, Bool) {
  let mut current = schema
  let mut present = true
  for token in path {
    let (child, required) = schema_for_token(current, token)
    current = child
    present = present && required
  }
  (current, present)
}
