///|
fn required_dependencies_ok(value : Json) -> Bool {
  guard value is Object(dependencies) else { return false }
  for _, names in dependencies {
    if !(names is Array(keys) && keys.all(key => key is String(_))) {
      return false
    }
  }
  true
}

///|
fn object_violation(
  schema : Json,
  fields : Map[String, Json],
  path : String,
) -> Violation? {
  if length_violation(
      schema,
      fields.length(),
      path,
      "minProperties",
      "maxProperties",
    )
    is Some(problem) {
    return Some(problem)
  }
  if field_at(schema, "dependentRequired") is Some(Object(dependencies)) {
    for trigger, names in dependencies {
      if fields.contains(trigger) && names is Array(keys) {
        for key in keys {
          if key is String(name) && !fields.contains(name) {
            return Some(
              violation(
                path + "/" + escaped(name),
                "dependentRequired",
                "Required when property " + trigger + " is present",
              ),
            )
          }
        }
      }
    }
  }
  None
}

///|
fn object_constraints_imply(source : Json, target : Json) -> Bool {
  if !bounds_inside(source, target, "minProperties", true) ||
    !bounds_inside(source, target, "maxProperties", false) {
    return false
  }
  if field_at(target, "dependentRequired") is Some(Object(dependencies)) {
    let source_dependencies = field_at(source, "dependentRequired").unwrap_or(
      Json::null(),
    )
    for trigger, names in dependencies {
      if prop(source, trigger) is False {
        continue
      }
      if names is Array(keys) {
        for key in keys {
          if key is String(name) && name != trigger && !requires(source, name) {
            match field_at(source_dependencies, trigger) {
              Some(Array(implied)) if implied.contains(key) => ()
              _ => return false
            }
          }
        }
      }
    }
  }
  true
}
