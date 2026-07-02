# Changelog

本文件记录 **Flow Skill 仓库**（skills 框架本身）的变更，不包含业务项目（如 glm）的需求 changelog。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

---

## [Unreleased]

### Changed

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
