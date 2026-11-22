///|
fn shrink_values(value : Json, depth : Int32) -> Array[Json] {
  if depth > 16 {
    return []
  }
  match value {
    Object(fields) => {
      let candidates : Array[Json] = []
      for name, child in fields {
        let reduced = fields.copy()
        reduced.remove(name)
        candidates.push(Json::object(reduced))
        for alternative in shrink_values(child, depth + 1) {
          let replacement = fields.copy()
          replacement.set(name, alternative)
          candidates.push(Json::object(replacement))
          if candidates.length() >= 64 {
            return candidates
          }
        }
        if candidates.length() >= 64 {
          break
        }
      }
      candidates
    }
    Array(items) => {
      let candidates : Array[Json] = []
      if items.length() > 0 {
        candidates.push(Json::array([]))
      }
      if items.length() > 1 {
        candidates.push(Json::array(items[:items.length() / 2].to_owned()))
      }
      for i, item in items {
        let rest : Array[Json] = []
        for j, other in items {
          if i != j {
            rest.push(other)
          }
        }
        candidates.push(Json::array(rest))
        for alternative in shrink_values(item, depth + 1) {
          let replacement = items.copy()
          replacement[i] = alternative
          candidates.push(Json::array(replacement))
          if candidates.length() >= 64 {
            return candidates
          }
        }
        if candidates.length() >= 64 {
          break
        }
      }
      candidates
    }
    String(text) => {
      let chars = text.to_array()
      let candidates : Array[Json] = []
      if chars.length() > 0 {
        candidates.push(Json::string(""))
      }
      if chars.length() > 1 {
        let prefix = StringBuilder()
        for i in 0..<(chars.length() / 2) {
          prefix.write_char(chars[i])
        }
        candidates.push(Json::string(prefix.to_string()))
      }
      candidates
    }
    Number(_, ..) => [Json::number(0.0), Json::number(1.0), Json::number(-1.0)]
    True => [Json::boolean(false)]
    _ => []
  }
}

///|
fn witness_cost(value : Json) -> Int32 {
  value.stringify().length()
}

///|
fn same_violation(a : Violation, b : Violation) -> Bool {
  a.pointer == b.pointer && a.keyword == b.keyword
}

///|
pub fn minimize_workflow_witness(
  catalog : Json,
  plan : Json,
  step_id : String,
  witness : Json,
) -> Json raise CheckError {
  if !verify_witness(catalog, plan, step_id, witness) {
    raise Invalid("Cannot minimize a counterexample that fails verification")
  }
  if field_at(witness, "kind") is Some(_) {
    return witness
  }
  let steps = order_steps(load_steps(catalog, plan))
  let index : Map[String, Step] = Map([])
  for step in steps {
    index.set(step.id, step)
  }
  let step = index[step_id]
  let outputs = object_value(required_member(witness, "outputs")).copy()
  let original = required_member(witness, "request")
  guard invalid_value(step.input, original, "") is Some(initial) else {
    return witness
  }
  let sources : Array[String] = []
  for name, _ in outputs {
    sources.push(name)
  }
  let mut budget = 512
  for _ in 0..<32 {
    let mut changed = false
    for name in sources {
      let given = outputs[name]
      let schema = if name == "$inputs" {
        field_at(plan, "inputs").map(expand_schema)
      } else {
        index[name].output
      }
      guard schema is Some(contract) else { continue }
      let mut best = given
      for candidate in shrink_values(given, 0) {
        budget -= 1
        if budget < 0 {
          break
        }
        if witness_cost(candidate) >= witness_cost(best) ||
          !accepts(contract, candidate) {
          continue
        }
        outputs.set(name, candidate)
        if invalid_value(step.input, assembled(step, outputs), "")
          is Some(problem) &&
          same_violation(initial, problem) {
          best = candidate
        }
      }
      outputs.set(name, best)
      if !exact_equal(given, best) {
        changed = true
      }
      if budget < 0 {
        break
      }
    }
    if !changed || budget < 0 {
      break
    }
  }
  witness_record(step, outputs, assembled(step, outputs))
}
