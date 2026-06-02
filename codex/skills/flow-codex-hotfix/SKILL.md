---
name: flow-codex-hotfix
description: 为单个服务创建可追踪的 Flow 热修复 spec，并准备进入常规派发。紧急生产修复仍需审核、测试和汇报时使用。
---

# Codex Flow 热修复

读取 `../flow-codex-core/references/platform.md`。要求提供根路径、服务、问题描述、期望分支和验收
标准。在根追踪中创建 hotfix 条目，并生成服务 OpenSpec proposal、design、delta specs 和 tasks。
验证 OpenSpec apply 就绪状态。通过 `flow-codex-assign` 派发；不要绕过审核、测试、提交或汇报。
