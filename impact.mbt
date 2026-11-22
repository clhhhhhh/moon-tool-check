///|
pub fn compare_workflow(
  before : Json,
  after : Json,
  plan : Json,
) -> Json raise CheckError {
  let prior = check_workflow(before, plan)
  let next = check_workflow(after, plan)
  let index : Map[String, Json] = Map([])
  for row in array_value(prior) {
    index.set(string_value(required_member(row, "step")), row)
  }
  let changes : Array[Json] = []
  for row in array_value(next) {
    let id = string_value(required_member(row, "step"))
    let old = index[id]
    let previous = string_value(required_member(old, "status"))
    let current = string_value(required_member(row, "status"))
    let change = match (previous, current) {
      ("incompatible", "incompatible") => "existing_failure"
      (_, "incompatible") => "new_failure"
      ("compatible", "unknown") => "lost_proof"
      ("incompatible", "compatible") => "fixed"
      _ if previous == current => "unchanged"
      _ => "changed"
    }
    changes.push(
      Json::object(
        Map([
          ("step", Json::string(id)),
          ("change", Json::string(change)),
          ("before", old),
          ("after", row),
        ]),
      ),
    )
  }
  Json::array(changes)
}

///|
pub fn verify_witness(
  catalog : Json,
  plan : Json,
  id : String,
  witness : Json,
) -> Bool raise CheckError {
  verify_prepared_witness(prepare_workflow(catalog, plan), id, witness)
}

///|
fn verify_prepared_witness(
  workflow : PreparedWorkflow,
  id : String,
  witness : Json,
) -> Bool raise CheckError {
  guard workflow.index.get(id) is Some(step) else {
    raise Invalid("Unknown step: " + id)
  }
  if !step.tool_available {
    return field_at(witness, "kind") == Some(Json::string("missing_tool"))
  }
  let outputs = object_value(required_member(witness, "outputs"))
  let request = required_member(witness, "request")
  let needed : Map[String, Bool] = Map([])
  for binding in step.bindings {
    if binding.source is Some(parent) && !needed.contains(parent) {
      needed.set(parent, true)
      match (prepared_source(workflow, parent), outputs.get(parent)) {
        (Some(schema), Some(value)) =>
          if validate_expanded_instance(schema, value) != Some(true) {
            return false
          }
        _ => return false
      }
    }
  }
  outputs.length() == needed.length() &&
  exact_equal(assembled(step, outputs), request) &&
  validate_expanded_instance(step.input, request) == Some(false)
}
