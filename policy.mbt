///|
pub(all) enum CheckPolicy {
  Default
  Strict
}

///|
pub(all) enum ReportKind {
  Bundle
  Workflow
  Upgrade
  Catalog
  Suite
  SuiteUpgrade
  Verify
  Instance
}

///|
pub fn report_exit_status(
  report : Json,
  kind : ReportKind,
  policy : CheckPolicy,
) -> Int32 raise CheckError {
  match kind {
    Bundle => 0
    Verify => if report is True { 0 } else { 1 }
    Workflow => workflow_exit(report, policy)
    Upgrade => upgrade_exit(report, policy)
    Catalog => catalog_exit(report, policy)
    Suite => {
      let counts = required_member(report, "counts")
      if positive_count(counts, "incompatible") ||
        (policy is Strict && positive_count(counts, "unknown")) {
        1
      } else {
        0
      }
    }
    SuiteUpgrade => {
      let groups = array_value(required_member(report, "workflows"))
      for group in groups {
        if upgrade_exit(required_member(group, "changes"), policy) != 0 {
          return 1
        }
      }
      0
    }
    Instance => {
      let status = status_of(report)
      if status == "invalid" || (policy is Strict && status == "unknown") {
        1
      } else {
        0
      }
    }
  }
}

///|
fn positive_count(counts : Json, key : String) -> Bool {
  field_at(counts, key) is Some(Number(n, ..)) && n > 0.0
}

///|
fn workflow_exit(rows : Json, policy : CheckPolicy) -> Int32 raise CheckError {
  for row in array_value(rows) {
    let status = status_of(row)
    if status == "incompatible" || (policy is Strict && status == "unknown") {
      return 1
    }
  }
  0
}

///|
fn upgrade_exit(rows : Json, policy : CheckPolicy) -> Int32 raise CheckError {
  for row in array_value(rows) {
    let change = string_value(required_member(row, "change"))
    if change == "new_failure" {
      return 1
    }
    if policy is Strict && status_of(required_member(row, "after")) == "unknown" {
      return 1
    }
  }
  0
}

///|
fn catalog_exit(rows : Json, policy : CheckPolicy) -> Int32 raise CheckError {
  for row in array_value(rows) {
    let status = status_of(row)
    if status == "removed" ||
      status == "breaking" ||
      (policy is Strict && status == "unknown") {
      return 1
    }
  }
  0
}
