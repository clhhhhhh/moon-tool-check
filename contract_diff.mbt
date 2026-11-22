///|
fn compatibility_json(result : Compatibility) -> Json {
  match result {
    Compatible => Json::object(Map([("status", Json::string("compatible"))]))
    Incompatible(value) =>
      Json::object(
        Map([("status", Json::string("incompatible")), ("instance", value)]),
      )
    Unknown(reason) =>
      Json::object(
        Map([
          ("status", Json::string("unknown")),
          ("reason", Json::string(reason)),
        ]),
      )
  }
}

///|
fn compare_output_contract(previous : Json?, current : Json?) -> Compatibility {
  match (previous, current) {
    (None, _) => Compatible
    (Some(_), None) => Unknown("Updated tool has no outputSchema")
    (Some(expected), Some(produced)) => compare_schemas(produced, expected)
  }
}

///|
fn output_record(
  key : String,
  name : String,
  fields : Map[String, Json],
) -> Json {
  fields.set("tool", Json::string(name))
  fields.set("key", Json::string(key))
  Json::object(fields)
}

///|
pub fn compare_catalogs(before : Json, after : Json) -> Json raise CheckError {
  let old_tools = catalog_tools(before)
  let new_tools = catalog_tools(after)
  let keys : Array[String] = []
  for key, _ in old_tools {
    keys.push(key)
  }
  for key, _ in new_tools {
    if !old_tools.contains(key) {
      keys.push(key)
    }
  }
  keys.sort()
  let records : Array[Json] = []
  for key in keys {
    let current = new_tools.get(key)
    let previous = old_tools.get(key)
    let name = string_value(
      required_member(
        current.unwrap_or(previous.unwrap_or(Json::null())),
        "name",
      ),
    )
    let fields : Map[String, Json] = Map([])
    match (previous, current) {
      (Some(old), Some(updated)) => {
        let input = compare_schemas(
          required_member(old, "inputSchema"),
          required_member(updated, "inputSchema"),
        )
        let output = compare_output_contract(
          field_at(old, "outputSchema"),
          field_at(updated, "outputSchema"),
        )
        fields.set("input", compatibility_json(input))
        fields.set("output", compatibility_json(output))
        fields.set(
          "metadataChanged",
          Json::boolean(tool_annotations(old) != tool_annotations(updated)),
        )
        let kind = if input is Incompatible(_) || output is Incompatible(_) {
          "breaking"
        } else if input is Unknown(_) || output is Unknown(_) {
          "unknown"
        } else {
          "compatible"
        }
        fields.set("status", Json::string(kind))
      }
      (Some(_), None) => fields.set("status", Json::string("removed"))
      (None, Some(_)) => fields.set("status", Json::string("added"))
      _ => ()
    }
    records.push(output_record(key, name, fields))
  }
  Json::array(records)
}

///|
fn tool_annotations(tool : Json) -> Json {
  let metadata : Map[String, Json] = Map([])
  for name in ["description", "title", "annotations"] {
    if field_at(tool, name) is Some(value) {
      metadata.set(name, value)
    }
  }
  Json::object(metadata)
}
