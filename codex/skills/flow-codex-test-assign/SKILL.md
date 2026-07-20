---
name: flow-codex-test-assign
description: 向 glm-system-test 派发 st-api 集成测试 spec。在 flow-codex-test-design READY 后使用。不修改 flow-codex-assign 业务派发链路。
---

# Codex Flow 集成测试派发

作为根编排 agent 执行。读取 `../flow-codex-core/references/platform.md`、
`../flow-codex-core/references/checkpoints.md` 和 `references/scheduler.md`。使用
`../flow-codex-core/assets/templates/test-child-agent-prompt.md`。

## 派发前检查

1. 要求根角色为 `orchestrator`，并明确提供 `change_name`。
2. `flow-codex-verify` 全量 §A+§B 已成功且无 ERROR。
3. `glm-system-test/changes/<change_name>/manifest.yaml` 与 `test-plan.md` 存在。
4. 最近一次 `[TEST_DESIGN_RESULT] READY`（或 task.md 中集成测试设计已就绪）。
5. `task.md` 中 `st-api-<change_name>` 依赖的业务 spec 已完成。
6. 读取 glm-system-test 期望分支与 `git status --short`；分支不匹配或未知脏改动时停止。

## 派发

1. Codex 多 agent 工具不可调用时，先执行工具发现。
2. 为 `st-api-<change_name>` 启动 **一个** glm-system-test 执行 agent。
3. 附带 `flow-codex-test-receive`、`flow-codex-test-apply`、`flow-codex-test-report`，并填充
   `test-child-agent-prompt.md`。
4. 执行 agent 严格遵循 `test-receive -> test-apply -> test-report`。
5. 收到 `REVIEW_REQUEST` 时，启动同级 `flow-codex-review`（**test 模式**：design 路径为
   `test-plan.md` + `manifest.yaml`），并将结果中继给同一执行 agent。最多三轮驳回。
6. 收到 `REPORT_REQUEST` 时，只向一个执行 agent 发放串行报告租约，恢复它并等待
   `[REPORT] complete`。
7. 更新根调度状态（glm-system-test 服务头部为开发中）。

不要在根上下文中编写测试代码或修改业务服务。
