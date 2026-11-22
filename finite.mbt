///|
fn finite_domain(
  schema : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Array[Json]? {
  budget.val -= 1
  if budget.val < 0 || depth > 20 {
    return None
  }
  if schema is False {
    return Some([])
  }
  if all_values(schema) is Some(Array(constraints)) {
    if constraints.length() > 128 {
      return None
    }
    return Some(constraints.filter(value => accepts(schema, value)))
  }
  let mut values : Array[Json] = []
  if !permits_type(schema, "string") &&
    !permits_type(schema, "number") &&
    !permits_type(schema, "integer") &&
    !permits_type(schema, "object") &&
    !permits_type(schema, "array") {
    for value in [Json::null(), Json::boolean(false), Json::boolean(true)] {
      if accepts(schema, value) {
        values.push(value)
      }
    }
    return Some(values)
  }
  if field_at(schema, "allOf") is Some(Array(branches)) {
    for branch in branches {
      if finite_domain(branch, depth + 1, budget) is Some(items) {
        return Some(items.filter(value => accepts(schema, value)))
      }
    }
  }
  for operator in ["anyOf", "oneOf"] {
    if field_at(schema, operator) is Some(Array(branches)) {
      let mut complete = true
      values = []
      for branch in branches {
        if finite_domain(branch, depth + 1, budget) is Some(items) &&
          values.length() + items.length() <= 128 {
          values.append(items)
        } else {
          complete = false
          break
        }
      }
      if complete {
        return Some(values.filter(value => accepts(schema, value)))
      }
    }
  }
  if field_at(schema, "type") == Some(Json::string("object")) &&
    field_at(schema, "additionalProperties") is Some(False) {
    return finite_object_domain(schema, depth, budget)
  }
  if field_at(schema, "type") == Some(Json::string("array")) {
    return finite_array_domain(schema, depth, budget)
  }
  None
}

///|
fn finite_object_domain(
  schema : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Array[Json]? {
  let names : Array[String] = []
  if field_at(schema, "properties") is Some(Object(fields)) {
    for key, _ in fields {
      names.push(key)
    }
  }
  let mut rows : Array[Map[String, Json]] = [Map([])]
  for name in names {
    let next : Array[Map[String, Json]] = []
    guard finite_domain(prop(schema, name), depth + 1, budget) is Some(domain) else {
      return None
    }
    for row in rows {
      if !requires(schema, name) {
        next.push(row)
      }
      for value in domain {
        budget.val -= 1
        if next.length() >= 128 || budget.val < 0 {
          return None
        }
        let updated = row.copy()
        updated.set(name, value)
        next.push(updated)
      }
      if next.length() > 128 {
        return None
      }
    }
    rows = next
  }
  Some(rows.map(Json::object).filter(value => accepts(schema, value)))
}

///|
fn finite_array_domain(
  schema : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Array[Json]? {
  let limit = limit(schema, "maxItems")
  let ceiling = if tail_item(schema) is False {
    let prefix = prefix_items(schema).length()
    match limit {
      Some(n) if n < prefix.to_double() => n.to_int()
      _ => prefix
    }
  } else if limit is Some(n) && n <= 16.0 {
    n.to_int()
  } else {
    return None
  }
  if ceiling > 16 {
    return None
  }
  let mut rows : Array[Array[Json]] = [[]]
  let result : Array[Json] = []
  for width in 0..<(ceiling + 1) {
    for row in rows {
      let instance = Json::array(row)
      if accepts(schema, instance) {
        if result.length() >= 128 {
          return None
        }
        result.push(instance)
      }
    }
    if width == ceiling || rows.length() == 0 {
      break
    }
    guard finite_domain(item_at(schema, width), depth + 1, budget)
      is Some(domain) else {
      return None
    }
    let next : Array[Array[Json]] = []
    for row in rows {
      for item in domain {
        budget.val -= 1
        if next.length() >= 128 || budget.val < 0 {
          return None
        }
        let variant = row.copy()
        variant.push(item)
        next.push(variant)
      }
    }
    rows = next
  }
  Some(result)
}

///|
fn complete_sources(sources : Map[String, Json]) -> Map[String, Array[Json]]? {
  let budget = Ref(4096)
  let result : Map[String, Array[Json]] = Map([])
  let mut product = 1
  for name, schema in sources {
    guard finite_domain(schema, 0, budget) is Some(domain) else { return None }
    product *= domain.length()
    if product > 1024 {
      return None
    }
    result.set(name, domain)
  }
  Some(result)
}
