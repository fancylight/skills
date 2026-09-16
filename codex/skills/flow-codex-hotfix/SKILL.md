---
name: flow-codex-hotfix
description: 为单个服务创建可追踪的 Flow 热修复 spec，并准备进入常规派发。紧急生产修复仍需审核、测试和汇报时使用。
---

# Codex Flow 热修复

需求命名、分支与提交遵循 `../flow-codex-core/references/git-conventions.md`；已有需求读取根 change.json；实际写入 Git 仓库前按该规则绑定并校验，提交使用公共脚本，中文描述贯穿业务、文档和测试。

读取 `../flow-codex-core/references/platform.md`。要求提供根路径、服务、问题描述、期望分支和验收
标准。在根追踪中创建 hotfix 条目，并生成服务 OpenSpec proposal、design、delta specs 和 tasks。
复用已有根需求时沿用其 change.json；创建新的正式 Flow 根需求时先按公共 Git 规则 init 身份，不能当作无编号的非 Flow 临时修复。
验证 OpenSpec apply 就绪状态。通过 `flow-codex-assign` 派发；不要绕过审核、测试、提交或汇报。
