# Changelog

本文件记录 **Flow Skill 仓库**（skills 框架本身）的变更，不包含业务项目（如 glm）的需求 changelog。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

---

## [Unreleased]

### Added

- **Claude 完整能力对齐 Codex（Phase 1–5）**：
  - **控制面 lease-v1**：`/flow:apply|assign|report|status` + 新增 `/flow:review`；`child-agent-prompt.md` 按 `protocol_version` 分支；缺省仍 legacy，新建 change design 写 `lease-v1`
  - **多模式 verify**：`format|domain|design|full|release`（+ 过渡 `legacy-api`）；design 强制 domain → DOMAIN_VERIFIED → 方案；assign/archive 门禁对齐
  - **集成测试全链**：`/flow:test-design|test-verify|test-assign|test-receive|test-apply|test-report|system-test`；`/flow:test` 改为 controller `next` 编排入口；`install.sh` 安装 `system-test/` 与 scripts
  - **feedback Discover/CDP** 对齐；`scripts/validate.js` 扩展 command↔skill stub、lease 词法、`flow/scripts` 存在性
  - 迁移清单：`docs/claude-lease-migration.md`
- **Phase 0 双宿主共享层（Claude 对齐预备）**：新增 `flow/docs/control-plane.md`（REVIEW/REPORT/test lease 词法 SoT）；`schema.md` / `config.yaml.tmpl` 增加可选 `protocol_version: legacy|lease-v1`（缺省 legacy）；宿主无关脚本迁至 `flow/scripts/`（validators + controller + 对应 tests/fixtures）；`codex/scripts/*.ps1` 保留过渡 shim；`install.sh` 安装 scripts + flow docs 且剔除 `templates/codex/`；`docs/claude-lease-migration.md`；ADR-002/005 与 `codex/PLAN.md` 改为 Claude 对齐中。

- **可验证集成测试控制器接入**：公开 test skills 统一读取 canonical controller state 与 `next`；实现派发、receive/apply/report 使用受控 lease，verifier 和 runner 只以绑定 revision/configuration 的结构化结果推进状态。持续 Goal 每轮只能执行 controller 返回的一个动作，不能自行跨级、提升授权、恢复或重跑。

- **集成测试 Flow 收口与配置停止**：移除独立运行前 skill 与 READY 凭据；设计阶段声明用户确认的配置来源、必需端点、
  最小只读探针和归属。implementation verify 保留静态检查；runner 仅在 implementation PASS、execution 授权、配置探针
  成功及 revision 一致时执行一次。失败统一停止分类，不自动修复配置、测试或业务仓。
- **集成测试失败归因与报告**：system-test runner 现在为每次运行生成统一 evidence index；FAIL 时收集原始报告和允许的
  日志/桩/数据库证据，生成脱敏 `failure-report.md`。失败项按配置、测试、数据契约、SUT 行为或未定性分类；证据不足只能
  标记 `UNDETERMINED`，同一 revision 不得重跑。

- **集成测试授权与范围硬门禁**：新增 `testAuthorization` ceiling（design / implementation / execution / result）、
  `validate-test-artifacts.ps1` 和 `test-scope-guard.ps1`。test-design/verify/assign/apply/test/system-test 现分别门禁
  授权、唯一 system-test 仓写入、静态实现校验、runner，以及 external-evidence BLOCKED、不可重置三轮 REJECT 和 stale
  capability fingerprint；模板、schema、status/archive 与结果记录同步。该变更不修改业务仓或自动修复外部证据。
  **迁移**：进行中的集成测试须补齐 `testAuthorization`、manifest `stage: "design"` 和 test-plan 的
  `system-test path:`，再重新执行对应阶段 verify。

