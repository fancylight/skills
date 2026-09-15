"""Executable local integration fixture and negative acceptance tests (stdlib only)."""
import importlib.util
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
RUNNER = Path(os.environ.get("FLOW_LOCAL_RUNNER", ROOT / "codex/skills/flow-codex-check/scripts/local-delivery.py"))
VALIDATOR = Path(os.environ.get("FLOW_LOCAL_VALIDATOR", ROOT / "flow/scripts/validate-test-cases.ps1"))
SPEC = importlib.util.spec_from_file_location("local_delivery", RUNNER)
delivery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(delivery)

SOURCE = """schemaVersion: 1
scenarios:
  - id: AC-1-S1
    acceptance: AC-1
    required: true
    suite: api
    integration: Y
    business:
      purpose: Preserve quantity through storage and CSV export
      preconditions: Empty database; one sample record
      inputs: name sample; quantity 7
      steps: Deserialize JSON then insert with SQL binding and export CSV
      expected: Exactly one CSV row sample with quantity 7
      oracle: Input quantity is the independent expected value 7
      counterexamples: Binding quantity 0 must fail the CSV assertion
      evidenceBoundary: Real local SQLite and CSV; no distributed transport coverage
    testClass: example.DeliveryTest
    testMethod: roundtrip
    reportClass: example.DeliveryTest
    filter: AC-1-S1
    externalEvidence: []
    setup:
      fixtures: [local-record]
    action:
      method: POST
      path: /records
    assertions:
      response: [accepted]
      database: [quantity-preserved]
      sideEffects: [csv-content-equals-input]
    cleanup: [run-directory-only]
    observability:
      correlationField: scenario
      allowedEvidence: [result.csv, result.db, reports/result.xml]
"""

# Real serialization, SQL binding, persistence and file output. No application services.
FIXTURE = '''import csv, json, os, sqlite3, sys, time
from pathlib import Path
import xml.etree.ElementTree as ET
run = Path(os.environ["FLOW_RUN_DIR"])
mode = sys.argv[1] if len(sys.argv) > 1 else "correct"
if mode == "timeout": time.sleep(10)
if mode == "no-report": sys.exit(0)
payload = json.loads('{"name":"sample","quantity":7}')
quantity = 0 if mode == "wrong" else payload["quantity"]
with sqlite3.connect(run / "result.db") as db:
    db.execute("CREATE TABLE records (name TEXT, quantity INTEGER)")
    db.execute("INSERT INTO records VALUES (?, ?)", (payload["name"], quantity))
    rows = db.execute("SELECT name, quantity FROM records").fetchall()
with (run / "result.csv").open("w", newline="") as f:
    csv.writer(f).writerows(rows)
with (run / "result.csv").open(newline="") as f:
    exported = list(csv.reader(f))
suite = ET.Element("testsuite")
test = ET.SubElement(suite, "testcase", classname="example.DeliveryTest", name="roundtrip")
code = 0
if mode == "skip": ET.SubElement(test, "skipped")
elif mode == "error":
    ET.SubElement(test, "error", message="infrastructure failed"); code = 1
elif mode != "weak":
    try:
        assert exported == [["sample", "7"]], "quantity survives storage and export"
    except AssertionError as error:
        ET.SubElement(test, "failure", message=str(error)); code = 1
ET.ElementTree(suite).write(Path(os.environ["FLOW_TEST_REPORT_DIR"]) / "result.xml")
sys.exit(code)
'''


