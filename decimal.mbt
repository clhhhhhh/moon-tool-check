///|
priv struct Decimal {
  sign : Int32
  digits : Array[Int32]
  power : Int32
}

///|
fn decimal_value(value : Json) -> Decimal? {
  match value {
    Number(number, repr~) => {
      let text = match repr {
        Some(s) => s
        None => {
          if number != number ||
            number > 1.7976931348623157e308 ||
            number < -1.7976931348623157e308 {
            return None
          }
          number.to_string()
        }
      }
      decimal_parse(text)
    }
    _ => None
  }
}

///|
fn ascii_digit(c : Char) -> Int32? {
  if c < '0' || c > '9' {
    None
  } else {
    Some(c.to_int() - '0'.to_int())
  }
}

///|
fn decimal_parse(text : String) -> Decimal? {
  let chars = text.to_array()
  if chars.length() == 0 || chars.length() > 1024 {
    return None
  }
  let negative = chars[0] == '-'
  let mut i = if negative { 1 } else { 0 }
  let coefficients : Array[Int32] = []
  let mut fraction = 0
  let mut dot = false
  let mut whole = 0
  while i < chars.length() && chars[i] != 'e' && chars[i] != 'E' {
    if chars[i] == '.' {
      if dot || whole == 0 {
        return None
      }
      dot = true
    } else if ascii_digit(chars[i]) is Some(digit) {
      coefficients.push(digit)
      if dot {
        fraction += 1
      } else {
        whole += 1
      }
    } else {
      return None
    }
    i += 1
  }
  if whole == 0 || (dot && fraction == 0) {
    return None
  }
  let mut exponent = 0
  if i < chars.length() {
    i += 1
    let mut negative_exponent = false
    if i < chars.length() && (chars[i] == '-' || chars[i] == '+') {
      negative_exponent = chars[i] == '-'
      i += 1
    }
    if i == chars.length() {
      return None
    }
    while i < chars.length() {
      guard ascii_digit(chars[i]) is Some(digit) else { return None }
      exponent = exponent * 10 + digit
      if exponent > 100000 {
        return None
      }
      i += 1
    }
    if negative_exponent {
      exponent = -exponent
    }
  }
  let mut first = 0
  let mut last = coefficients.length()
  while first < last && coefficients[first] == 0 {
    first += 1
  }
  if first == last {
    return Some({ sign: 0, digits: [], power: 0, })
  }
  while last > first && coefficients[last - 1] == 0 {
    last -= 1
  }
  let significant : Array[Int32] = []
  for j in first..<last {
    significant.push(coefficients[j])
  }
  Some({
    sign: if negative {
      -1
    } else {
      1
    },
    digits: significant,
    power: exponent - fraction + coefficients.length() - last,
  })
}

///|
fn compare_decimal(a : Decimal, b : Decimal) -> Int32 {
  if a.sign != b.sign {
    return a.sign.compare(b.sign)
  }
  if a.sign == 0 {
    return 0
  }
  let a_size = a.digits.length() + a.power
  let b_size = b.digits.length() + b.power
  if a_size != b_size {
    return a.sign * a_size.compare(b_size)
  }
  let length = if a.digits.length() > b.digits.length() {
    a.digits.length()
  } else {
    b.digits.length()
  }
  for i in 0..<length {
    let left = if i < a.digits.length() { a.digits[i] } else { 0 }
    let right = if i < b.digits.length() { b.digits[i] } else { 0 }
    if left != right {
      return a.sign * left.compare(right)
    }
  }
  0
}

///|
fn exact_equal(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Number(_, ..), Number(_, ..)) =>
      match (decimal_value(a), decimal_value(b)) {
        (Some(left), Some(right)) => compare_decimal(left, right) == 0
        _ => false
      }
    (Array(left), Array(right)) => {
      if left.length() != right.length() {
        return false
      }
      for i, value in left {
        if !exact_equal(value, right[i]) {
          return false
        }
      }
      true
    }
    (Object(left), Object(right)) => {
      if left.length() != right.length() {
        return false
      }
      for key, value in left {
        guard right.get(key) is Some(other) else { return false }
        if !exact_equal(value, other) {
          return false
        }
      }
      true
    }
    _ => a == b
  }
}

///|
fn decimal_limit(schema : Json, key : String) -> Decimal? {
  field_at(schema, key).bind(decimal_value)
}
