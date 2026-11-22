///|
priv struct Violation {
  pointer : String
  keyword : String
  message : String
}

///|
fn violation(pointer : String, keyword : String, message : String) -> Violation {
  { pointer, keyword, message, }
}

///|
fn Violation::json(self : Violation) -> Json {
  Json::object(
    Map([
      ("pointer", Json::string(self.pointer)),
      ("keyword", Json::string(self.keyword)),
      ("message", Json::string(self.message)),
    ]),
  )
}

///|
fn invalid_value(schema : Json, instance : Json, path : String) -> Violation? {
  if schema is False {
    return Some(violation(path, "false", "The contract forbids this value"))
  }
  let type_ok = match field_at(schema, "type") {
    Some(String(kind)) => has_type(instance, kind)
    Some(Array(kinds)) =>
      kinds.any(kind => {
        match kind {
          String(name) => has_type(instance, name)
          _ => false
        }
      })
    _ => true
  }
  if !type_ok {
    return Some(
      violation(path, "type", "Value has a type the contract does not accept"),
    )
  }
  if field_at(schema, "const") is Some(expected) &&
    !exact_equal(expected, instance) {
    return Some(
      violation(path, "const", "Value differs from the required constant"),
    )
  }
  if field_at(schema, "enum") is Some(Array(allowed)) &&
    !allowed.any(value => exact_equal(value, instance)) {
    return Some(
      violation(path, "enum", "Value is outside the allowed enumeration"),
    )
  }
  match instance {
    Object(fields) => {
      if object_shape_violation(schema, instance, fields, path) is Some(problem) {
        return Some(problem)
      }
      if object_violation(schema, fields, path) is Some(problem) {
        return Some(problem)
      }
      if field_at(schema, "required") is Some(Array(keys)) {
        for key in keys {
          if key is String(name) && !fields.contains(name) {
            return Some(
              violation(
                path + "/" + escaped(name),
                "required",
                "Required field is absent",
              ),
            )
          }
        }
      }
      for name, value in fields {
        let location = path + "/" + escaped(name)
        let child = prop(schema, name)
        if child is False &&
          field_at(field_at(schema, "properties").unwrap_or(Json::null()), name)
          is None {
          return Some(
            violation(
              location, "additionalProperties", "Additional property is forbidden",
            ),
          )
        }
        if invalid_value(child, value, location) is Some(problem) {
          return Some(problem)
        }
      }
    }
    Array(items) =>
      if array_violation(schema, items, path) is Some(problem) {
        return Some(problem)
      }
    String(value) =>
      if length_violation(
          schema,
          value.to_array().length(),
          path,
          "minLength",
          "maxLength",
        )
        is Some(problem) {
        return Some(problem)
      }
    Number(_, ..) => {
      if decimal_limit(schema, "multipleOf") is Some(divisor) &&
        decimal_value(instance) is Some(value) &&
        !is_multiple(value, divisor) {
        return Some(
          violation(
            path, "multipleOf", "Number is not a multiple of the declared divisor",
          ),
        )
      }

      for
        (keyword, lower, strict) in [
          ("minimum", true, false),
          ("maximum", false, false),
          ("exclusiveMinimum", true, true),
          ("exclusiveMaximum", false, true),
        ] {
        if decimal_limit(schema, keyword) is Some(bound) &&
          decimal_value(instance) is Some(value) {
          let relation = compare_decimal(value, bound)
          let outside = if lower { relation < 0 } else { relation > 0 }
          if outside || (strict && relation == 0) {
            return Some(
              violation(
                path, keyword, "Number falls outside the accepted interval",
              ),
            )
          }
        }
      }
    }
    _ => ()
  }
  if branch_violation(schema, instance, path) is Some(problem) {
    return Some(problem)
  }
  conditional_violation(schema, instance, path)
}

///|
fn length_violation(
  schema : Json,
  count : Int32,
  path : String,
  low : String,
  high : String,
) -> Violation? {
  let n = count.to_double()
  if limit(schema, low) is Some(bound) && n < bound {
    return Some(violation(path, low, "Value is shorter than the minimum"))
  }
  if limit(schema, high) is Some(bound) && n > bound {
    return Some(violation(path, high, "Value is longer than the maximum"))
  }
  None
}

///|
pub fn explain_instance(schema : Json, instance : Json) -> Json {
  explain_expanded_instance(expand_schema(schema), instance)
}

///|
fn explain_expanded_instance(resolved : Json, instance : Json) -> Json {
  if !supports(resolved, 0) || !exact_value(instance) {
    return Json::object(Map([("status", Json::string("unknown"))]))
  }
  match invalid_value(resolved, instance, "") {
    None => Json::object(Map([("status", Json::string("valid"))]))
    Some(problem) =>
      Json::object(
        Map([("status", Json::string("invalid")), ("violation", problem.json())]),
      )
  }
}
