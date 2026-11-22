///|
fn conditional_violation(
  schema : Json,
  instance : Json,
  path : String,
) -> Violation? {
  if field_at(schema, "if") is Some(condition) {
    let selected = if accepts(condition, instance) { "then" } else { "else" }
    if field_at(schema, selected) is Some(branch) {
      return invalid_value(branch, instance, path)
    }
  }
  None
}

///|
fn conditional_implies(
  source : Json,
  target : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Bool? {
  guard field_at(target, "if") is Some(condition) else { return None }
  let base = without_keyword(
    without_keyword(without_keyword(target, "if"), "then"),
    "else",
  )
  if !implies_at(source, base, depth + 1, budget) {
    return Some(false)
  }
  let success = field_at(target, "then").unwrap_or(Json::boolean(true))
  let fallback = field_at(target, "else").unwrap_or(Json::boolean(true))
  if implies_at(source, condition, depth + 1, budget) {
    return Some(implies_at(source, success, depth + 1, budget))
  }
  Some(
    implies_at(source, success, depth + 1, budget) &&
    implies_at(source, fallback, depth + 1, budget),
  )
}

///|
fn schema_map_supported(value : Json, depth : Int32) -> Bool {
  guard value is Object(fields) else { return false }
  for _, schema in fields {
    if !supports(schema, depth + 1) {
      return false
    }
  }
  true
}

///|
fn object_shape_violation(
  schema : Json,
  instance : Json,
  fields : Map[String, Json],
  path : String,
) -> Violation? {
  if field_at(schema, "propertyNames") is Some(names) {
    for key, _ in fields {
      if !accepts(names, Json::string(key)) {
        return Some(
          violation(
            path + "/" + escaped(key),
            "propertyNames",
            "Property name violates its contract",
          ),
        )
      }
    }
  }
  if field_at(schema, "dependentSchemas") is Some(Object(dependencies)) {
    for trigger, dependent in dependencies {
      if fields.contains(trigger) &&
        invalid_value(dependent, instance, path) is Some(problem) {
        return Some(problem)
      }
    }
  }
  None
}

///|
fn shape_implication(
  source : Json,
  target : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Bool {
  if field_at(target, "propertyNames") is Some(names) {
    let given = field_at(source, "propertyNames").unwrap_or(Json::boolean(true))
    if !implies_at(given, names, depth + 1, budget) {
      if !(field_at(source, "additionalProperties") is Some(False)) {
        return false
      }
      if field_at(source, "properties") is Some(Object(props)) {
        for key, _ in props {
          if !(prop(source, key) is False) && !accepts(names, Json::string(key)) {
            return false
          }
        }
      }
    }
  }
  if field_at(target, "dependentSchemas") is Some(Object(dependencies)) {
    let given = field_at(source, "dependentSchemas").unwrap_or(Json::null())
    for trigger, target_constraint in dependencies {
      if prop(source, trigger) is False {
        continue
      }
      let source_constraint = field_at(given, trigger).unwrap_or(
        Json::boolean(true),
      )
      if !implies_at(source_constraint, target_constraint, depth + 1, budget) &&
        !implies_at(source, target_constraint, depth + 1, budget) {
        return false
      }
    }
  }
  true
}
