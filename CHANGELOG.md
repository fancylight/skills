# Changelog

本文件记录 **Flow Skill 仓库**（skills 框架本身）的变更，不包含业务项目（如 glm）的需求 changelog。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

---

## [Unreleased]

### Fixed

- 分离旧测试执行预算与后续用户授权的设计/开发：新增 revise/review-design，保留运行门禁与历史；明确授权的新执行轮次记录独立预算历史，防止旧 budget-exhausted 永久阻断新需求。

- Flow Hook 统一写入 config.toml 的独立标记块，迁移旧版仅含 Flow 的 hooks.json 并保留备份，消除同层双来源提示；重复安装和撤销保留其他配置及信任/启停记录。

- 补齐 Codex Git 的 create-worktree 入口，支持明确的本地及远端跟踪基线，创建后绑定新工作目录并保留源目录状态；修复 Hook 拦截 worktree 却只提示 create-branch 的流程死路，增加真实临时仓回归。

- 修复 11 个 Codex 技能入口的 UTF-8 BOM，恢复 design、verify、review 及测试技能的可发现性；校验和安装共用原始字节检查，安装前拒绝不合格源文件，复制后复核入口，避免文本读取隐藏编码错误。

### Changed

- Codex 设计及实现审核要求原始依据与可证伪输入；新增正式测试切片与统一执行入口，沿用 controller 状态管理修复、历史证据、结果审核及30分钟总预算。runner 保留首个失败并单列清理问题；PowerShell 7 的状态读取保留原始日期字符串。

- 修复 Codex Git hook 阻断恢复已有需求分支却只提示 create-branch 的缺口：新增 switch-branch，校验目标绑定、本地分支和已跟踪改动，保留既有提交与无冲突的未跟踪测试证据；实际路径冲突（含被忽略文件）仍拒绝覆盖，补充恢复开发及拒绝不安全切换的回归测试。

- Codex 需求以 change.json 绑定编号、英文短名、初始交期及完整分支；中文提交规范覆盖业务、文档和测试。增加本地 Git 校验/提交/统计脚本及可撤销的 Codex PreToolUse 接线，保留手动 Git 和存量历史，不改变单对话流程。

- Codex环境预检兼容既有字面量TCP端点和多服务/多仓SUT拓扑：逐服务核对指纹绑定版本，并要求主业务仓与controller一致；不弱化缺失引用、连接失败或版本漂移的拒绝。

- Codex测试实施中支持已授权范围修订的定点设计审核记录；绑定真实提交、源摘要和退出场景，保留原阶段、lease、授权及历史，不绕过代码/环境/运行/结果门禁。

- Codex 集成测试先形成并审核业务用例，再设计运行/代码/夹具/观测；同一 canonical 源生成业务主体和技术附录，正式门禁拒绝纯技术映射。业务预览支持无技术字段，PowerShell 5.1/7 中文生成一致。新增 controller 追加用户授权和实施前设计重开/版本接纳入口，保留授权审计、旧审核与稳定基线，支持存量设计在原对话复核。

- Codex 首轮交付采用四项精简责任，明确单对话分阶段自查和可选委派，保留正式 Flow 状态与权限。增加项目本地命令执行/只读证据校验，复用 canonical 场景源，检查真实 JUnit、故障断言、构件与证据漂移；正式结果校验器可接入该检查。无 CI、后台服务或额外对话依赖。

- 全局短原则与 Flow 分阶段质量检查分层：共享工程质量约束覆盖复用、目标环境、必要复杂度、编码规范、真实验收和文档当前结论；Codex 与 Claude 入口引用同一来源。移除审核只检查设计一致性的限制，概要设计改为业务说明先行、追溯材料后置，兼容既有布局。
- Codex feedback 浏览器操作优先使用 Edge 控制工具，CDP 降为用户指定或 Edge 控制不可用 / 无法完成操作时的备用方式。保留 `.flow/cdp/` 手册兼容，通过 Codex 专属模板移除默认远程调试要求；Claude 不变。

### Added

- 独立 Java NeedBraces 检查器：固定 Checkstyle 14.1.0/JDK 21+，按指定文件与 Git 基线分离新增和历史违例；输出原始 XML 与 PASS/FAIL/UNVERIFIED/NOT_APPLICABLE，不修改业务 POM。新增真实工具回归及安装分发验证。

