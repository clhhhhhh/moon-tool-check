///|
fn status_of(row : Json) -> String raise CheckError {
  string_value(required_member(row, "status"))
}

///|
fn counts_for(rows : Json) -> Json raise CheckError {
  let counts : Map[String, Int32] = Map([
    ("compatible", 0),
    ("incompatible", 0),
    ("unknown", 0),
  ])
  for row in array_value(rows) {
    let status = status_of(row)
    counts.set(status, counts.get(status).unwrap_or(0) + 1)
  }
  let result : Map[String, Json] = Map([])
  for name, count in counts {
    result.set(name, Json::number(count.to_double()))
  }
  Json::object(result)
}

///|
pub fn audit_workflows(catalog : Json, suite : Json) -> Json raise CheckError {
  let workflows = object_value(suite)
  let ids : Array[String] = []
  for id, _ in workflows {
    ids.push(id)
  }
  ids.sort()
  let groups : Array[Json] = []
  let all_steps : Array[Json] = []
  for id in ids {
    let steps = check_workflow(catalog, workflows[id])
    all_steps.append(array_value(steps))
    groups.push(
      Json::object(
        Map([
          ("workflow", Json::string(id)),
          ("counts", counts_for(steps)),
          ("steps", steps),
        ]),
      ),
    )
  }
  Json::object(
    Map([
      ("workflows", Json::array(groups)),
      ("counts", counts_for(Json::array(all_steps))),
    ]),
  )
}

///|
pub fn compare_workflows(
  before : Json,
  after : Json,
  suite : Json,
) -> Json raise CheckError {
  let workflows = object_value(suite)
  let ids : Array[String] = []
  for id, _ in workflows {
    ids.push(id)
  }
  ids.sort()
  let groups : Array[Json] = []
  let regressions : Array[Json] = []
  for id in ids {
    let changes = compare_workflow(before, after, workflows[id])
    for row in array_value(changes) {
      if field_at(row, "change") == Some(Json::string("new_failure")) ||
        field_at(row, "change") == Some(Json::string("lost_proof")) {
        regressions.push(
          Json::object(
            Map([
              ("workflow", Json::string(id)),
              ("step", required_member(row, "step")),
              ("change", required_member(row, "change")),
            ]),
          ),
        )
      }
    }
    groups.push(
      Json::object(Map([("workflow", Json::string(id)), ("changes", changes)])),
    )
  }
  Json::object(
    Map([
      ("workflows", Json::array(groups)),
      ("regressions", Json::array(regressions)),
    ]),
  )
}
