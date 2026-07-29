# Changelog

本文件记录 **Flow Skill 仓库**（skills 框架本身）的变更，不包含业务项目（如 glm）的需求 changelog。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

---

## [Unreleased]

### Added

- **设计阶段操作链路 + verify §D/§E + assign 门禁**：新增 `flow/templates/操作链路.md.tmpl`（`as-built` 行须带 `文件:行` 证据）；`verify-checklist.md` 新增 §D（D.1.1/D.1.2/D.2.1/D.2.2/D.2.5）与 §E（Apifox、接口表范围、文档一致性）；`verify_mode=design` 扩展为 §A+§C+§D+§E；verify 报告含编排人 WARN 确认清单；`flow-codex-design` 新增步骤 3.5 现状链路提取、产出 `操作链路.md`、Apifox MCP 强制路径、去自检化；`flow-codex-assign` 门禁扩展到 §D/§E；`flow-codex-change` 接口变化时同步链路。缺链路默认 WARN（`journey_required: true` 升 ERROR）；Apifox 待录入默认 WARN（`apifox_required: true` 升 ERROR）。默认 format / 全量 verify（§A+§B）行为不变；`flow-codex-review` / `test-design` / `kb` 未改。Claude 侧待 follow-up。
- **`flow-codex-feedback` Discover + CDP playbook**：Intake 后自动查已有 feedback / KB 选篇 / `{root}/.flow/cdp`；新增 `references/cdp.md`、`discover-kb.md`、`flow/templates/cdp-playbook.md.tmpl`；报告支持 `remediation` 与 `resolution=data-fix`（数据修复说明三段式）；收紧 feedback→KB（默认不写）；`validate.ps1` 校验 feedback/CDP 资源路径。Claude `/flow:feedback` 对齐待 follow-up。
- **设计阶段领域概念 + verify §C**：`overview-design.md.tmpl` 强制「领域概念 / 歧义裁决 / 审核 pass 决策表 / 集成范围」；`verify-checklist.md` 新增 §C；`flow-codex-verify` 支持 `verify_mode=design`（§A+§C）；`flow-codex-assign` 派发前强制 design verify；`flow-codex-kb` / `flow-codex-archive` 联动 `kb_action: 待沉淀`。默认 format / 全量 verify（§A+§B）行为不变；`flow-codex-review` 未改。Claude 侧 design 对齐待 follow-up。
- **`flow-codex-feedback`** / **`/flow:feedback`** — 线上反馈调查，`.flow/feedback/` 独立目录（懒创建）；不修代码、不写 task.md
- **`flow-codex-kb` feedback 入口** / **`/flow:kb feedback/{id}`** — 从调查报告沉淀 KB
- 模板：`feedback-index.md.tmpl`、`feedback-record.md.tmpl`、`feedback-report.md.tmpl`、`feedback-kb-rules.md`
- `flow/docs/schema.md` §11 feedback 协议
- Claude：`.claude/commands/flow/feedback.md`、`.claude/commands/flow/kb.md`、`.claude/skills/flow-feedback/`

### Changed

- **`flow-codex-kb`** / **`flow-kb`** — 双入口（change / feedback）；`references/feedback-kb-rules.md`
- `AGENTS.md` · `docs/claude-code.md` · `流程文档.md` · `codex/PLAN.md` — 反馈闭环文档

- **集成测试 Flow 工作流**（Codex）：业务 verify 全量 PASS 后
  - `flow-codex-test-design` — manifest / test-plan / fixtures 设计（glm-system-test）
  - `flow-codex-test-assign` — 派发 `st-api-<change>`（不动 `flow-codex-assign`）
  - `flow-codex-test-receive` · `test-apply` · `test-report` — 测试代码子 agent 链
  - `flow-codex-test` 重写 — 门禁 + 委托 system-test
- **`flow-codex-system-test`** — 迁入 skills 仓库；glm-system-test runner 执行与 evidence（原 glm-system-test 仓内 skill 已废弃）
- `flow/templates/codex/test-child-agent-prompt.md`、`integration-test-result.md.tmpl`
- `task-md-maintenance.md` §2.7 st-api 格式与集成测试完成检查清单
- `flow-codex-review` test 模式（对照 test-plan + manifest）

### Changed

