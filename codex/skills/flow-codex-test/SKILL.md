---
name: flow-codex-test
description: 集成测试代码就绪后，门禁校验并委托 flow-codex-system-test 执行 runner，更新 task 检查清单。用户要求运行 Flow 集成测试时使用。
---

# Codex Flow 集成测试编排

作为根编排 agent 执行。读取 `../flow-codex-core/references/platform.md` 和
`../flow-codex-core/assets/templates/integration-test-result.md.tmpl`。

## 前置（硬门禁）

1. 要求根角色为 `orchestrator`，并明确提供 `change_name`。
2. `flow-codex-verify` **全量（§A+§B）** 已成功且无 ERROR。
3. 根 config 可解析 system-test 服务仓，且 `changes/<change_name>/manifest.yaml` 与 `test-plan.md` 存在。
4. `task.md` 中 `st-api-<change_name>` 已完成，**或**用户明示跳过 test-assign、由根代跑。
5. 测试仓或 manifest 缺失时 **停止**；提示 `flow-codex-test-design`，不要临时拼凑命令。

## 编排

1. 读取 manifest / test-plan / 概要设计验收表。
2. **委托 `flow-codex-system-test`** 执行 doctor → run（suite 默认 manifest 声明或 `api`）。
   将 `change_name` 与可选 `suite` 传入；由该 skill 写 evidence 与 `集成测试.md`。
3. 收到 `[SYSTEM_TEST_RESULT]` 后：
   - PASS：勾选 task.md 完成检查清单 `集成测试执行 PASS`；输出 `[INTEGRATION_TEST_RESULT] PASS`（字段与
     system-test 一致）。
   - FAIL：不勾选清单；输出 `[INTEGRATION_TEST_RESULT] FAIL` 并保留 cleanup 指引。
4. 可选：委托子 agent 仅运行 `flow-codex-system-test`，根 agent 汇总并更新 checklist。

## 与 system-test 的分工

| Skill | 职责 |
|-------|------|
| `flow-codex-test`（本 skill） | 门禁、task 检查清单、INTEGRATION_TEST_RESULT |
| `flow-codex-system-test` | runner 命令、evidence、`集成测试.md` 正文 |

不要在本 skill 内重复拼 `system-test.ps1` 命令；统一走 `flow-codex-system-test`。

作为根编排 agent 时不要修改业务代码。