class LocalDeliveryTests(unittest.TestCase):
    def setUp(self):
        evidence_root = os.environ.get("FLOW_LOCAL_TEST_EVIDENCE_ROOT")
        self.temp = None if evidence_root else tempfile.TemporaryDirectory(prefix="flow-local-test-")
        self.root = Path(evidence_root) / self._testMethodName if evidence_root else Path(self.temp.name)
        if evidence_root:
            self.root.mkdir(parents=True, exist_ok=False)
        self.repo = self.root / "candidate"
        self.repo.mkdir()
        (self.repo / "fixture.py").write_text(FIXTURE, encoding="utf-8")
        for args in (["init", "-q"], ["add", "."],
                     ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                      "commit", "-qm", "local integration fixture"]):
            subprocess.run(["git", "-C", str(self.repo), *args], check=True, capture_output=True)
        (self.root / "test-cases.yaml").write_text(SOURCE, encoding="utf-8")
        command = [sys.executable, str(self.repo / "fixture.py")]
        self.plan = {"schemaVersion": 1, "review": "self", "testCases": "test-cases.yaml",
                     "candidates": {"sample": {"repo": "candidate",
                         "revision": delivery.git(self.repo, "rev-parse", "HEAD"),
                         "artifacts": ["fixture.py"]}},
                     "command": command, "timeoutSeconds": 5,
                     "probes": [{"scenario": "AC-1-S1", "risk": "lost quantity",
                         "command": command + ["wrong"],
                         "assertion": "quantity survives storage and export"}]}
        self.path = self.root / "local-delivery.json"
        self.output = self.root / "evidence"

    def tearDown(self):
        if self.temp:
            self.temp.cleanup()

    def call(self, mode="run", expected=0):
        self.path.write_text(json.dumps(self.plan), encoding="utf-8")
        proc = subprocess.run([sys.executable, str(RUNNER), mode, "--plan", str(self.path),
                               "--output", str(self.output), "--validator", str(VALIDATOR)],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, expected, proc.stdout + proc.stderr)
        return proc

    def test_real_roundtrip_probe_and_readonly_check(self):
        self.call()
        before = delivery.files(self.output)
        self.call("check")
        self.assertEqual(before, delivery.files(self.output))
        receipt = delivery.read(self.output / "receipt.json")
        self.assertFalse(receipt["flowComplete"])
        self.assertEqual(receipt["probeResults"][0]["result"], "caught")
        self.call(expected=1)  # first execution cannot be overwritten

    def test_missing_reports(self):
        self.plan["command"] += ["no-report"]
        self.call(expected=1)

    def test_skipped_test(self):
        self.plan["command"] += ["skip"]
        self.call(expected=1)

    def test_baseline_business_failure_stops_probes(self):
        self.plan["command"] += ["wrong"]
        self.call(expected=1)
        self.assertFalse((self.output / "probe-0").exists())

    def test_survived_probe(self):
        self.plan["probes"][0]["command"][-1] = "correct"
        self.call(expected=1)

    def test_invalid_probe_not_caught(self):
        self.plan["probes"][0]["command"][-1] = "error"
        self.call(expected=1)

    def test_wrong_failure_assertion(self):
        self.plan["probes"][0]["assertion"] = "unrelated assertion"
        self.call(expected=1)

    def test_dirty_candidate(self):
        (self.repo / "fixture.py").write_text("changed", encoding="utf-8")
        self.call(expected=1)

    def test_old_revision(self):
        self.plan["candidates"]["sample"]["revision"] = "0" * 40
        self.call(expected=1)

    def test_evidence_tamper(self):
        self.call()
        (self.output / "baseline/result.csv").write_text("changed")
        self.call("check", expected=1)

    def test_scenario_drift(self):
        self.call()
        with (self.root / "test-cases.yaml").open("a") as file:
            file.write("\n# changed requirement\n")
        self.call("check", expected=1)

    def test_missing_required_method(self):
        (self.root / "test-cases.yaml").write_text(SOURCE.replace("testMethod: roundtrip", "testMethod: absent"))
        self.call(expected=1)

    def test_path_escape(self):
        (self.root / "test-cases.yaml").write_text(SOURCE.replace("result.csv,", "../result.csv,"))
        self.call(expected=1)

    def test_timeout(self):
        self.plan["command"] += ["timeout"]
        self.plan["timeoutSeconds"] = 1
        self.call(expected=1)

    def test_ignored_artifact_drift(self):
        (self.repo / '.git/info/exclude').write_text('artifact.bin\n')
        (self.repo / 'artifact.bin').write_bytes(b'build-one')
        self.plan['candidates']['sample']['artifacts'].append('artifact.bin')
        self.call()
        (self.repo / 'artifact.bin').write_bytes(b'build-two')
        proc = self.call('check', expected=1)
        self.assertIn('artifact drift', proc.stdout)

    def test_handwritten_pass_cannot_hide_failed_xml(self):
        self.plan['command'] += ['wrong']
        self.call(expected=1)
        receipt = delivery.read(self.output / 'receipt.json')
        receipt['result'] = 'PASS'
        receipt['baseline']['exitCode'] = 0
        (self.output / 'receipt.json').write_text(json.dumps(receipt))
        proc = self.call('check', expected=1)
        self.assertIn('Baseline failed', proc.stdout)

    def test_missing_consumer_evidence(self):
        (self.root / 'test-cases.yaml').write_text(SOURCE.replace('result.csv,', 'consumer.json, result.csv,'))
        proc = self.call(expected=1)
        self.assertIn('Missing evidence', proc.stdout)

    def test_result_validator_local_hook(self):
        repo = self.root / 'system-test'
        change = repo / 'changes/sample'
        change.mkdir(parents=True)
        source = change / 'test-cases.yaml'
        source.write_text(SOURCE)
        self.plan['testCases'] = 'system-test/changes/sample/test-cases.yaml'
        manifest = change / 'manifest.yaml'
        manifest.write_text(json.dumps({'testCasesContract': {'path': 'test-cases.generated.json'}}))
        plan = change / 'test-plan.md'
        plan.write_text('<!-- FLOW_TEST_CASES_GENERATED:START -->\n<!-- FLOW_TEST_CASES_GENERATED:END -->')
        revision = '1' * 40
        proc = subprocess.run(['powershell.exe', '-NoProfile', '-File', str(VALIDATOR),
            '-TestCasesPath', str(source), '-Generate', '-CanonicalRevision', revision,
            '-ManifestPath', str(manifest), '-DerivedContractPath', str(change/'test-cases.generated.json'),
            '-TestPlanPath', str(plan)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        java = repo / 'backend-tests/src/test/sample/DeliveryTest.java'
        java.parent.mkdir(parents=True)
        java.write_text('package example;\nclass DeliveryTest { @TestScenarioId("AC-1-S1") void roundtrip() {} }')
        self.call()
        shutil.copytree(self.output/'baseline', change/'evidence/current')
        command = ['powershell.exe', '-NoProfile', '-File', str(VALIDATOR.parent/'validate-test-artifacts.ps1'),
            '-SystemTestRepo', str(repo), '-ChangeName', 'sample', '-Mode', 'result',
            '-CanonicalRevision', revision, '-LocalDeliveryPlan', str(self.path),
            '-LocalDeliveryEvidence', str(self.output), '-PythonExecutable', sys.executable]
        proc = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        (self.output/'baseline/result.csv').write_text('tampered')
        proc = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn('Local delivery evidence rejected', proc.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