- **v2 standalone 场景选择与本地配置统一**：新增 canonical `-ScenarioIds` 精确过滤和本次 JUnit 报告校验，拒绝空选集、未知 ID、零匹配、越界或 skipped；部分结果 `fullSuite=false`，controller 拒绝将其登记全量 PASS。Git 忽略的 human 本地配置允许已有凭据，完整文件 SHA256 检测变化；日志脱敏后入独立 runs 证据目录。运行时增加 prepare/cleanup 契约、显式身份复用、按 SUT 关联配置证据、120 秒启动及 600 秒 suite 上限、PID/启动时间校验后的进程树清理。共享 helper 纳入 harness certification。

- **集成测试环境 v2 P3 隔离生命周期引擎**：新增 `run-resolved-environment.ps1`，消费锁定 fingerprint 的 resolved manifest，验证 provider target 身份和 SUT 配置消费证据，区分 managed 创建与健康实例复用，只清理本次创建的进程，并按 `CONFIG_INFRA` / `SUT_BUSINESS` 输出结构化结果；伪 provider/SUT/suite 自测覆盖正常、失败归因、复用所有权与敏感值脱敏。现有 v1 `system-test.ps1` 尚未切换。
- **集成测试环境 v2 P4 接线与迁移**：`system-test.ps1` 现按 manifest schema 保留 v1 或分派 v2，v2 强制 harness certification、controller fingerprint、resolved environment file，并输出结构化 evidence；运行所有权持久化 PID + start time，支持中断后的安全 cleanup。新增只写新文件的显式 migration-spec 迁移器，拒绝猜测 provider/SUT/evidence/runner 契约。
- **GLM P5 结构 shadow 与 Spring Config git backend**：provider service repo 与 configuration content repo 现分别锁定 revision；支持 git backend 的 `<configRoot>/<application>-<profile>.yml` target。真实 GLM committed snapshot 的配置敏感项被安全门禁阻断，临时引用化 clone resolver PASS。secret 检查补齐 `appSecret`、`secret-key` 与 CRLF 行尾回归；未启动真实服务或业务测试。

- **集成测试环境 v2 P2 preflight**：新增 `flow/scripts/validate-test-environment.ps1`，在
  `VERIFY_ENVIRONMENT` 阶段只读校验 controller/fingerprint、输入与 Git revision 漂移、配置 target、环境引用、managed
  executable/start script/端口，并执行 external TCP/HTTP probe；不启动 managed 服务。结构化 PASS 已通过隔离测试由现有
  controller 接受并推进 `TEST_ENVIRONMENT_VERIFIED`，BLOCKED 覆盖依赖不可用、端口占用、引用缺失和漂移场景。

- **集成测试环境 v2 P1 resolver**：新增 repo 级 environment descriptor 示例与
  `flow/scripts/resolve-test-environment.ps1`。resolver 在隔离 Git 仓中校验 provider/SUT revision、配置 target、
  managed/external 生命周期、结构化 probe、资源依赖环、路径越界和敏感值，生成确定性的
  `resolved-manifest.json` 与 `configurationFingerprint`；P1 尚未切换现有 runner。新增对应隔离 self-test，
  并接入 Codex/Claude 安装与仓库校验。

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

## Codex 灵活交付（Unreleased）

- 原范围修复重开 spec，允许后续 Git 提交；交付责任集中到 core/delivery，新增只读 flow-codex-check 与 Git 文件范围盘点。
- 根文档收尾及本地提交明确归根或直接实施者；新增项目入口模板，安装不自动迁移业务文件。
- 执行已有测试优先复用项目路径；feedback/apply 保持原行为，本版不适配 Claude。

验证（2026-09-11）：仅含本轮暂存改动的导出副本通过 `codex/validate.ps1`、`test-delivery-scope.py` 和临时安装；apply/feedback 文件与修改前逐文件一致。10 个冻结案例仅为回放输入与期望，GPT-6 / GPT-5.6 Sol 实际模型回放均为 UNVERIFIED，不能据此声明模型兼容。未覆盖全局技能安装及其他业务项目迁移。
