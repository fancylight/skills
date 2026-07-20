---
name: flow-codex-review
description: 根据 OpenSpec 设计对一个 Flow spec 实现执行独立只读审核。作为根编排 agent 启动的同级审核 agent 使用。
---

# Codex Flow 审核

读取 `../flow-codex-core/references/platform.md` 和 `references/review-format.md`。这是内部只读
辅助 skill。

## 输入

要求提供 `change_name`、`spec_id`、服务路径、设计路径、变更文件列表和审核轮次。

可选 `review_mode`：

- **默认（业务 spec）**：设计路径为 OpenSpec `design.md`
- **`test`**：`spec_id` 为 `st-api-*`；设计路径为 glm-system-test 的 `test-plan.md` +
  `manifest.yaml`（见 `references/review-format.md` §test 模式）

## 审核

1. 读取设计产物和变更文件（按 review_mode 选择 OpenSpec 或 test-plan/manifest）。
2. 检查正确性、缺失的验收标准、回归风险、不安全行为和缺失测试。
3. test 模式额外检查：验收 ID 覆盖、无理由 skip、fixtures 预留 ID 合规。
4. 不要编辑文件、提交或扩大范围。
5. 没有可执行问题时返回 `[REVIEW_RESULT] PASS`。
6. 否则返回 `[REVIEW_RESULT] REJECT`，并附带简短的问题列表、文件和行号。
