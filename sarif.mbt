///|
fn sarif_message(text : String) -> Json {
  Json::object(Map([("text", Json::string(text))]))
}

///|
fn sarif_location(
  plan_uri : String,
  step_index : Int32,
  step : String,
  pointer : String,
) -> Json {
  let path = if pointer == "" {
    "/steps/" + step_index.to_string()
  } else {
    "/steps/" + step_index.to_string() + "/args" + pointer
  }
  Json::object(
    Map([
      (
        "physicalLocation",
        Json::object(
          Map([
            (
              "artifactLocation",
              Json::object(Map([("uri", Json::string(plan_uri))])),
            ),
          ]),
        ),
      ),
      (
        "logicalLocations",
        Json::array([
          Json::object(
            Map([
              ("name", Json::string(step)),
              ("fullyQualifiedName", Json::string(path)),
            ]),
          ),
        ]),
      ),
    ]),
  )
}

///|
fn sarif_result(row : Json, plan_uri : String, step_index : Int32) -> Json? {
  guard field_at(row, "step") is Some(String(id)) &&
    field_at(row, "status") is Some(String(status)) else {
    return None
  }
  if status == "compatible" {
    return None
  }
  let evidence = field_at(row, "witness").unwrap_or(Json::null())
  let validation = field_at(evidence, "validation").unwrap_or(Json::null())
  let problem = field_at(validation, "violation").unwrap_or(Json::null())
  let pointer = match field_at(problem, "pointer") {
    Some(String(path)) => path
    _ => ""
  }
  let note = match (field_at(row, "reason"), field_at(problem, "message")) {
    (Some(String(reason)), _) => reason
    (_, Some(String(reason))) => reason
    _ if field_at(evidence, "kind") == Some(Json::string("missing_tool")) =>
      "The referenced tool is absent from the catalog"
    _ => "A verified upstream response leads to an incompatible request"
  }
  let level = if status == "incompatible" { "error" } else { "warning" }
  let rule = if status == "incompatible" { "MTC001" } else { "MTC002" }
  Some(
    Json::object(
      Map([
        ("ruleId", Json::string(rule)),
        ("level", Json::string(level)),
        ("message", sarif_message(id + " " + note)),
        (
          "locations",
          Json::array([sarif_location(plan_uri, step_index, id, pointer)]),
        ),
        ("properties", row),
      ]),
    ),
  )
}

///|
fn sarif_rule(id : String, description : String) -> Json {
  Json::object(
    Map([
      ("id", Json::string(id)),
      ("shortDescription", sarif_message(description)),
    ]),
  )
}

///|
pub fn workflow_sarif(
  report : Json,
  plan : Json,
  plan_uri : String,
) -> Json raise CheckError {
  let offsets : Map[String, Int32] = Map([])
  for i, step in array_value(required_member(plan, "steps")) {
    offsets.set(string_value(required_member(step, "id")), i)
  }
  let results : Array[Json] = []
  for row in array_value(report) {
    let id = string_value(required_member(row, "step"))
    guard offsets.get(id) is Some(index) else {
      raise Invalid("Report references unknown workflow step " + id)
    }
    if sarif_result(row, plan_uri, index) is Some(result) {
      results.push(result)
    }
  }
  let driver = Json::object(
    Map([
      ("name", Json::string("MoonToolCheck")),
      (
        "rules",
        Json::array([
          sarif_rule("MTC001", "Incompatible MCP workflow binding"),
          sarif_rule(
            "MTC002", "MCP workflow compatibility could not be established",
          ),
        ]),
      ),
    ]),
  )
  let run = Json::object(
    Map([
      ("tool", Json::object(Map([("driver", driver)]))),
      ("results", Json::array(results)),
    ]),
  )
  Json::object(
    Map([
      ("version", Json::string("2.1.0")),
      ("$schema", Json::string("https://json.schemastore.org/sarif-2.1.0.json")),
      ("runs", Json::array([run])),
    ]),
  )
}
