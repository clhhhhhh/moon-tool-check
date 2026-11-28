///|
pub(all) suberror CheckError {
  Invalid(String)
}

///|
// Retain the explicit input depth limit while the RC deprecates its label.
#warnings("-deprecated")
pub fn parse_json(text : String) -> Json raise CheckError {
  if text.length() > 4194304 {
    raise Invalid("JSON exceeds the document limit")
  }
  @json.parse(
    text[:],
    max_nesting_depth=80,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    _ =>
      raise Invalid("Malformed JSON, duplicate keys, or nesting exceeds limit")
  }
}

///|
fn field_at(value : Json, name : String) -> Json? {
  match value {
    Object(fields) => fields.get(name)
    _ => None
  }
}

///|
fn required_member(value : Json, name : String) -> Json raise CheckError {
  match field_at(value, name) {
    Some(field) => field
    None => raise Invalid("Missing field: " + name)
  }
}

///|
fn string_value(value : Json) -> String raise CheckError {
  match value {
    String(text) => text
    _ => raise Invalid("Expected a string")
  }
}

///|
fn object_value(value : Json) -> Map[String, Json] raise CheckError {
  match value {
    Object(fields) => fields
    _ => raise Invalid("Expected an object")
  }
}

///|
fn array_value(value : Json) -> Array[Json] raise CheckError {
  match value {
    Array(items) => items
    _ => raise Invalid("Expected an array")
  }
}

///|
fn escaped(token : String) -> String {
  token.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn pointer_tokens(pointer : String) -> Array[String] raise CheckError {
  if pointer == "" {
    return []
  }
  if !pointer.has_prefix("/") {
    raise Invalid("JSON Pointer must begin with /")
  }
  let result : Array[String] = []
  for segment in pointer[1:].split("/") {
    let out = StringBuilder()
    let chars = segment.to_owned().to_array()
    let mut i = 0
    while i < chars.length() {
      if chars[i] == '~' {
        i += 1
        if i == chars.length() {
          raise Invalid("Invalid JSON Pointer escape")
        }
        match chars[i] {
          '0' => out.write_char('~')
          '1' => out.write_char('/')
          _ => raise Invalid("Invalid JSON Pointer escape")
        }
      } else {
        out.write_char(chars[i])
      }
      i += 1
    }
    result.push(out.to_string())
  }
  result
}

///|
fn resolve(value : Json, tokens : Array[String]) -> Json? {
  let mut current = value
  for token in tokens {
    let child = match current {
      Array(items) =>
        match array_index(token) {
          Some(index) if index < items.length() => Some(items[index])
          _ => None
        }
      _ => field_at(current, token)
    }
    match child {
      Some(field) => current = field
      None => return None
    }
  }
  Some(current)
}
