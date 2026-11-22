///|
fn object_domain_candidates(
  source : Json,
  target : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Array[Json] {
  let names = candidate_keys(source, target)
  let fields : Map[String, Json] = Map([])
  let variants : Array[Json] = []
  let choices : Map[String, Array[Json]] = Map([])
  for name in names {
    let options = candidate_walk(
      prop(source, name),
      prop(target, name),
      depth + 1,
      budget,
    )
    choices.set(name, options)
    if requires(source, name) {
      if options.length() == 0 {
        return []
      }
      fields.set(name, options[0])
    }
  }
  variants.push(Json::object(fields.copy()))
  let min = limit(source, "minProperties").unwrap_or(0.0)
  let target_max = limit(target, "maxProperties").unwrap_or(0.0)
  let target_min = limit(target, "minProperties").unwrap_or(0.0)
  let at_size = if min > target_max + 1.0 { min } else { target_max + 1.0 }
  if at_size <= 64.0 {
    let candidate = fields.copy()
    for name in names {
      if candidate.length().to_double() >= at_size {
        break
      }
      if choices.get(name) is Some(options) &&
        options.length() > 0 &&
        !candidate.contains(name) {
        candidate.set(name, options[0])
        if candidate.length().to_double() == min ||
          candidate.length().to_double() == target_min ||
          candidate.length().to_double() == at_size {
          variants.push(Json::object(candidate.copy()))
        }
      }
    }
  }
  for name in names {
    if choices.get(name) is Some(options) {
      for value in options {
        let variant = fields.copy()
        variant.set(name, value)
        cover_dependency(source, name, variant, choices)
        variants.push(Json::object(variant))
        if variants.length() >= 240 {
          return variants
        }
      }
    }
  }
  variants
}

///|
fn cover_dependency(
  schema : Json,
  trigger : String,
  fields : Map[String, Json],
  choices : Map[String, Array[Json]],
) -> Unit {
  guard field_at(schema, "dependentRequired") is Some(Object(dependencies)) else {
    return
  }
  let pending = [trigger]
  let mut index = 0
  while index < pending.length() {
    let key = pending[index]
    index += 1
    if dependencies.get(key) is Some(Array(names)) {
      for field in names {
        if field is String(name) &&
          !fields.contains(name) &&
          choices.get(name) is Some(options) &&
          options.length() > 0 {
          fields.set(name, options[0])
          pending.push(name)
        }
      }
    }
  }
}

///|
fn candidate_keys(source : Json, target : Json) -> Array[String] {
  let keys : Array[String] = []
  let known : Map[String, Bool] = Map([])
  for schema in [source, target] {
    let candidates : Array[String] = []
    if field_at(schema, "required") is Some(Array(names)) {
      for name in names {
        if name is String(text) {
          candidates.push(text)
        }
      }
    }
    if field_at(schema, "properties") is Some(Object(props)) {
      for name, _ in props {
        candidates.push(name)
      }
    }
    if field_at(schema, "dependentRequired") is Some(Object(dependencies)) {
      for trigger, values in dependencies {
        candidates.push(trigger)
        if values is Array(names) {
          for key in names {
            if key is String(name) {
              candidates.push(name)
            }
          }
        }
      }
    }
    for name in candidates {
      if !known.contains(name) {
        known.set(name, true)
        keys.push(name)
      }
    }
  }
  if !(field_at(source, "additionalProperties") is Some(False)) {
    let needed = limit(source, "minProperties").unwrap_or(0.0)
    let other = limit(target, "maxProperties").unwrap_or(0.0)
    let mut requested = 1
    if needed < 64.0 && needed.to_int() > requested {
      requested = needed.to_int()
    }
    if other < 64.0 && other.to_int() + 1 > requested {
      requested = other.to_int() + 1
    }
    for i in 0..<requested {
      let mut name = "extra" + i.to_string()
      while known.contains(name) {
        name += "_"
      }
      known.set(name, true)
      keys.push(name)
    }
  }
  keys
}
