---
name: "Flow: Test Verify"
description: "Read-only verify of integration test design, implementation, or result evidence — hard gate; no edits"
category: Workflow
tags: [workflow, orchestration, testing, verify]
version: "0.1.0"
---

只读验证集成测试生命周期。清单：`test-verify-checklist.md`。先读 controller `status`/`next`；mode 与 phase 不匹配立即 ERROR。

**输入**：`change_name` + `verify_mode=design|implementation|result`

## 检查

1. **design**：`validate-test-artifacts.ps1 -Mode design` + `validate-test-cases.ps1 -Mode design`；TD.1–TD.11；配置探针失败 → `[TEST_CONFIGURATION] BLOCKED`
2. **implementation**：TI.1–TI.8 + validate-test-cases implementation；Java 方法绑定稳定 ID
3. **result**：仅 `next=VERIFY_RESULT`；TR.1–TR.8；须 ceiling=result

PASS 后向 controller `record-verifier` 提交结构化报告；本命令不直接改 state、不启动服务、不改 task。

## 输出

```text
[TEST_VERIFY_RESULT] PASS | WARN | ERROR
change_name: <name>
verify_mode: design | implementation | result
next: <skill or STOP_AWAIT_USER_AUTHORIZATION or blocked>
authorization_ceiling: ...
next_authorized: true | false
```
