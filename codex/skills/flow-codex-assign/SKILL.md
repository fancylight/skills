---
name: flow-codex-assign
description: 按依赖安排 Flow specs，默认当前对话串行实施，仅经用户授权才委派子 agent。用户要求分配、委托、开始编码或执行根 task 中的 spec 时使用。
---

# Codex Flow 派发

完整编排入口；不因用户只要求修复已有 spec 而自动派发。先按 ../flow-codex-core/references/delivery.md 判断路径并确认当前项目允许子 agent；不允许时不得启动或恢复子 agent，也不得以本 skill 推导授权。作为根编排 agent 执行。读取 `../flow-codex-core/references/platform.md`、
`../flow-codex-core/references/checkpoints.md` 和 `references/scheduler.md`。使用
`../flow-codex-core/assets/templates/child-agent-prompt.md`.

## 派发前检查

单对话模式：按 core/references/delivery.md 完成下列范围、设计、依赖和分支检查，然后由当前执行者逐 spec 接收并实施；跳过下方工具发现、子 agent 派发及租约中继，不伪造独立审核。只有已授权委派才使用多 agent 派发段。

1. 要求根角色为 `orchestrator`，并明确提供 `change_name` 和选中的 specs。
2. 读取根追踪元数据和依赖状态，不要读取服务业务代码。
3. 对每个选中的服务仓库检查期望分支和干净基线。
4. 对本 change 执行 `flow-codex-verify`（`verify_mode=design`，覆盖 §A+§C+§D+§E+§F.1–§F.3）。存在 §A、§C、§D、§E 或 §F **ERROR** 时停止派发。存在 **WARN** 时须对照 verify 报告末尾「编排人 WARN 确认清单」**逐项**向用户确认（确认 / 回 design 修 / waive 并说明）；未确认不得 assign。
5. 确认每个选中的 OpenSpec 均可 apply，遇到阻断 spec 时停止。
6. 只派发依赖就绪的 specs。仅在不同仓库或隔离 worktree 之间并行。

## 派发

1. Codex 多 agent 工具不可调用时，先执行工具发现。
2. 为每个就绪 spec 启动一个执行 agent。附带 `flow-codex-receive`、`flow-codex-apply` 和
   `flow-codex-report`，并填充子 agent 提示词模板。
3. 执行 agent 严格遵循 `receive -> apply -> report`。
4. 收到 `REVIEW_REQUEST` 时，启动同级 `flow-codex-review` agent，并将结果中继给同一个执行
   agent。最多允许三轮驳回。
5. 收到 `REPORT_REQUEST` 时，只向一个执行 agent 发放串行报告租约，恢复它并等待
   `[REPORT] complete`。
6. 更新根调度状态；由根按 ../flow-codex-core/references/delivery.md 串行完成根文档提交与 flow-codex-check，分别报告服务和根仓提交。继续派发新解锁的 specs。

不要在根上下文中实现服务代码。
