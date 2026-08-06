---
name: "Flow: Test Apply"
description: "Implement st-api tests in system-test repo under lease + scope guard; emit REVIEW_REQUEST / REPORT_REQUEST"
category: Workflow
tags: [workflow, orchestration, testing, executor]
version: "0.1.0"
---

在 system-test 仓按已验证设计实现 JUnit/fixtures/stubs。每次写/测/提交前：controller `validate-lease` + `test-scope-guard.ps1`。

- 禁止改业务仓
- review PASS 前只允许 test-compile/静态发现
- 返回 REVIEW_REQUEST（design_path = test-design+test-plan+manifest）
- PASS 且静态校验+提交后 REPORT_REQUEST
- 外部 evidence 缺失 → `[TEST_EXTERNAL_EVIDENCE] BLOCKED`，不改业务
