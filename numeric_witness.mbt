///|
fn zero_padded_integer(d : Decimal, power : Int32) -> BigInt? {
  if d.sign == 0 {
    return Some(0N)
  }
  let shift = d.power - power
  if shift < 0 || shift > 96 || d.digits.length() > 96 {
    return None
  }
  let mut result = coefficient(d.digits)
  for _ in 0..<shift {
    result *= 10N
  }
  Some(if d.sign < 0 { -result } else { result })
}

///|
fn number_from_coefficient(value : BigInt, power : Int32) -> Json? {
  let text = value.to_string() + "e" + power.to_string()
  let node = parse_json(text) catch { _ => return None }
  if decimal_value(node) is Some(_) {
    Some(node)
  } else {
    None
  }
}

///|
fn nearby_numeric_values(bound : Json) -> Array[Json] {
  guard decimal_value(bound) is Some(decimal) else { return [] }
  let results = [bound]
  let precision = if decimal.power < 0 { decimal.power - 1 } else { -1 }
  if precision < -4096 || decimal.power > 4096 {
    return results
  }
  if zero_padded_integer(decimal, precision) is Some(value) {
    for delta in [-1N, 1N] {
      if number_from_coefficient(value + delta, precision) is Some(neighbor) {
        results.push(neighbor)
      }
    }
  }
  if zero_padded_integer(decimal, 0) is Some(integer) {
    for delta in [-1N, 1N] {
      if number_from_coefficient(integer + delta, 0) is Some(neighbor) {
        results.push(neighbor)
      }
    }
  }
  results
}

///|
fn midpoint_numerical(a : Decimal, b : Decimal) -> Json? {
  if compare_decimal(a, b) >= 0 {
    return None
  }
  let power = if a.power < b.power { a.power } else { b.power }
  if power < -4096 || power > 4096 {
    return None
  }
  guard zero_padded_integer(a, power) is Some(left) &&
    zero_padded_integer(b, power) is Some(right) else {
    return None
  }
  number_from_coefficient((left + right) * 5N, power - 1)
}

///|
fn numeric_candidates(source : Json, target : Json) -> Array[Json] {
  let samples : Array[Json] = []
  for schema in [source, target] {
    for key in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"] {
      if field_at(schema, key) is Some(bound) {
        samples.append(nearby_numeric_values(bound))
      }
    }
    if boundary(schema, true) is Some(lower) &&
      boundary(schema, false) is Some(upper) &&
      midpoint_numerical(lower.value, upper.value) is Some(midpoint) {
      samples.push(midpoint)
    }
    if decimal_limit(schema, "multipleOf") is Some(divisor) {
      let coefficient_value = coefficient(divisor.digits)
      for factor in [-2N, -1N, 1N, 2N, 3N] {
        if number_from_coefficient(factor * coefficient_value, divisor.power)
          is Some(sample) {
          samples.push(sample)
        }
      }
    }
  }
  samples
}
