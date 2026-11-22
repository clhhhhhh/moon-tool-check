///|
fn schema_issue(path : String, keyword : String, reason : String) -> Json {
  Json::object(
    Map([
      ("schemaPointer", Json::string(path)),
      ("keyword", Json::string(keyword)),
      ("reason", Json::string(reason)),
    ]),
  )
}

///|
fn report_issue(
  issues : Array[Json],
  path : String,
  keyword : String,
  reason : String,
) -> Unit {
  if issues.length() < 128 {
    issues.push(schema_issue(path, keyword, reason))
  }
}

///|
fn collect_schema_issues(
  schema : Json,
  path : String,
  depth : Int32,
  issues : Array[Json],
) -> Unit {
  if issues.length() >= 128 {
    return
  }
  if depth > 48 {
    report_issue(issues, path, "", "Schema nesting limit")
    return
  }
  match schema {
    True | False => ()
    Object(fields) =>
      for name, value in fields {
        let location = path + "/" + escaped(name)
        match (name, value) {
          ("properties", Object(props)) =>
            for key, child in props {
              collect_schema_issues(
                child,
                location + "/" + escaped(key),
                depth + 1,
                issues,
              )
            }
          ("additionalProperties" | "items" | "contains" | "not", _) =>
            collect_schema_issues(value, location, depth + 1, issues)
          ("anyOf" | "allOf" | "oneOf" | "prefixItems", Array(branches)) if branches.length() >
            0 =>
            for i, child in branches {
              collect_schema_issues(
                child,
                location + "/" + i.to_string(),
                depth + 1,
                issues,
              )
            }
          ("$ref", _) =>
            report_issue(
              issues, location, name, "Reference could not be resolved within this document",
            )
          ("$unresolved", String(reason)) =>
            report_issue(issues, path, "$ref", reason)
          _ =>
            if !supports(Json::object(Map([(name, value)])), depth) {
              report_issue(
                issues, location, name, "Keyword or value is outside the supported schema profile",
              )
            }
        }
      }
    _ => report_issue(issues, path, "", "Expected a boolean or object schema")
  }
}

///|
pub fn inspect_schema(schema : Json) -> Json {
  let issues : Array[Json] = []
  collect_schema_issues(expand_schema(schema), "", 0, issues)
  Json::object(
    Map([
      (
        "status",
        Json::string(if issues.length() == 0 { "valid" } else { "unknown" }),
      ),
      ("issues", Json::array(issues)),
    ]),
  )
}

///|
pub fn inspect_catalog(catalog : Json) -> Json raise CheckError {
  let tools = catalog_tools(catalog)
  let keys : Array[String] = []
  for key, _ in tools {
    keys.push(key)
  }
  keys.sort()
  let entries : Array[Json] = []
  let mut unsupported = 0
  let mut missing_output = 0
  for key in keys {
    let tool = tools[key]
    let input = inspect_schema(required_member(tool, "inputSchema"))
    let output = match field_at(tool, "outputSchema") {
      Some(schema) => inspect_schema(schema)
      None => {
        missing_output += 1
        Json::null()
      }
    }
    if status_of(input) == "unknown" ||
      field_at(output, "status") == Some(Json::string("unknown")) {
      unsupported += 1
    }
    entries.push(
      Json::object(
        Map([
          ("key", Json::string(key)),
          ("tool", required_member(tool, "name")),
          ("input", input),
          ("output", output),
        ]),
      ),
    )
  }
  Json::object(
    Map([
      (
        "status",
        Json::string(
          if unsupported > 0 || missing_output > 0 {
            "unknown"
          } else {
            "valid"
          },
        ),
      ),
      ("tools", Json::array(entries)),
      ("unsupported", Json::number(unsupported.to_double())),
      ("missingOutput", Json::number(missing_output.to_double())),
    ]),
  )
}
