---
name: "Flow: Test Design"
description: "Design independent Flow integration tests after business specs are committed — test-cases.yaml SoT, no JUnit"
category: Workflow
tags: [workflow, orchestration, testing, design]
version: "0.1.0"
---

业务代码已审核提交后，设计可独立实施的集成测试。以 `test-cases.yaml` 为唯一场景源。模板：`test-design.md.tmpl`、`test-plan.md.tmpl`、`test-cases.yaml.tmpl`。脚本：`validate-test-cases.ps1`、`validate-test-artifacts.ps1`、`test-scope-guard.ps1`。

对照 Codex `flow-codex-test-design` 语义；Claude 用 `powershell -File ~/.claude/commands/flow/scripts/...`。

## 硬前置

1. `orchestrator` + `change_name`
2. 范围内业务 spec 已 review/单测/提交；`/flow:verify full` §A+§B 无 ERROR
3. 每个 SUT 记录 repo/branch/commit；未提交业务代码不得作基线
4. 读取概要设计验收、操作链路、数据访问契约、OpenSpec；不得用已写集成测试反推设计
5. controller state：不存在则可在 design 产物可提交后唯一一次 `initialize`；已存在则 next 须相容

## 步骤（摘要）

0. 解析/初始化 config 中 system-test 仓
1. 验收 → 稳定 AC-n；Y/N/Non-Goal
2. 写 `changes/<change>/test-cases.yaml`（唯一可执行场景源）→ 生成 sidecar / test-plan 标记区
3. `test-design.md` 覆盖 TDD.1–TDD.10
4. `test-plan.md` 只写背景与人工说明，不复制可执行表
5. manifest：configurationSource、requiredEndpoints、connectivityProbe、ownership、testCasesContract 等
6. 每次写 system-test 前 `test-scope-guard.ps1 -Stage design`
7. READY 前 `validate-test-cases.ps1 -Generate ...` 与 `validate-test-artifacts.ps1 -Mode design`
8. 禁止写 JUnit、改业务源码、在 design 写实际 PASS/EXPLAIN 结果

## 结果

```text
[TEST_DESIGN_RESULT] READY | BLOCKED
change_name: <name>
next: flow-test-verify design | STOP_AWAIT_USER_AUTHORIZATION
authorization_ceiling: design | ...
```

design verify PASS 后若 ceiling 仍为 design → `STOP_AWAIT_USER_AUTHORIZATION`，不得派发实现。
