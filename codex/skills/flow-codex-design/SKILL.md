---
name: flow-codex-design
description: 为 Codex 编排设计或修复 Flow 需求。创建根需求产物、拆分服务 spec、生成 OpenSpec change 或修复无法 apply 的设计时使用。
---

# Codex Flow 设计

读取 `../flow-codex-core/references/platform.md` 和 `references/openspec-readiness.md`。使用 core
模板生成概要设计、开发文档和发版记录。

## 根模式

1. 要求明确提供 `change_name`。
2. 读取根 Flow 配置和已有需求产物。
3. **查询 Apifox 已有接口**：如 Apifox MCP 可用，对涉及的接口（新增/修改）搜索已有定义——修改的查当前定义对比差异，新增的查命名冲突。MCP 不可用时降级跳过。
4. 创建或修复 `.flow/changes/<change_name>/概要设计.md`、`开发文档.md`、`task.md` 和 `发版记录.md`。
   - 生成 `开发文档.md` 前读取 `../flow-codex-core/assets/templates/dev-doc-maintenance.md` 与 `开发文档模板.md.tmpl`。
   - **§1–§2**：从需求/用户输入填写；§2「相关规则」写业务可验证规则。
   - **§3.2.1–§3.2.3**：仅写摘要或占位（业务规则要点、存储语义草稿、流转草图）；**禁止**从 `概要设计.md` 复制消费点表、Java/文件清单、JSON。
   - **§3.2.4**：接口表填路径 + 变更类型 + 一行说明；Apifox 列从步骤 3 填入链接或「待录入」；**禁止 JSON**。
   - **§4.1**：从 task.md services 填分支；**§4.2** 留空（由 report 补充）。
5. 按服务和 spec 拆分工作，记录依赖关系、期望分支和验收标准。
6. 对每个服务 spec 使用已安装的 OpenSpec 流程生成 proposal、design、delta specs 和 tasks。
7. 对每个 spec 执行 OpenSpec readiness 检查，持续补齐设计，直到没有阻断项。
8. 返回 spec 依赖图和 apply-readiness 结果。

## 服务模式

只创建或修复一个已分配的服务 spec。以内联执行 agent 运行且需要独立设计审核时，向根 agent
返回审核 checkpoint，不要尝试启动嵌套审核 agent。