- `flow-codex-archive`：前置增加 `集成测试.md` PASS 或用户跳过
- `verify-checklist.md` §A.3：可选 st-api 行型检查
- `AGENTS.md` · `README.md` · `codex/PLAN.md` · `checkpoints.md`：集成测试生命周期文档
- `integration-test.md.tmpl`：标记废弃，改由 test-design + result 模板
- **开发文档 §4 规则收紧**（修复 report 回写踩坑）：`dev-doc-maintenance.md`、`dev-doc-update-rules.md`、`开发文档模板.md.tmpl`、`flow-codex-report`/`flow-codex-design`、Claude `/flow:report`/`/flow:design` + `flow-report`/`flow-design` skill、`verify-checklist.md`、`schema.md` §10
  - §4.1：服务名称 = 可部署/运行单元，多模块仓拆行，禁止用仓库名冒充服务
  - §4.2：DDL/SQL 直接写在本节（自包含），禁止「详见发版记录 / openspec / 本地路径」
  - §4.3：新增必须章节，只写业务验收语义；禁止测试类名、本机地址、commit/spec
  - 全文禁止本地路径依赖、类名堆砌、Flow 内部术语写入正文
- **Spec 粒度铁律**：`platform.md`、`flow-codex-design`、`task-md-maintenance.md`、`overview-design.md.tmpl`、`dev-doc-maintenance.md` — 根 task 每个 c = 1 repo = 1 OpenSpec change，禁止多仓 bundle；design 强制 Spec | 服务 matrix 与 task-md §2.2 格式
- **verify 分层**：`verify-checklist.md` 拆为 §A 产物格式（结构/格式，design 后可跑）与 §B 发布就绪（test/archive 全量）；Spec 粒度归入 §A；`flow-codex-verify` 说明双模式调用

### Added

- `README.md`：项目框架、双平台架构、目录说明、安装与文档索引
- `AGENTS.md`：Cursor/Codex Agent 入口（重写，替代过时版本）
- `CLAUDE.md`：Claude Code Agent 薄入口（重写，指向 README）
- `docs/claude-code.md`：Claude Code 完整 Agent 指令
- `MAINTENANCE.md`：双平台维护规范、文档边界、校验流程
- `CHANGELOG.md`：本文件
- `flow/templates/dev-doc-maintenance.md`：开发文档受众、必须/禁止项、阶段职责
- `flow/templates/dev-doc-update-rules.md`：report 阶段开发文档增量回写规则
- `flow/templates/verify-checklist.md`：发布就绪检查（verify/archive）
- `flow/docs/schema.md` §10：`开发文档.md` 字段规范

### Changed

- 文档职责拆分：README（人读框架）/ AGENTS（Codex Agent）/ CLAUDE（薄路由）/ MAINTENANCE（维护者）
- **方案 A**：`CLAUDE.md` 收成薄路由；Claude Code 完整指令迁至 `docs/claude-code.md`
- **开发文档规范**：重写 `开发文档模板.md.tmpl`（§3.2.1–3.2.4 结构；接口表迁至 §3.2.4）
- `flow-codex-design` / `flow:design`：design 阶段只写开发文档骨架，禁止照搬概要设计
- `flow-codex-report` / `flow:report`：report 回写 §3.2.2–3.2.4、§4.2；Apifox 同步读 §3.2.4
- `flow-codex-verify`：充实为发布就绪 + 产物规范检查（非跨服务契约）
- `flow-codex-archive` / `flow:archive`：归档前 verify-checklist 无 ERROR
- 澄清读者分工：`MAINTENANCE.md` 仅 skills 仓库维护；`flow/templates/dev-doc-*.md` 供业务 Flow Agent

### Removed

- 删除 AGENTS.md 中错误的 `.Codex/commands/flow` 路径描述及对不存在 `flow:feedback` 的引用

### Notes

- **破坏性**：新需求开发文档接口表在 **§3.2.4**（旧模板为 §3.2.2）；存量 change 不自动迁移

---

## [0.2.0] - 2026-06（估算）

### Added

- `codex/` 适配层：`flow-codex-*` skills、`install.ps1`、`validate.ps1`
- `codex/PLAN.md`：Codex 生命周期（根调度 review、串行 report 租约）
- 共享模板安装：`flow/templates/` → `flow-codex-core/assets/templates/` + `codex/` 覆盖

### Notes

- Claude Code 原版保留在 `.claude/` + `install.sh`
- 双平台共用 `.flow/` 协议与 OpenSpec
