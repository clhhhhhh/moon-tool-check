///|
fn supports(schema : Json, depth : Int32) -> Bool {
  if depth > 48 {
    return false
  }
  match schema {
    True | False => true
    Object(fields) => {
      for name, value in fields {
        let valid = match name {
          "title" | "description" | "default" | "examples" | "$comment" => true
          "$schema" =>
            value ==
            Json::string("https://json-schema.org/draft/2020-12/schema")
          "type" =>
            match value {
              String(kind) => known_type(kind)
              Array(kinds) =>
                kinds.length() > 0 &&
                kinds.all(kind => {
                  match kind {
                    String(s) => known_type(s)
                    _ => false
                  }
                })
              _ => false
            }
          "properties" | "dependentSchemas" =>
            schema_map_supported(value, depth)
          "additionalProperties"
          | "items"
          | "not"
          | "contains"
          | "if"
          | "then"
          | "else"
          | "propertyNames" => supports(value, depth + 1)
          "anyOf" | "allOf" | "oneOf" | "prefixItems" =>
            match value {
              Array(branches) =>
                branches.length() > 0 &&
                branches.all(branch => supports(branch, depth + 1))
              _ => false
            }
          "enum" =>
            match value {
              Array(values) => values.length() > 0 && values.all(exact_value)
              _ => false
            }
          "const" => exact_value(value)
          "uniqueItems" => value is True || value is False
          "multipleOf" => bounded_multiple(value)
          "dependentRequired" => required_dependencies_ok(value)
          "required" =>
            match value {
              Array(values) => values.all(v => v is String(_))
              _ => false
            }
          "minimum" | "maximum" | "exclusiveMinimum" | "exclusiveMaximum" =>
            decimal_value(value) is Some(_)
          "minLength"
          | "maxLength"
          | "minItems"
          | "maxItems"
          | "minContains"
          | "maxContains"
          | "minProperties"
          | "maxProperties" =>
            match numeric(value) {
              Some(n) => n >= 0.0 && n == n.floor()
              None => false
            }
          _ => false
        }
        if !valid {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn numeric(value : Json) -> Double? {
  match value {
    Number(n, ..) if decimal_value(value) is Some(d) &&
      d.power >= 0 &&
      n >= -9007199254740991.0 &&
      n <= 9007199254740991.0 &&
      n == n.floor() => Some(n)
    _ => None
  }
}

///|
fn exact_value(value : Json) -> Bool {
  match value {
    Number(_, ..) => decimal_value(value) is Some(_)
    Array(items) => items.all(exact_value)
    Object(fields) => {
      for _, field in fields {
        if !exact_value(field) {
          return false
        }
      }
      true
    }
    _ => true
  }
}

///|
fn known_type(kind : String) -> Bool {
  ["null", "boolean", "number", "integer", "string", "array", "object"].contains(
    kind,
  )
}

///|
fn has_type(value : Json, kind : String) -> Bool {
  match (value, kind) {
    (Null, "null") | (True, "boolean") | (False, "boolean") => true
    (String(_), "string") | (Object(_), "object") | (Array(_), "array") => true
    (Number(_, ..), "number") => true
    (Number(_, ..), "integer") =>
      decimal_value(value) is Some(d) && d.power >= 0
    _ => false
  }
}

///|
fn permits_type(schema : Json, kind : String) -> Bool {
  match field_at(schema, "type") {
    None => true
    Some(String(name)) =>
      name == kind || (kind == "integer" && name == "number")
    Some(Array(names)) =>
      names.contains(Json::string(kind)) ||
      (kind == "integer" && names.contains(Json::string("number")))
    _ => false
  }
}

///|
fn prop(schema : Json, key : String) -> Json {
  match field_at(field_at(schema, "properties").unwrap_or(Json::null()), key) {
    Some(value) => value
    None =>
      field_at(schema, "additionalProperties").unwrap_or(Json::boolean(true))
  }
}

///|
fn requires(schema : Json, key : String) -> Bool {
  match field_at(schema, "required") {
    Some(Array(keys)) => keys.contains(Json::string(key))
    _ => false
  }
}

///|
fn limit(schema : Json, key : String) -> Double? {
  numeric(field_at(schema, key).unwrap_or(Json::null()))
}

///|
fn accepts(schema : Json, value : Json) -> Bool {
  invalid_value(schema, value, "") is None
}

///|

///|
pub fn validate_instance(schema : Json, instance : Json) -> Bool? {
  let schema = expand_schema(schema)
  if supports(schema, 0) && exact_value(instance) {
    Some(accepts(schema, instance))
  } else {
    None
  }
}
