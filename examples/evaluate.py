"""Reproduce the contract regression experiment with an independent validator."""
import copy
import json
from pathlib import Path
from statistics import median
from subprocess import run
from tempfile import TemporaryDirectory
from time import perf_counter

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "examples"
CLI = ROOT / "_build/js/debug/build/cmd/main/main.js"


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def tool_schema_changed(prior, updated):
    def index(document):
        return {
            (server, tool["name"]): (tool["inputSchema"], tool.get("outputSchema"))
            for server, snapshot in document.items()
            for tool in snapshot["tools"]
        }

    return index(prior) != index(updated)


def correlated_catalog(outputs):
    producer = {
        "name": "source", "inputSchema": {"type": "object"},
        "outputSchema": {"type": "object", "enum": outputs},
    }
    consumer = {
        "name": "sink",
        "inputSchema": {"enum": [{"a": value, "b": value} for value in (False, True)]},
    }
    return {"example": {"tools": [producer, consumer]}}


def correlated_plan():
    return {"steps": [
        {"id": "source", "server": "example", "tool": "source", "args": {}},
        {"id": "sink", "server": "example", "tool": "sink",
         "args": {key: {"from": "source", "pointer": "/" + key} for key in ("a", "b")}},
    ]}


def cases():
    for name in ("orders", "knowledge", "report"):
        before = read(EXAMPLES / f"{name}-before.json")
        after = read(EXAMPLES / f"{name}-after.json")
        plan = read(EXAMPLES / f"{name}-plan.json")
        annotation = copy.deepcopy(before)
        annotation["example"]["tools"][0]["description"] = "Updated wording"
        extra = copy.deepcopy(before)
        output = extra["example"]["tools"][0]["outputSchema"]
        output["properties"]["unbound_note"] = {"type": "string"}
        yield name, "fault", before, after, plan, True
        yield name, "description", before, annotation, plan, False
        yield name, "format", before, before, plan, False
        yield name, "unbound_output", before, extra, plan, False

    previous = [{"a": False, "b": False}]
    safe = previous + [{"a": True, "b": True}]
    broken = safe + [{"a": True, "b": False}]
    plan = correlated_plan()
    before = correlated_catalog(previous)
    for label, outputs in (("shared_source_safe", safe), ("shared_source_breaks", broken)):
        updated = correlated_catalog(outputs)
        producer, consumer = updated["example"]["tools"]
        validator = Draft202012Validator(consumer["inputSchema"])
        expected = any(
            not validator.is_valid(bind(plan, instance))
            for instance in producer["outputSchema"]["enum"]
        )
        yield "correlation", label, before, updated, plan, expected


def bind(plan, output):
    args = next(step["args"] for step in plan["steps"] if step["id"] == "sink")
    return {
        key: output[spec["pointer"][1:]]
        for key, spec in args.items()
        if spec["pointer"][1:] in output
    }


def evaluate():
    rows = []
    with TemporaryDirectory() as directory:
        root = Path(directory)
        before_path, after_path, plan_path = (
            root / name for name in ("before.json", "after.json", "plan.json")
        )
        for name, case, before, updated, plan, expected in cases():
            before_path.write_text(json.dumps(before, indent=2), encoding="utf-8")
            after_path.write_text(json.dumps(updated, sort_keys=True), encoding="utf-8")
            plan_path.write_text(json.dumps(plan), encoding="utf-8")
            command = [
                "node", str(CLI), "compare", str(before_path), str(after_path), str(plan_path)
            ]
            times = []
            for _ in range(5):
                start = perf_counter()
                result = run(command, capture_output=True, text=True)
                times.append((perf_counter() - start) * 1000)
            assert result.returncode == int(expected), result.stderr + result.stdout
            report = json.loads(result.stdout)
            failures = [step for step in report if step["change"] == "new_failure"]
            assert bool(failures) == expected, report
            assert all(step["before"]["status"] == "compatible" for step in report)
            assert all(step["after"]["status"] != "unknown" for step in report)
            for step in failures:
                witness = step["after"]["witness"]
                producer, consumer = updated["example"]["tools"]
                output = witness["outputs"]["source"]
                Draft202012Validator(producer["outputSchema"]).validate(output)
                assert bind(plan, output) == witness["request"]
                assert not Draft202012Validator(consumer["inputSchema"]).is_valid(
                    witness["request"]
                )
            schema_diff = run(
                ["node", str(CLI), "catalog-diff", str(before_path), str(after_path)],
                capture_output=True, text=True,
            )
            assert schema_diff.returncode in (0, 1), schema_diff.stderr
            statuses = [tool["status"] for tool in json.loads(schema_diff.stdout)]
            rows.append({
                "scenario": name,
                "case": case,
                "expected_failure": expected,
                "text_diff": before_path.read_bytes() != after_path.read_bytes(),
                "structural_tool_diff": tool_schema_changed(before, updated),
                "catalog_breaking": any(status in ("breaking", "removed") for status in statuses),
                "catalog_unknown": "unknown" in statuses,
                "workflow_failure": bool(failures),
                "verified_witnesses": len(failures),
                "median_cli_ms": round(median(times), 2),
            })
    return rows


if __name__ == "__main__":
    print(json.dumps(evaluate(), indent=2))
