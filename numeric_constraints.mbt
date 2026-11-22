///|
priv struct Endpoint {
  value : Decimal
  exclusive : Bool
}

///|
fn boundary(schema : Json, lower : Bool) -> Endpoint? {
  let inclusive_key = if lower { "minimum" } else { "maximum" }
  let exclusive_key = if lower {
    "exclusiveMinimum"
  } else {
    "exclusiveMaximum"
  }
  match
    (decimal_limit(schema, inclusive_key), decimal_limit(schema, exclusive_key)) {
    (Some(inclusive), Some(exclusive)) => {
      let order = compare_decimal(inclusive, exclusive)
      if (lower && order > 0) || (!lower && order < 0) {
        Some({ value: inclusive, exclusive: false, })
      } else {
        Some({ value: exclusive, exclusive: true, })
      }
    }
    (Some(value), None) => Some({ value, exclusive: false, })
    (None, Some(value)) => Some({ value, exclusive: true, })
    _ => None
  }
}

///|
fn endpoint_inside(
  source : Endpoint?,
  target : Endpoint?,
  lower : Bool,
) -> Bool {
  match (source, target) {
    (_, None) => true
    (None, Some(_)) => false
    (Some(actual), Some(required)) => {
      let order = compare_decimal(actual.value, required.value)
      if order == 0 {
        !required.exclusive || actual.exclusive
      } else if lower {
        order > 0
      } else {
        order < 0
      }
    }
  }
}

///|
fn empty_numeric_domain(lower : Endpoint?, upper : Endpoint?) -> Bool {
  match (lower, upper) {
    (Some(low), Some(high)) => {
      let order = compare_decimal(low.value, high.value)
      order > 0 || (order == 0 && (low.exclusive || high.exclusive))
    }
    _ => false
  }
}

///|
fn numeric_implies(source : Json, target : Json) -> Bool {
  let low = boundary(source, true)
  let high = boundary(source, false)
  if empty_numeric_domain(low, high) {
    return true
  }
  if !endpoint_inside(low, boundary(target, true), true) ||
    !endpoint_inside(high, boundary(target, false), false) {
    return false
  }
  match decimal_limit(target, "multipleOf") {
    None => true
    Some(required) =>
      match decimal_limit(source, "multipleOf") {
        Some(given) => is_multiple(given, required)
        None => false
      }
  }
}

///|
fn bounded_multiple(value : Json) -> Bool {
  decimal_value(value) is Some(d) &&
  d.sign > 0 &&
  d.digits.length() <= 24 &&
  d.power >= -24 &&
  d.power <= 24
}

///|
fn is_multiple(value : Decimal, divisor : Decimal) -> Bool {
  if value.sign == 0 {
    return true
  }
  let exponent = value.power - divisor.power
  // Normalized coefficients have no trailing zero. A lower power cannot divide.
  if exponent < 0 {
    return false
  }
  if divisor.digits.length() == 1 && divisor.digits[0] == 1 {
    return true
  }
  let modulus = coefficient(divisor.digits)
  let mut remainder = coefficient_mod(value.digits, modulus)
  let mut factor = 10N % modulus
  let mut steps = exponent
  // Binary modular exponentiation avoids materializing a giant number of zeroes.
  while steps > 0 && remainder != 0N {
    if steps % 2 == 1 {
      remainder = remainder * factor % modulus
    }
    factor = factor * factor % modulus
    steps = steps / 2
  }
  remainder == 0N
}

///|
fn coefficient(digits : Array[Int32]) -> BigInt {
  let mut result = 0N
  for digit in digits {
    result = result * 10N + [0N, 1N, 2N, 3N, 4N, 5N, 6N, 7N, 8N, 9N][digit]
  }
  result
}

///|
fn coefficient_mod(digits : Array[Int32], modulus : BigInt) -> BigInt {
  let mut result = 0N
  for digit in digits {
    result = (result * 10N + [0N, 1N, 2N, 3N, 4N, 5N, 6N, 7N, 8N, 9N][digit]) %
      modulus
  }
  result
}
