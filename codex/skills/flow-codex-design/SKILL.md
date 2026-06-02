---
name: flow-codex-design
description: 为 Codex 编排设计或修复 Flow 需求。创建根需求产物、拆分服务 spec、生成 OpenSpec change 或修复无法 apply 的设计时使用。
---

# Codex Flow 设计

读取 `../flow-codex-core/references/platform.md` 和 `references/openspec-readiness.md`。使用 core
模板生成概要设计和发版记录。

## 根模式

1. 要求明确提供 `change_name`。
2. 读取根 Flow 配置和已有需求产物。
3. 创建或修复 `.flow/changes/<change_name>/概要设计.md`、`task.md` 和 `发版记录.md`。
4. 按服务和 spec 拆分工作，记录依赖关系、期望分支和验收标准。
5. 对每个服务 spec 使用已安装的 OpenSpec 流程生成 proposal、design、delta specs 和 tasks。
6. 对每个 spec 执行 OpenSpec readiness 检查，持续补齐设计，直到没有阻断项。
7. 返回 spec 依赖图和 apply-readiness 结果。

## 服务模式

只创建或修复一个已分配的服务 spec。以内联执行 agent 运行且需要独立设计审核时，向根 agent
返回审核 checkpoint，不要尝试启动嵌套审核 agent。
