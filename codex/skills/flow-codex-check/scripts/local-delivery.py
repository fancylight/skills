"""Run project-owned tests and verify local evidence; never change Flow controller state."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def child(root, name):
    path = (root / name).resolve()
    require(path.is_relative_to(root.resolve()), f"Path escapes run directory: {name}")
    return path


def git(repo, *args):
    return subprocess.check_output(["git", "--no-optional-locks", "-C", str(repo), *args], stderr=subprocess.PIPE).decode().strip()


def snapshot(plan, base):
    result = {}
    require(bool(plan["candidates"]), "No candidates")
    for name, item in plan["candidates"].items():
        repo = (base / item["repo"]).resolve()
        head = git(repo, "rev-parse", "HEAD")
        require(head == item["revision"], f"Candidate revision changed: {name}")
        require(not git(repo, "status", "--porcelain"), f"Candidate has uncommitted files: {name}")
        require(bool(item["artifacts"]), f"Missing artifact binding: {name}")
        result[name] = {"revision": head, "artifacts": {
            file: digest(repo / file) for file in item["artifacts"]}}
    return result


def source(plan, base, validator, powershell):
    path = (base / plan["testCases"]).resolve()
    proc = subprocess.run([powershell, "-NoProfile", "-File", str(validator),
                           "-TestCasesPath", str(path), "-ExportJson"],
                          capture_output=True, text=True, encoding="utf-8", timeout=60)
    require(proc.returncode == 0, "Canonical validator rejected test-cases: " + proc.stdout + proc.stderr)
    doc = json.loads(proc.stdout.lstrip("\ufeff"))
    cases = {s["id"]: s for s in doc["scenarios"]}
    require(bool(cases), "No scenarios")
    return path, cases


def report_tests(directory):
    files = list(directory.rglob("*.xml"))
    require(bool(files), "Missing fresh JUnit XML")
    result = {}
    for file in files:
        root = ET.parse(file).getroot()
        require(root.tag in ("testsuite", "testsuites"), "Not a JUnit report")
        for case in root.iter("testcase"):
            key = (case.get("classname"), case.get("name"))
            require(key not in result, f"Duplicate test result: {key}")
            result[key] = case
    require(bool(result), "Zero tests")
    return result


def binding(case, plan):
    if case["integration"] == "Y":
        return case["testClass"], case["testMethod"]
    explicit = plan.get("externalBindings", {}).get(case["id"])
    require(bool(explicit), f"External scenario needs executable assertion: {case['id']}")
    return explicit["class"], explicit["method"]


def execute(command, base, directory, timeout, environment=None):
    directory.mkdir(parents=True, exist_ok=False)
    (directory / "reports").mkdir()
    env = os.environ.copy()
    env.update(environment or {})
    env.update(FLOW_RUN_DIR=str(directory), FLOW_TEST_REPORT_DIR=str(directory / "reports"))
    require(isinstance(command, list) and all(isinstance(s, str) for s in command) and command,
            "Command must be an argv array, not shell text")
    require(0 < timeout <= 3600, "Timeout must be between 1 and 3600 seconds")
    start = time.monotonic()
    with (directory / "command.log").open("wb") as log:
        proc = subprocess.Popen(command, cwd=base, env=env, stdout=log, stderr=subprocess.STDOUT,
                                start_new_session=os.name != "nt")
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
            else:
                import signal
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            raise ValueError("Command timeout; process tree terminated")
    return {"exitCode": code, "seconds": time.monotonic() - start}


def assess(plan, cases, directory, receipt):
    require(receipt["baseline"]["exitCode"] == 0, "Baseline command failed")
    tests = report_tests(directory / "baseline" / "reports")
    for key, case in tests.items():
        require(not any(case.find(tag) is not None for tag in ("failure", "error", "skipped")),
                f"Baseline failed or skipped: {key}")
    outcomes = {}
    for sid, case in cases.items():
        if not case["required"]:
            continue
        require(binding(case, plan) in tests, f"Required scenario not executed: {sid}")
        paths = case["observability"]["allowedEvidence"] + case.get("externalEvidence", [])
        for path in paths:
            evidence = child(directory / "baseline", path)
            require(evidence.is_file() and evidence.stat().st_size > 0, f"Missing evidence for {sid}: {path}")
        outcomes[sid] = "PASS"
    require(bool(outcomes), "No required scenarios")
    probes = []
    for index, probe in enumerate(plan.get("probes", [])):
        require(probe["scenario"] in outcomes, "Probe must bind a required scenario")
        run = receipt["probes"][index]
        entries = report_tests(directory / f"probe-{index}" / "reports")
        case = entries.get(binding(cases[probe["scenario"]], plan))
        require(case is not None and case.find("error") is None and case.find("skipped") is None,
                "Probe invalid: missing test, error or skipped")
        failure = case.find("failure")
        text = "" if failure is None else " ".join([failure.get("message", ""), failure.text or ""])
        marker = probe["assertion"]
        require(bool(marker.strip()), "Empty expected assertion")
        caught = run["exitCode"] != 0 and failure is not None and marker in text
        probes.append({"scenario": probe["scenario"], "risk": probe["risk"],
                       "result": "caught" if caught else "survived"})
        require(caught, f"Critical probe survived or failed at wrong assertion: {probe['risk']}")
    return outcomes, probes


def files(directory):
    return {str(p.relative_to(directory)): digest(p) for p in directory.rglob("*")
            if p.is_file() and p != directory / "receipt.json"}


def run(plan_path, output, validator, powershell):
    plan, base = read(plan_path), plan_path.parent
    require(plan.get("schemaVersion") == 1, "Unsupported local plan version")
    require(plan.get("review") in ("self", "independent"), "Declare review mode")
    source_path, cases = source(plan, base, validator, powershell)
    before = snapshot(plan, base)
    require(not output.exists(), "Run directory must be new; preserve first results")
    for item in plan["candidates"].values():
        require(not output.is_relative_to((base / item["repo"]).resolve()), "Evidence must be outside candidate repos")
    output.mkdir(parents=True)
    receipt = {"schemaVersion": 1, "kind": "flow-local-delivery", "runId": str(uuid.uuid4()),
               "result": "FAIL", "scope": "local-declared-scenarios", "flowComplete": False,
               "review": plan["review"], "planHash": digest(plan_path), "sourceHash": digest(source_path),
               "runnerHash": digest(__file__), "validatorHash": digest(validator),
               "candidates": before, "startedAt": time.time(), "probes": []}
    try:
        receipt["baseline"] = execute(plan["command"], base, output / "baseline", plan["timeoutSeconds"])
        # Never run error probes until the same baseline has passed all assertions.
        baseline_plan = dict(plan, probes=[])
        receipt["scenarios"], _ = assess(baseline_plan, cases, output, receipt)
        for index, probe in enumerate(plan.get("probes", [])):
            receipt["probes"].append(execute(probe["command"], base, output / f"probe-{index}",
                                             plan["timeoutSeconds"], probe.get("environment")))
        receipt["scenarios"], receipt["probeResults"] = assess(plan, cases, output, receipt)
        require(snapshot(plan, base) == before, "Candidate changed during run")
        require(digest(plan_path) == receipt["planHash"] and digest(source_path) == receipt["sourceHash"],
                "Plan or scenarios changed during run")
        receipt["result"] = "PASS"
    except (ValueError, OSError, ET.ParseError, KeyError, TypeError) as error:
        receipt["error"] = str(error)
    receipt["finishedAt"] = time.time()
    receipt["files"] = files(output)
    (output / "receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"result": receipt["result"], "receipt": str(output / "receipt.json"),
                      "error": receipt.get("error"), "flowComplete": False}, ensure_ascii=False))
    return 0 if receipt["result"] == "PASS" else 1


def check(plan_path, output, validator, powershell):
    plan, receipt = read(plan_path), read(output / "receipt.json")
    source_path, cases = source(plan, plan_path.parent, validator, powershell)
    require(receipt["kind"] == "flow-local-delivery" and receipt["result"] == "PASS", "Run did not pass")
    require(receipt["runnerHash"] == digest(__file__) and receipt["validatorHash"] == digest(validator), "Execution tooling drift")
    require(digest(plan_path) == receipt["planHash"] and digest(source_path) == receipt["sourceHash"], "Plan/scenario drift")
    require(snapshot(plan, plan_path.parent) == receipt["candidates"], "Candidate/artifact drift")
    require(files(output) == receipt["files"], "Evidence missing or changed")
    assess(plan, cases, output, receipt)
    print(json.dumps({"result": "PASS", "scope": "local-declared-scenarios", "flowComplete": False,
                      "review": plan["review"], "scenarios": list(receipt["scenarios"])}))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("run", "check"))
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--validator", type=Path, required=True)
    parser.add_argument("--powershell", default="powershell.exe" if os.name == "nt" else "pwsh")
    args = parser.parse_args()
    try:
        return (run if args.mode == "run" else check)(args.plan.resolve(), args.output.resolve(),
                                                       args.validator.resolve(), args.powershell)
    except (ValueError, OSError, KeyError, TypeError, ET.ParseError, subprocess.SubprocessError) as error:
        print(json.dumps({"result": "FAIL", "error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
