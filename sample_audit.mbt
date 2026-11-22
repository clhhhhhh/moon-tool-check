///|
priv struct SampleCase {
  id : String
  tool : Json?
  key : String
  arguments : Json?
  response : Json?
  expected : Bool
}

///|
fn load_samples(
  catalog : Json,
  document : Json,
) -> Array[SampleCase] raise CheckError {
  let tools = catalog_tools(catalog)
  let samples = array_value(required_member(document, "cases"))
  let ids : Map[String, Bool] = Map([])
  let cases : Array[SampleCase] = []
  for sample in samples {
    let id = string_value(required_member(sample, "id"))
    if ids.contains(id) || id == "" {
      raise Invalid("Invalid or duplicate sample ID " + id)
    }
    ids.set(id, true)
    let server = string_value(required_member(sample, "server"))
    let tool = string_value(required_member(sample, "tool"))
    let key = tool_key(server, tool)
    let input = field_at(sample, "arguments")
    let output = field_at(sample, "structuredContent")
    if input is None && output is None {
      raise Invalid("Sample " + id + " requires arguments or structuredContent")
    }
    let expected = match field_at(sample, "expectedValid") {
      None | Some(True) => true
      Some(False) => false
      _ => raise Invalid("expectedValid must be boolean in " + id)
    }
    cases.push({
      id,
      key,
      tool: tools.get(key),
      arguments: input,
      response: output,
      expected,
    })
  }
  cases
}

///|
fn unchecked_sample(reason : String) -> Json {
  Json::object(
    Map([("status", Json::string("unknown")), ("reason", Json::string(reason))]),
  )
}

///|
fn evaluate_sample(sample : SampleCase) -> Json raise CheckError {
  let checks : Map[String, Json] = Map([])
  if sample.tool is Some(tool) {
    if sample.arguments is Some(value) {
      checks.set(
        "input",
        explain_instance(required_member(tool, "inputSchema"), value),
      )
    }
    if sample.response is Some(value) {
      checks.set(
        "output",
        match field_at(tool, "outputSchema") {
          Some(schema) => explain_instance(schema, value)
          None => unchecked_sample("Tool does not declare an output contract")
        },
      )
    }
  } else {
    checks.set(
      "tool",
      Json::object(
        Map([
          ("status", Json::string("invalid")),
          ("reason", Json::string("Sample references an unavailable tool")),
        ]),
      ),
    )
  }
  let mut invalid = false
  let mut unknown = false
  for _, check in checks {
    match status_of(check) {
      "invalid" => invalid = true
      "unknown" => unknown = true
      _ => ()
    }
  }
  let status = if invalid {
    "invalid"
  } else if unknown {
    "unknown"
  } else {
    "valid"
  }
  let matched = if status == "unknown" {
    Json::null()
  } else {
    Json::boolean(sample.expected == (status == "valid"))
  }
  Json::object(
    Map([
      ("id", Json::string(sample.id)),
      ("tool", Json::string(sample.key)),
      ("status", Json::string(status)),
      ("expectedValid", Json::boolean(sample.expected)),
      ("matchesExpectation", matched),
      ("checks", Json::object(checks)),
    ]),
  )
}

///|
pub fn audit_samples(catalog : Json, samples : Json) -> Json raise CheckError {
  let results : Array[Json] = []
  let mut failed = 0
  let mut unknown = 0
  for sample in load_samples(catalog, samples) {
    let row = evaluate_sample(sample)
    results.push(row)
    match field_at(row, "matchesExpectation") {
      Some(False) => failed += 1
      Some(Null) => unknown += 1
      _ => ()
    }
  }
  let status = if failed > 0 {
    "invalid"
  } else if unknown > 0 {
    "unknown"
  } else {
    "valid"
  }
  Json::object(
    Map([
      ("status", Json::string(status)),
      ("samples", Json::array(results)),
      ("failed", Json::number(failed.to_double())),
      ("unknown", Json::number(unknown.to_double())),
    ]),
  )
}

///|
pub fn compare_samples(
  before : Json,
  after : Json,
  samples : Json,
) -> Json raise CheckError {
  let first = array_value(
    required_member(audit_samples(before, samples), "samples"),
  )
  let second = array_value(
    required_member(audit_samples(after, samples), "samples"),
  )
  let rows : Array[Json] = []
  let mut changed = 0
  let mut regressions = 0
  let mut unresolved = 0
  for i, old in first {
    let updated = second[i]
    let previous = status_of(old)
    let current = status_of(updated)
    let was_matched = field_at(old, "matchesExpectation")
    let is_matched = field_at(updated, "matchesExpectation")
    if previous != current {
      changed += 1
    }
    if was_matched is Some(True) && is_matched is Some(False) {
      regressions += 1
    }
    if current == "unknown" {
      unresolved += 1
    }
    rows.push(
      Json::object(
        Map([
          ("id", required_member(old, "id")),
          ("before", old),
          ("after", updated),
          ("changed", Json::boolean(previous != current)),
        ]),
      ),
    )
  }
  let status = if regressions > 0 {
    "invalid"
  } else if unresolved > 0 {
    "unknown"
  } else {
    "valid"
  }
  Json::object(
    Map([
      ("status", Json::string(status)),
      ("changed", Json::number(changed.to_double())),
      ("regressions", Json::number(regressions.to_double())),
      ("samples", Json::array(rows)),
    ]),
  )
}
