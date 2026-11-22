///|
fn witness_record(
  step : Step,
  outputs : Map[String, Json],
  request : Json,
) -> Json {
  Json::object(
    Map([
      ("outputs", Json::object(outputs)),
      ("request", request),
      ("validation", explain_instance(step.input, request)),
    ]),
  )
}

///|
fn find_counterexample(
  step : Step,
  domains : Map[String, Array[Json]],
) -> Json? {
  let names : Array[String] = []
  let options : Array[Array[Json]] = []
  for name, values in domains {
    if values.length() == 0 {
      return None
    }
    names.push(name)
    options.push(values)
  }
  let positions = Array::make(names.length(), 0)
  for _ in 0..<1024 {
    let outputs : Map[String, Json] = Map([])
    for i, name in names {
      outputs.set(name, options[i][positions[i]])
    }
    let request = assembled(step, outputs)
    if !accepts(step.input, request) {
      return Some(witness_record(step, outputs, request))
    }
    let mut i = 0
    while i < positions.length() {
      positions[i] += 1
      if positions[i] < options[i].length() {
        break
      }
      positions[i] = 0
      i += 1
    }
    if i == positions.length() {
      return None
    }
  }
  None
}

///|
fn witness_domains(
  step : Step,
  schemas : Map[String, Json],
) -> Map[String, Array[Json]] {
  let domains : Map[String, Array[Json]] = Map([])
  for name, schema in schemas {
    let samples = candidates(schema, source_hints(step, name), 0)
    domains.set(name, samples)
  }
  domains
}

///|
fn source_hints(step : Step, name : String) -> Json {
  let hints : Map[String, Json] = Map([])
  for binding in step.bindings {
    if binding.source != Some(name) || binding.pointer.length() == 0 {
      continue
    }
    let desired = prop(step.input, binding.parameter)
    hint_at(hints, binding.pointer, 0, desired)
  }
  Json::object(Map([("properties", Json::object(hints))]))
}

///|
fn hint_at(
  fields : Map[String, Json],
  path : Array[String],
  offset : Int32,
  hint : Json,
) -> Unit {
  let token = path[offset]
  if offset + 1 == path.length() {
    if !fields.contains(token) {
      fields.set(token, hint)
    }
    return
  }
  let nested : Map[String, Json] = match fields.get(token) {
    Some(value) =>
      match field_at(value, "properties") {
        Some(Object(props)) => props.copy()
        _ => Map([])
      }
    None => Map([])
  }
  hint_at(nested, path, offset + 1, hint)
  fields.set(token, Json::object(Map([("properties", Json::object(nested))])))
}

///|
fn analyze_bindings(
  step : Step,
  predecessors : Map[String, Json],
  projected : Json,
) -> Compatibility {
  if implies(projected, step.input, 0) {
    return Compatible
  }
  if complete_sources(predecessors) is Some(domains) {
    return match find_counterexample(step, domains) {
      Some(witness) => Incompatible(witness)
      None => Compatible
    }
  }
  match find_counterexample(step, witness_domains(step, predecessors)) {
    Some(witness) => Incompatible(witness)
    None => Unknown("No proof or reproducible counterexample")
  }
}
