///|
extern "js" fn read_text(path : String) -> String? =
  #| path => {
  #|   try {
  #|     const fs = require("node:fs");
  #|     if (fs.statSync(path).size > 4194304) return undefined;
  #|     return fs.readFileSync(path, "utf8");
  #|   } catch (_) { return undefined; }
  #| }

///|
extern "js" fn exit_status(status : Int32) -> Unit =
  #| status => { process.exitCode = status; }

///|
extern "js" fn error_message(message : String) -> Unit =
  #| message => { console.error(message); }

///|
fn load(path : String) -> Json raise @toolcheck.CheckError {
  match read_text(path) {
    Some(text) => @toolcheck.parse_json(text)
    None => raise @toolcheck.Invalid("Unable to read " + path)
  }
}

///|
fn execute(
  args : ArrayView[String],
) -> (Json, @toolcheck.ReportKind) raise @toolcheck.CheckError {
  match args {
    ["check", catalog, plan] =>
      (@toolcheck.check_workflow(load(catalog), load(plan)), Workflow)
    ["compare", before, after, plan] =>
      (
        @toolcheck.compare_workflow(load(before), load(after), load(plan)),
        Upgrade,
      )
    ["export-witnesses", catalog, plan] =>
      (@toolcheck.export_witnesses(load(catalog), load(plan)), Bundle)
    ["replay", catalog, plan, bundle] =>
      (
        @toolcheck.verify_witnesses(load(catalog), load(plan), load(bundle)),
        Instance,
      )
    ["verify-upgrade", catalog, plan, report] =>
      (
        @toolcheck.verify_upgrade_witnesses(
          load(catalog),
          load(plan),
          load(report),
        ),
        Instance,
      )
    ["verify", catalog, plan, step, witness] =>
      (
        Json::boolean(
          @toolcheck.verify_witness(
            load(catalog),
            load(plan),
            step,
            load(witness),
          ),
        ),
        Verify,
      )
    ["explain-upgrade", before, after, plan] =>
      (
        @toolcheck.explain_upgrade(load(before), load(after), load(plan)),
        Instance,
      )
    ["catalog-diff", before, after] =>
      (@toolcheck.compare_catalogs(load(before), load(after)), Catalog)
    ["audit", catalog, suite] =>
      (@toolcheck.audit_workflows(load(catalog), load(suite)), Suite)
    ["compare-suite", before, after, suite] =>
      (
        @toolcheck.compare_workflows(load(before), load(after), load(suite)),
        SuiteUpgrade,
      )
    ["audit-samples", catalog, samples] =>
      (@toolcheck.audit_samples(load(catalog), load(samples)), Instance)
    ["compare-samples", before, after, samples] =>
      (
        @toolcheck.compare_samples(load(before), load(after), load(samples)),
        Instance,
      )
    ["inspect", catalog] =>
      (@toolcheck.inspect_catalog(load(catalog)), Instance)
    ["inspect-schema", schema] =>
      (@toolcheck.inspect_schema(load(schema)), Instance)
    ["compare-trace", before, after, plan, trace] =>
      (
        @toolcheck.compare_trace(
          load(before),
          load(after),
          load(plan),
          load(trace),
        ),
        Instance,
      )
    ["trace", catalog, plan, trace] =>
      (@toolcheck.check_trace(load(catalog), load(plan), load(trace)), Instance)
    ["validate", schema, instance] =>
      (@toolcheck.explain_instance(load(schema), load(instance)), Instance)
    _ =>
      raise @toolcheck.Invalid(
        "Usage: [--strict] check CATALOG PLAN | compare BEFORE AFTER PLAN | verify CATALOG PLAN STEP WITNESS | explain-upgrade BEFORE AFTER PLAN | export-witnesses CATALOG PLAN | replay CATALOG PLAN BUNDLE | verify-upgrade CATALOG PLAN REPORT | catalog-diff BEFORE AFTER | audit CATALOG SUITE | compare-suite BEFORE AFTER SUITE | audit-samples CATALOG SAMPLES | compare-samples BEFORE AFTER SAMPLES | inspect CATALOG | inspect-schema SCHEMA | trace CATALOG PLAN TRACE | compare-trace BEFORE AFTER PLAN TRACE | validate SCHEMA INSTANCE",
      )
  }
}

///|
fn main {
  let args = @env.args()
  let strict = args.length() > 2 && args[2] == "--strict"
  let policy : @toolcheck.CheckPolicy = if strict { Strict } else { Default }
  let offset = if strict { 3 } else { 2 }
  try {
    let (result, kind) = execute(args[offset:])
    println(result.stringify())
    exit_status(@toolcheck.report_exit_status(result, kind, policy))
  } catch {
    @toolcheck.Invalid(message) => {
      error_message(message)
      exit_status(2)
    }
  }
}
