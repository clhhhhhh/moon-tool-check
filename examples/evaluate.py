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


def evaluate():
    rows = []
    with TemporaryDirectory() as directory:
        generated = Path(directory) / "updated.json"
        for name in ("orders", "knowledge", "report"):
            before_path = EXAMPLES / f"{name}-before.json"
            before = read(before_path)
            changed = read(EXAMPLES / f"{name}-after.json")
            annotation = copy.deepcopy(before)
            annotation["example"]["tools"][0]["description"] = "Updated wording"
            for case, updated, expected in (
                ("fault", changed, True),
                ("description", annotation, False),
                ("format", before, False),
            ):
                generated.write_text(
                    json.dumps(updated, sort_keys=True), encoding="utf-8"
                )
                command = [
                    "node", str(CLI), "compare", str(before_path), str(generated),
                    str(EXAMPLES / f"{name}-plan.json"),
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
                assert all(step["after"]["status"] != "unknown" for step in report)
                for step in failures:
                    witness = step["after"]["witness"]
                    producer, consumer = updated["example"]["tools"]
                    Draft202012Validator(producer["outputSchema"]).validate(
                        witness["outputs"]["source"]
                    )
                    assert not Draft202012Validator(consumer["inputSchema"]).is_valid(
                        witness["request"]
                    )
                rows.append({
                    "scenario": name,
                    "case": case,
                    "expected_failure": expected,
                    "text_diff": before_path.read_bytes() != generated.read_bytes(),
                    "structural_tool_diff": tool_schema_changed(before, updated),
                    "workflow_failure": bool(failures),
                    "verified_witnesses": len(failures),
                    "median_cli_ms": round(median(times), 2),
                })
    return rows


if __name__ == "__main__":
    print(json.dumps(evaluate(), indent=2))
