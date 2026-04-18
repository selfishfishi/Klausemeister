#!/usr/bin/env python3
"""
Regression tests for schedule.py — fixture-driven.

Each `*.input.json` file alongside this script defines a scheduling
scenario. Its sibling `*.expected.json` holds the expected output. The
runner diffs actual vs expected and exits non-zero on mismatch.

Run directly:
    python3 klause-workflow/scripts/tests/run_tests.py

Or via make (no make target yet — add one if CI starts running these).
"""

import json
import pathlib
import subprocess
import sys


def load_fixtures(fixtures_dir: pathlib.Path):
    for input_path in sorted(fixtures_dir.glob("*.input.json")):
        name = input_path.name.removesuffix(".input.json")
        expected_path = fixtures_dir / f"{name}.expected.json"
        if not expected_path.exists():
            raise FileNotFoundError(
                f"fixture {name} has .input.json but no .expected.json"
            )
        yield name, input_path, expected_path


def run_schedule(script_path: pathlib.Path, input_json: str) -> dict:
    result = subprocess.run(  # noqa: S603 — trusted local script
        [sys.executable, str(script_path)],
        input=input_json,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"schedule.py exited {result.returncode}:\n"
            f"stdout={result.stdout!r}\nstderr={result.stderr!r}"
        )
    return json.loads(result.stdout)


def diff_summary(actual: dict, expected: dict) -> str:
    """Compact JSON diff for CLI readability."""
    return (
        f"  expected:\n{json.dumps(expected, indent=2, sort_keys=True)}\n"
        f"  actual:\n{json.dumps(actual, indent=2, sort_keys=True)}"
    )


def main() -> int:
    here = pathlib.Path(__file__).resolve().parent
    script = here.parent / "schedule.py"
    if not script.exists():
        print(f"FAIL: schedule.py not found at {script}")
        return 1

    fixtures = list(load_fixtures(here))
    if not fixtures:
        print("FAIL: no fixtures discovered")
        return 1

    failures: list[str] = []
    for name, input_path, expected_path in fixtures:
        input_json = input_path.read_text()
        expected = json.loads(expected_path.read_text())
        try:
            actual = run_schedule(script, input_json)
        except RuntimeError as exc:
            failures.append(f"{name}: {exc}")
            print(f"FAIL: {name} — script errored")
            continue

        if actual == expected:
            print(f"PASS: {name}")
        else:
            failures.append(f"{name}\n{diff_summary(actual, expected)}")
            print(f"FAIL: {name}")

    print()
    print(f"{len(fixtures) - len(failures)}/{len(fixtures)} passed")
    if failures:
        print("\n".join(failures))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
