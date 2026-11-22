///|
fn branch_violation(
  schema : Json,
  instance : Json,
  path : String,
) -> Violation? {
  if field_at(schema, "allOf") is Some(Array(branches)) {
    for branch in branches {
      if invalid_value(branch, instance, path) is Some(problem) {
        return Some(problem)
      }
    }
  }
  if field_at(schema, "anyOf") is Some(Array(branches)) &&
    !branches.any(branch => accepts(branch, instance)) {
    return Some(violation(path, "anyOf", "No alternative accepts the instance"))
  }
  if field_at(schema, "oneOf") is Some(Array(branches)) {
    let mut matches = 0
    for branch in branches {
      if accepts(branch, instance) {
        matches += 1
      }
    }
    if matches != 1 {
      return Some(
        violation(
          path, "oneOf", "Exactly one alternative must accept the instance",
        ),
      )
    }
  }
  if field_at(schema, "not") is Some(branch) && accepts(branch, instance) {
    return Some(violation(path, "not", "Instance matches an excluded schema"))
  }
  None
}

///|
fn without_keyword(schema : Json, ignored : String) -> Json {
  guard schema is Object(fields) else { return schema }
  let output : Map[String, Json] = Map([])
  for name, value in fields {
    if name != ignored {
      output.set(name, value)
    }
  }
  Json::object(output)
}

///|
fn composed_implication(
  source : Json,
  target : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Bool? {
  for name in ["anyOf", "oneOf"] {
    if field_at(source, name) is Some(Array(branches)) &&
      branches.all(branch => implies_at(branch, target, depth + 1, budget)) {
      return Some(true)
    }
  }
  if field_at(source, "allOf") is Some(Array(branches)) &&
    branches.any(branch => implies_at(branch, target, depth + 1, budget)) {
    return Some(true)
  }
  if field_at(target, "allOf") is Some(Array(branches)) {
    return Some(
      implies_at(source, without_keyword(target, "allOf"), depth + 1, budget) &&
      branches.all(branch => implies_at(source, branch, depth + 1, budget)),
    )
  }
  if field_at(target, "anyOf") is Some(Array(branches)) {
    return Some(
      implies_at(source, without_keyword(target, "anyOf"), depth + 1, budget) &&
      branches.any(branch => implies_at(source, branch, depth + 1, budget)),
    )
  }
  if field_at(target, "oneOf") is Some(_) || field_at(target, "not") is Some(_) {
    return Some(false)
  }
  None
}
