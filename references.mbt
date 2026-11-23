///|
fn expand_schema(schema : Json) -> Json {
  let budget = Ref(4096)
  expand_at(schema, schema, [], budget, 0)
}

///|
fn expand_at(
  schema : Json,
  root : Json,
  references : Array[String],
  budget : Ref[Int32],
  depth : Int32,
) -> Json {
  budget.val -= 1
  if budget.val < 0 || depth > 48 {
    return Json::object(
      Map([("$unresolved", Json::string("Schema expansion limit"))]),
    )
  }
  guard schema is Object(fields) else { return schema }
  if fields.get("$schema") is Some(dialect) &&
    dialect != Json::string("https://json-schema.org/draft/2020-12/schema") {
    return schema
  }
  if fields.contains("$id") || fields.contains("$anchor") {
    return schema
  }
  if fields.get("$ref") is Some(String(reference)) {
    for name, _ in fields {
      if name != "$ref" &&
        name != "$defs" &&
        name != "$schema" &&
        name != "description" &&
        name != "title" {
        return schema
      }
    }
    guard decode_reference_fragment(reference) is Some(pointer) &&
      pointer.has_prefix("/$defs/") &&
      !references.contains(pointer) else {
      return schema
    }
    let tokens = pointer_tokens(pointer) catch { _ => return schema }
    guard resolve(root, tokens) is Some(target) else { return schema }
    let next = references.copy()
    next.push(pointer)
    return expand_at(target, root, next, budget, depth + 1)
  }
  let result : Map[String, Json] = Map([])
  for name, field in fields {
    match (name, field) {
      ("$defs", _) => ()
      ("items", _)
      | ("additionalProperties", _)
      | ("not", _)
      | ("contains", _)
      | ("if", _)
      | ("then", _)
      | ("else", _)
      | ("propertyNames", _) =>
        result.set(name, expand_at(field, root, references, budget, depth + 1))
      ("anyOf" | "allOf" | "oneOf" | "prefixItems", Array(branches)) =>
        result.set(
          name,
          Json::array(
            branches.map(branch => {
              expand_at(branch, root, references, budget, depth + 1)
            }),
          ),
        )
      ("properties" | "dependentSchemas", Object(props)) => {
        let normalized : Map[String, Json] = Map([])
        for key, value in props {
          normalized.set(
            key,
            expand_at(value, root, references, budget, depth + 1),
          )
        }
        result.set(name, Json::object(normalized))
      }
      _ => result.set(name, field)
    }
  }
  Json::object(result)
}

///|
fn decode_reference_fragment(reference : String) -> String? {
  if !reference.has_prefix("#") {
    return None
  }
  let fragment = reference[1:]
  if !fragment.to_owned().contains("%") {
    return Some(fragment.to_owned())
  }
  let encoded = @utf8.encode(fragment)
  let bytes : Array[Byte] = []
  let mut offset = 0
  while offset < encoded.length() {
    if encoded[offset] != b'%' {
      bytes.push(encoded[offset])
      offset += 1
      continue
    }
    guard offset + 2 < encoded.length() &&
      hex_digit(encoded[offset + 1]) is Some(high) &&
      hex_digit(encoded[offset + 2]) is Some(low) else {
      return None
    }
    bytes.push((high * 16 + low).to_byte())
    offset += 3
  }
  let decoded = Bytes::from_array(bytes[:])
  Some(@utf8.decode(decoded[:])) catch {
    _ => None
  }
}

///|
fn hex_digit(value : Byte) -> Int32? {
  let code = value.to_int()
  if value >= b'0' && value <= b'9' {
    Some(code - b'0'.to_int())
  } else if value >= b'A' && value <= b'F' {
    Some(code - b'A'.to_int() + 10)
  } else if value >= b'a' && value <= b'f' {
    Some(code - b'a'.to_int() + 10)
  } else {
    None
  }
}
