///|
fn trace_problem_key(problem : Json) -> String raise CheckError {
  let id = required_member(problem, "step")
  let kind = required_member(problem, "kind")
  let detail = required_member(problem, "detail")
  let violation = field_at(detail, "violation").unwrap_or(Json::null())
  let path = field_at(violation, "pointer").unwrap_or(Json::null())
  let keyword = field_at(violation, "keyword").unwrap_or(Json::null())
  let upstream = match kind {
    String(
      "upstream_error"
      | "unavailable_output"
      | "out_of_order"
      | "missing_upstream_call",
    ) => detail
    _ => Json::null()
  }
  Json::array([id, kind, path, keyword, upstream]).stringify()
}

///|
fn trace_delta_row(event : Json, verdict : String) -> Json {
  Json::object(Map([("change", Json::string(verdict)), ("problem", event)]))
}

///|
pub fn compare_trace(
  before : Json,
  after : Json,
  plan : Json,
  trace : Json,
) -> Json raise CheckError {
  let old = check_trace(before, plan, trace)
  let updated = check_trace(after, plan, trace)
  let old_problems = array_value(required_member(old, "problems"))
  let next_problems = array_value(required_member(updated, "problems"))
  let old_index : Map[String, Json] = Map([])
  let new_index : Map[String, Json] = Map([])
  for problem in old_problems {
    old_index.set(trace_problem_key(problem), problem)
  }
  for problem in next_problems {
    new_index.set(trace_problem_key(problem), problem)
  }
  let changes : Array[Json] = []
  let mut regressions = 0
  let mut unknown = 0
  for problem in next_problems {
    let key = trace_problem_key(problem)
    let is_unknown = field_at(required_member(problem, "detail"), "status") ==
      Some(Json::string("unknown"))
    if is_unknown {
      unknown += 1
    }
    match old_index.get(key) {
      None => {
        changes.push(
          trace_delta_row(
            problem,
            if is_unknown {
              "unknown"
            } else {
              "new_failure"
            },
          ),
        )
        if !is_unknown {
          regressions += 1
        }
      }
      Some(previous) if !exact_equal(previous, problem) => {
        let was_unknown = field_at(
            required_member(previous, "detail"),
            "status",
          ) ==
          Some(Json::string("unknown"))
        if was_unknown && !is_unknown {
          changes.push(trace_delta_row(problem, "new_failure"))
          regressions += 1
        } else {
          changes.push(trace_delta_row(problem, "detail_changed"))
        }
      }
      _ => ()
    }
  }
  for problem in old_problems {
    if !new_index.contains(trace_problem_key(problem)) {
      changes.push(trace_delta_row(problem, "resolved"))
    }
  }
  let state = if regressions > 0 {
    "invalid"
  } else if unknown > 0 {
    "unknown"
  } else {
    "valid"
  }
  Json::object(
    Map([
      ("status", Json::string(state)),
      ("regressions", Json::number(regressions.to_double())),
      ("before", old),
      ("after", updated),
      ("changes", Json::array(changes)),
    ]),
  )
}
