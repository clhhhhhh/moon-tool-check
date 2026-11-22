///|
test "integer inputs are accepted by a number contract" {
  let source = parse_json("{\"type\":\"integer\",\"minimum\":1}")
  let target = parse_json("{\"type\":\"number\",\"minimum\":0}")
  assert_true(compare_schemas(source, target) is Compatible)
}

///|
test "an exclusive bound rejects the old endpoint" {
  let source = parse_json("{\"type\":\"integer\",\"minimum\":0}")
  let target = parse_json("{\"type\":\"integer\",\"exclusiveMinimum\":0}")
  assert_true(compare_schemas(source, target) is Incompatible(_))
}

///|
test "unsupported constraints remain unknown" {
  let schema = parse_json("{\"type\":\"string\",\"pattern\":\"^x$\"}")
  assert_true(compare_schemas(schema, schema) is Unknown(_))
}

///|
test "JSON Pointer handles escaped keys" {
  let value = parse_json("{\"a/b\":{\"~\":null}}")
  assert_true(resolve(value, pointer_tokens("/a~1b/~0")) is Some(Null))
}

///|
test "validated object witness omits a previously optional property" {
  let source = parse_json("{\"type\":\"object\"}")
  let target = parse_json("{\"type\":\"object\",\"required\":[\"id\"]}")
  match compare_schemas(source, target) {
    Incompatible(value) => {
      assert_eq(validate_instance(source, value), Some(true))
      assert_eq(validate_instance(target, value), Some(false))
    }
    _ => fail("expected a counterexample")
  }
}
