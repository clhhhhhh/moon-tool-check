///|
fn step_dependencies(step : Step) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let dependencies : Array[String] = []
  for binding in step.bindings {
    if binding.source is Some(source) &&
      source != "$inputs" &&
      !seen.contains(source) {
      seen.set(source, true)
      dependencies.push(source)
    }
  }
  dependencies
}

///|
fn downstream_index(steps : Array[Step]) -> Map[String, Array[String]] {
  let downstream : Map[String, Array[String]] = Map([])
  for step in steps {
    downstream.set(step.id, [])
  }
  for step in steps {
    for source in step_dependencies(step) {
      if downstream.get(source) is Some(children) {
        children.push(step.id)
      }
    }
  }
  downstream
}

///|
fn affected_steps(
  root : String,
  downstream : Map[String, Array[String]],
) -> Array[Json] {
  let queue = [root]
  let distances : Map[String, Int32] = Map([(root, 0)])
  let affected : Array[Json] = []
  let mut position = 0
  while position < queue.length() {
    let current = queue[position]
    position += 1
    let distance = distances[current]
    if current != root {
      affected.push(
        Json::object(
          Map([
            ("step", Json::string(current)),
            ("hops", Json::number(distance.to_double())),
          ]),
        ),
      )
    }
    if downstream.get(current) is Some(children) {
      for child in children {
        if !distances.contains(child) {
          distances.set(child, distance + 1)
          queue.push(child)
        }
      }
    }
  }
  affected
}

///|
pub fn explain_upgrade(
  before : Json,
  after : Json,
  plan : Json,
) -> Json raise CheckError {
  let changes = compare_workflow(before, after, plan)
  let steps = order_steps(load_steps(after, plan))
  let downstream = downstream_index(steps)
  let affected : Array[Json] = []
  let mut failures = 0
  let mut lost = 0
  let mut has_unknown = false
  for row in array_value(changes) {
    let id = string_value(required_member(row, "step"))
    let change = string_value(required_member(row, "change"))
    has_unknown = has_unknown ||
      status_of(required_member(row, "after")) == "unknown"
    match change {
      "new_failure" => failures += 1
      "lost_proof" => lost += 1
      _ => continue
    }
    affected.push(
      Json::object(
        Map([
          ("step", Json::string(id)),
          ("change", Json::string(change)),
          ("downstream", Json::array(affected_steps(id, downstream))),
        ]),
      ),
    )
  }
  let state = if failures > 0 {
    "invalid"
  } else if has_unknown {
    "unknown"
  } else {
    "valid"
  }
  Json::object(
    Map([
      ("status", Json::string(state)),
      ("newFailures", Json::number(failures.to_double())),
      ("lostProofs", Json::number(lost.to_double())),
      ("changes", changes),
      ("affected", Json::array(affected)),
    ]),
  )
}