- **集成测试设计协议与独立 verify**：新增 `test-design.md.tmpl`、`test-plan.md.tmpl`、`test-verify-checklist.md` 和 `flow-codex-test-verify`；test-design 固定 SUT revision、拓扑、真实/桩、夹具、观测和覆盖策略，test-plan 固定 AC→场景→方法→断言。design / implementation / result 三次只读验证分别门禁派发、runner 和完成状态；standalone runner 不得完成 Flow，local-only 不得进入发布或 Goal complete。
- **SQL 数据访问门禁**：`overview-design.md.tmpl` 新增条件必填「数据访问契约」；`flow-codex-design` 向 OpenSpec 传导过滤键、JOIN、基数/选行、索引与参考实现。`flow-codex-review` 审查相关子查询、`max/min` 选行、跨表风险形态及 Mapper 契约测试。`verify_mode=design` 新增 §F.1–§F.3，`verify_mode=release` 新增 §F.4，归档前强制最终列表 SQL 与 PageHelper count 的只读 EXPLAIN evidence；集成测试/发版记录模板同步记录风险与回滚。`scripts/validate.js` 同步 `.claude/commands/flow` 路径并支持中文模板名。
- **集成测试框架模板 + test-design scaffold**：`flow/templates/system-test/`（Maven 双模块、`scripts/system-test.ps1`、FixtureTool 等）；`flow-codex-test-design` 步骤 0 在编排根缺失测试仓时从模板初始化并登记 `type: system-test`；`codex/install.ps1` 安装 `system-test/` 目录树；`task-md-maintenance` §2.7 / runtime-contract 按 config 动态解析服务名。
- **设计阶段操作链路 + verify §D/§E + assign 门禁**：新增 `flow/templates/操作链路.md.tmpl`（`as-built` 行须带 `文件:行` 证据）；`verify-checklist.md` 新增 §D（D.1.1/D.1.2/D.2.1/D.2.2/D.2.5）与 §E（Apifox、接口表范围、文档一致性）；`verify_mode=design` 扩展为 §A+§C+§D+§E；verify 报告含编排人 WARN 确认清单；`flow-codex-design` 新增步骤 3.5 现状链路提取、产出 `操作链路.md`、Apifox MCP 强制路径、去自检化；`flow-codex-assign` 门禁扩展到 §D/§E；`flow-codex-change` 接口变化时同步链路。缺链路默认 WARN（`journey_required: true` 升 ERROR）；Apifox 待录入默认 WARN（`apifox_required: true` 升 ERROR）。默认 format / 全量 verify（§A+§B）行为不变。**Claude 侧已对齐**（`/flow:design|verify|assign`，见 Unreleased Phase 1–5）。
- **`flow-codex-feedback` Discover + CDP playbook**：Intake 后自动查已有 feedback / KB 选篇 / `{root}/.flow/cdp`；新增 `references/cdp.md`、`discover-kb.md`、`flow/templates/cdp-playbook.md.tmpl`；报告支持 `remediation` 与 `resolution=data-fix`（数据修复说明三段式）；收紧 feedback→KB（默认不写）；`validate.ps1` 校验 feedback/CDP 资源路径。**Claude `/flow:feedback` 已对齐 Discover/CDP**。
- **设计阶段领域概念 + verify §C**：`overview-design.md.tmpl` 强制「领域概念 / 歧义裁决 / 审核 pass 决策表 / 集成范围」；`verify-checklist.md` 新增 §C；`flow-codex-verify` 支持 `verify_mode=design`（§A+§C）；`flow-codex-assign` 派发前强制 design verify；`flow-codex-kb` / `flow-codex-archive` 联动 `kb_action: 待沉淀`。默认 format / 全量 verify（§A+§B）行为不变。**Claude 侧 design/domain 已对齐**。
- **`flow-codex-feedback`** / **`/flow:feedback`** — 线上反馈调查，`.flow/feedback/` 独立目录（懒创建）；不修代码、不写 task.md
- **`flow-codex-kb` feedback 入口** / **`/flow:kb feedback/{id}`** — 从调查报告沉淀 KB
- 模板：`feedback-index.md.tmpl`、`feedback-record.md.tmpl`、`feedback-report.md.tmpl`、`feedback-kb-rules.md`
- `flow/docs/schema.md` §11 feedback 协议
- Claude：`.claude/commands/flow/feedback.md`、`.claude/commands/flow/kb.md`、`.claude/skills/flow-feedback/`

### Changed

- **Feedback Trace 工具选择**：Java 服务 / 模块优先使用 IDEA MCP；MCP 不可用时暂停并提示打开对应工程或明确授权 GitNexus，禁止静默回退。非 Java 保留原策略。规则迁至共享 `feedback-trace-rules.md`，Codex / Claude 同步引用，并校验模板存在性。
- **`flow-codex-kb`** / **`flow-kb`** — 双入口（change / feedback）；`references/feedback-kb-rules.md`
- `AGENTS.md` · `docs/claude-code.md` · `流程文档.md` · `codex/PLAN.md` — 反馈闭环文档

- **集成测试 Flow 工作流**（Codex）：业务 verify 全量 PASS 后
  - `flow-codex-test-design` — manifest / test-plan / fixtures 设计（system-test 服务）
  - `flow-codex-test-assign` — 派发 `st-api-<change>`（不动 `flow-codex-assign`）
  - `flow-codex-test-receive` · `test-apply` · `test-report` — 测试代码子 agent 链
  - `flow-codex-test` 重写 — 门禁 + 委托 system-test
- **`flow-codex-system-test`** — 迁入 skills 仓库；system-test runner 执行与 evidence
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
