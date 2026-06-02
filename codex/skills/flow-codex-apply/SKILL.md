---
name: flow-codex-apply
description: 使用 OpenSpec 实现唯一一个已接收的 Flow spec，并完成独立代码审核、测试和一次服务提交。在 flow-codex-receive 后使用。
---

# Codex Flow 编码

读取 `../flow-codex-core/references/platform.md` 和
`../flow-codex-core/references/checkpoints.md`.

## 实现

1. 要求明确提供 `change_name` 和 `spec_id`。
2. 编辑前重新检查期望分支和干净基线。
3. 只对当前 spec 执行已安装的 OpenSpec apply 流程。
4. 实现完成后追加进度，并返回 `REVIEW_REQUEST`。

## 审核后恢复

- 收到 `REVIEW_RESULT REJECT` 时，只修复已报告的问题，再次返回 `REVIEW_REQUEST`。
- 收到 `REVIEW_RESULT PASS` 时，执行配置中的测试。失败时修复并重跑，最多三轮。
- 使用配置的提交格式，只提交当前 spec 的文件。
- 返回 `REPORT_REQUEST`，等待根 agent 发放报告租约。

apply 阶段不要直接更新根追踪文档。
