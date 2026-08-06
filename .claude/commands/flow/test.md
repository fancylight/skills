---
name: "Flow: Test"
description: "Root orchestration entry for integration tests — reads flow-test-controller next and runs exactly one allowed action"
category: Workflow
tags: [workflow, orchestration, multi-agent, testing]
version: "0.4.0"
---

根集成测试编排入口。协议：`control-plane.md` §4 + controller 脚本 `~/.claude/commands/flow/scripts/flow-test-controller.ps1`。

**输入**：`/flow:test [change-name]`

每轮**只**执行 controller `next` 返回的一个动作。`BLOCKED` 立即停止；`COMPLETE` 才输出完成。不得按本文叙述顺序自行跨阶段。

---

**前置**

1. `role: orchestrator`，提供 `change_name`
2. 解析 system-test 仓（根 config `type: system-test`）与 `.flow/changes/<change>/automation-state.yaml`
3. 先运行 flow-test-controller.ps1 的 `status` / `next`（参数以脚本实际 param 为准）

---

**next → 唯一动作**

| next | 动作 |
|------|------|
| VERIFY_DESIGN | `/flow:test-verify design` |
| ISSUE_IMPLEMENTATION_LEASE | `/flow:test-assign`（controller issue-lease） |
| AWAIT_IMPLEMENTATION_RESULT | 等待持租约 agent receive/apply/report |
| VERIFY_IMPLEMENTATION | `/flow:test-verify implementation` |
| VERIFY_ENVIRONMENT | 认证 harness 最小环境验证 + record-verifier environment |
| RUN_ONCE / AWAIT_RUN_RESULT | `/flow:system-test` orchestrated → record-run |
| VERIFY_RESULT | `/flow:test-verify result` |
| COMPLETE / BLOCKED | 完成或停止 |

业务全量 `/flow:verify full`（§A+§B）无 ERROR 是进入 test-design 的前置（见 test-design）。

---

**废弃路径（迁移）**

旧「委托 test_command / 手写 E2E HTTP」不再作为主路径。服务级单测仍在 `/flow:apply`。详见 `docs/claude-lease-migration.md`。

---

**约束**

- Goal 只能执行 controller 返回的一个动作
- runner PASS ≠ Flow complete；须 result verify PASS
- 不在根上下文编写测试代码
