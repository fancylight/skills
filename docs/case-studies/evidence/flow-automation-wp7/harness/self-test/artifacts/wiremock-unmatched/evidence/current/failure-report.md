# Integration Test Failure Triage

- revisions and manifest hash: see ../summary.md
- JUnit executed: unavailable
- passed / failed / skipped: 0 / 1 / 0
- first runner error: [TEST_HARNESS] WireMock unmatched request

## Failures

| Scenario | Test method | Category | Certainty | First evidence | Summary |
|---|---|---|---|---|---|
| unmapped | unavailable | UNDETERMINED | suspected | none | Raw report was not produced; collect only read-only diagnostics. |

## Undetermined boundary

- UNDETERMINED permits only read-only diagnostic evidence; do not guess a business defect or auto-modify code, configuration, or fixtures.
- Only SUT_BUSINESS with confirmed certainty may seed a separate business Flow.
- Do not rerun the current revision. Any repair or diagnostic improvement requires a new revision and implementation verify.
