///|
fn capture_bundled_entry(
  catalog : Json,
  plan : Json,
  row : Json,
  minimize : Bool,
) -> Json? raise CheckError {
  guard field_at(row, "witness") is Some(witness) else { return None }
  let step = required_member(row, "step")
  let id = string_value(step)
  let reduced = if minimize {
    minimize_workflow_witness(catalog, plan, id, witness)
  } else {
    witness
  }
  Some(
    Json::object(
      Map([
        ("step", step),
        ("witness", reduced),
        ("originalLength", Json::number(witness_cost(witness).to_double())),
        ("bundledLength", Json::number(witness_cost(reduced).to_double())),
      ]),
    ),
  )
}

///|
pub fn export_witnesses(
  catalog : Json,
  plan : Json,
  minimize~ : Bool = true,
) -> Json raise CheckError {
  let rows = array_value(check_workflow(catalog, plan))
  let entries : Array[Json] = []
  for row in rows {
    if capture_bundled_entry(catalog, plan, row, minimize) is Some(entry) {
      entries.push(entry)
    }
  }
  Json::object(
    Map([("version", Json::number(1.0)), ("entries", Json::array(entries))]),
  )
}

///|
pub fn verify_witnesses(
  catalog : Json,
  plan : Json,
  bundle : Json,
) -> Json raise CheckError {
  if !exact_equal(required_member(bundle, "version"), Json::number(1.0)) {
    raise Invalid("Unsupported witness bundle version")
  }
  let seen : Map[String, Bool] = Map([])
  let results : Array[Json] = []
  let mut invalid = 0
  for entry in array_value(required_member(bundle, "entries")) {
    let step = string_value(required_member(entry, "step"))
    if seen.contains(step) {
      raise Invalid("Duplicate witness for step " + step)
    }
    seen.set(step, true)
    let witness = required_member(entry, "witness")
    let verified = verify_witness(catalog, plan, step, witness)
    if !verified {
      invalid += 1
    }
    results.push(
      Json::object(
        Map([
          ("step", Json::string(step)),
          ("verified", Json::boolean(verified)),
        ]),
      ),
    )
  }
  Json::object(
    Map([
      ("status", Json::string(if invalid == 0 { "valid" } else { "invalid" })),
      ("verified", Json::number((results.length() - invalid).to_double())),
      ("invalid", Json::number(invalid.to_double())),
      ("entries", Json::array(results)),
    ]),
  )
}

///|
pub fn verify_upgrade_witnesses(
  catalog : Json,
  plan : Json,
  upgrade : Json,
) -> Json raise CheckError {
  let entries : Array[Json] = []
  for change in array_value(upgrade) {
    if field_at(change, "change") != Some(Json::string("new_failure")) {
      continue
    }
    let step = required_member(change, "step")
    let current = required_member(change, "after")
    let witness = required_member(current, "witness")
    entries.push(Json::object(Map([("step", step), ("witness", witness)])))
  }
  verify_witnesses(
    catalog,
    plan,
    Json::object(
      Map([("version", Json::number(1.0)), ("entries", Json::array(entries))]),
    ),
  )
}
