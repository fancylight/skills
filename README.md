# Flow Skill

全局工作站点能力见 [flow-codex-sites](codex/skills/flow-codex-sites/SKILL.md)：任意阶段或独立任务需要操作工作平台时，优先通过 Edge 查对应手册；普通查询不触发 feedback 建档。个人索引位于用户主目录 `.flow/worksites/README.md`，按平台、环境、操作维护，安装与回退不覆盖个人资料。成功的新操作自动沉淀，未验证范围明确保留；不将劳务动态菜单或 GBP 的某一模块当作通用固定路径。

Codex 默认支持单对话完成设计、自查、实施、测试及交付，多对话仅在用户授权时采用。首轮质量改进保留四项责任：独立预期、最小真实链路、受影响重验、当前构件与证据汇合。项目命令可接入本地执行器，实际执行 JUnit 断言并复查原始报告；详见 [首轮交付与本地闭环](codex/skills/flow-codex-core/references/first-delivery.md)。本地通过不替代完整 Flow 或目标部署验收。

多服务、多 Agent 协作研发的 **Skills 工作流框架**。把需求拆分、设计、编码、审核、测试、汇报、集成验证和知识沉淀，编码成可被 AI Agent 重复执行的指令集。

本仓库**不是业务项目**，而是 skills 源码与共享协议（`.flow/`）的定义处。业务项目（如 `glm`）在根目录初始化 `.flow/` 后，安装并调用这里的 skills。

## 工程质量

Codex 的设计、自查与测试审核按 [设计判断与反例审核](codex/skills/flow-codex-core/references/design-challenge.md) 核对原始依据和可证伪输入。结构完整不能自动成为语义通过。

正式集成测试支持先跑已审核切片，通过 [flow-test.ps1 执行与恢复](codex/skills/flow-codex-core/references/test-execution-cycle.md) 管理原 controller 状态。首次准备运行起默认30分钟，恢复不重置预算；当前结果与历史证据分开，局部成功不算全量成功。仍可在一个对话完成设计、开发、测试和交付。

设计、编码、审核、测试和汇报共用 [工程质量约束](flow/templates/engineering-quality.md)。先核对既有实现及目标环境，再判断新增能力；审核不能仅检查与设计一致。概要设计先解释当前方案，追溯信息后置；历史布局仍可使用。

Java 变更保留项目已有规范检查，并用 [独立 NeedBraces 检查器](flow/scripts/check-java-style.ps1) 检查本次文件。它只保证控制语句的大括号，不代表完整阿里 Java 规范检查，不修改业务 POM。工具固定 Checkstyle 14.1.0，可从 [官方发布页](https://github.com/checkstyle/checkstyle/releases/tag/checkstyle-14.1.0)取得 all.jar，放在用户缓存 `.cache/flow-tools/checkstyle/14.1.0/`，或传入 `-CheckstyleJar`；使用独立 JDK 21+，不升级业务项目 JDK。检查器不会自动下载或安装依赖。

```powershell
# Files 为本次明确的仓库相对路径；每次使用空的独立报告目录。
./flow/scripts/check-java-style.ps1 -RepositoryPath <repo> -BaseRevision <commit> -Files <file.java> -ReportDirectory <report-dir> -JavaExecutable <jdk21-java>
```

新文件检查全部违例；已有文件通过基线和 Git 行映射识别历史违例，Git 已识别的重命名也保留基线。未被 Git 识别的新增路径按新文件检查，可在正常暂存后重新检查重命名。结果及原始 XML 保留在报告目录：PASS/NOT_APPLICABLE 退出0，新增违例 FAIL 退出1，工具、输入或解析问题 UNVERIFIED 退出2。Java 相关审核不能把 FAIL/UNVERIFIED 当作规范通过。

维护时运行 `flow/scripts/tests/test-check-java-style.ps1`（传入可用的 `-JavaExecutable`）和 `codex/validate.ps1`。安装器分发共享规则、脚本和配置，不修改个人全局 AGENTS.md；全局规则由用户单独维护。

---

## 架构总览

```text
┌─────────────────────────────────────────────────────────────────┐
│                        业务项目（如 glm）                          │
│  .flow/config.yaml · changes/{需求}/task.md · 概要设计.md …      │
└───────────────────────────────┬─────────────────────────────────┘
                                │ 文件协议（解耦通信）
        ┌───────────────────────┴───────────────────────┐
        ▼                                               ▼
┌───────────────────┐                         ┌───────────────────┐
│   根 Agent        │  assign / status /      │   执行 Agent       │
│   orchestrator    │  verify / test / archive│   executor         │
│   不编码、不提交    │ ──────────────────────► │   编码·审核·测试·汇报 │
└───────────────────┘                         └───────────────────┘
        │                                               │
        └───────────────────┬───────────────────────────┘
                            ▼
              ┌─────────────────────────────┐
              │  本仓库提供的 Skills 实现      │
              │  Claude Code  │  Codex/Cursor │
              └─────────────────────────────┘
```

### 角色

| 角色 | 职责 | 禁止 |
|------|------|------|
| **根 Agent** | 需求拆分、概要设计、维护 `task.md` 结构、派发、进度、集成测试、契约验证、归档 | 编码、提交代码、勾选 spec 完成 |
| **执行 Agent** | 接收 spec → OpenSpec 实现 → 审核 → 测试 → 提交 → 汇报 | 越权改其他服务 spec、跳过知识库判断 |

### 核心约定

- **文件通信**：根与执行 Agent 通过 `.flow/` 下文件协作，不依赖同一对话或进程。
- **粒度**：每个 spec 对应单仓 OpenSpec change；一次实施尽量一个提交，原范围返修允许后续提交（spec = 根 task 单仓 OpenSpec change；跨仓 c 递增，禁止多仓 bundle）。
- **task.md 完成状态**：仅由汇报阶段写入（Claude：`flow:report`；Codex：`flow-codex-report`）。

---

## 双平台实现

同一套 `.flow/` 协议与 `flow/` 共享模板，两套 skills 分别面向不同 AI 宿主：

| | Claude Code | Codex / Cursor |
|--|-------------|----------------|
| **本仓库路径** | `.claude/`（gitignore，开发用） | `codex/skills/` |
| **安装脚本** | `install.sh` | `codex/install.ps1` |
| **安装目标** | `~/.claude` 或项目 `.claude` | `~/.agents/skills` |
| **触发方式** | 斜杠命令 `/flow:*` + `flow-*` skill stub | `flow-codex-*` skill（语义触发） |
| **Agent 入口** | [docs/claude-code.md](./docs/claude-code.md)（经 [CLAUDE.md](./CLAUDE.md) 路由） | [AGENTS.md](./AGENTS.md) |
| **审核（lease-v1）** | 根收 `REVIEW_REQUEST` → `/flow:review` → 注入 `REVIEW_RESULT` | 根调度 `flow-codex-review` |
| **汇报（lease-v1）** | 根串行 `REPORT_LEASE_GRANTED` 后 `/flow:report` | 同词法，`flow-codex-report` |
| **兼容（legacy）** | 内联审核 + 直接 report（缺省，不打断进行中 change） | — |
| **共享 SoT** | `flow/docs/*` · `flow/templates/**` · `flow/scripts/*.ps1` | 同左（`codex/scripts` 为过渡 shim） |

协议词法：[flow/docs/control-plane.md](./flow/docs/control-plane.md)。Claude 迁移：[docs/claude-lease-migration.md](./docs/claude-lease-migration.md)。平台差异详见 [codex/PLAN.md](./codex/PLAN.md)。

---

## 本仓库目录

```text
skills/
├── README.md                 ← 本文件（人读 · 项目框架）
├── AGENTS.md                 ← Cursor/Codex Agent 主入口
├── CLAUDE.md                 ← 薄路由（Cursor 忽略；Claude Code 读 docs/claude-code.md）
├── docs/claude-code.md       ← Claude Code 完整 Agent 指令
├── MAINTENANCE.md            ← 维护规范
├── CHANGELOG.md              ← 版本与变更记录
│
├── .claude/                  ← Claude 实现（gitignore；install.sh 复制到 ~/.claude）
│   ├── commands/flow/            /flow:* 正文（22 个，含 review + test 全链）
│   ├── skills/flow-*/            薄 stub → 对应 command（22 个）
│   └── INSTALL.md
│
├── codex/                    ← Codex 适配层
│   ├── install.ps1
│   ├── validate.ps1
│   ├── PLAN.md
│   ├── scripts/                过渡 shim → flow/scripts/
│   └── skills/
│       ├── flow-codex-*        公开 skills
│       └── flow-codex-core     内部公共资源 + 安装后模板副本
│
├── flow/                     ← 双平台共享 SoT
│   ├── docs/                   schema · control-plane · test-controller
│   ├── scripts/                validators + flow-test-controller + tests
│   └── templates/              模板源（含 system-test/）
│       └── codex/              Codex 覆盖项（仅 Codex install 叠加）
│
├── scripts/validate.js       ← Claude 侧静态校验（stub/lease/scripts）
├── install.sh                ← Claude 安装
├── docs/claude-lease-migration.md
├── flow-redesign.md          ← 设计文档 v3（细节参考）
├── 流程文档.md                ← 工作流场景与 Mermaid 图
└── 多阶段AI自动化开发流程（含Mermaid流程图）.md  ← 愿景
```

---

## 运行时协议（业务项目中的 `.flow/`）

Skills 在业务仓库中读写以下结构（完整字段见 [flow/docs/schema.md](./flow/docs/schema.md)）：

```text
{编排根目录}/
└── .flow/
    ├── config.yaml
    ├── onboarding.md
    ├── services.md
    └── changes/
        └── {需求名}-{YYYYMMDD}/
            ├── 概要设计.md      ← Agent 编排：服务边界、spec、验收标准、契约草稿
            ├── 开发文档.md      ← 人读：业务规则、存储、数据流、接口索引
            ├── task.md          ← spec 清单与进度
            ├── 发版记录.md
            └── archive/         ← 完成后移入

{服务目录}/
└── .flow/
    ├── config.yaml
    └── 工作流程.md
```

**文档边界**（详见 [MAINTENANCE.md](./MAINTENANCE.md)）：

| 文档 | 读者 | 内容 |
|------|------|------|
| `概要设计.md` | Agent / 编排 | spec 拆分、开发顺序、验收标准、Flow 测试设计 |
| `开发文档.md` | 开发 / 测试 / 运维 | §2 需求分析；§3.2.1–3.2.4；§4.1 可部署服务-分支；§4.2 SQL/配置（自包含）；§4.3 业务验收 |

规范见 `flow/templates/dev-doc-maintenance.md`。design 写骨架，report 按实现回写。
---

## 安装

### Codex / Cursor（推荐，本仓库主维护线）

```powershell
cd path\to\skills
.\codex\install.ps1              # 安装到 ~/.agents/skills
.\codex\install.ps1 -WhatIf      # 预览
.\codex\validate.ps1             # 校验 skill 完整性
```

### Claude Code

```bash
cd path/to/skills
./install.sh                     # 安装到 ~/.claude
./install.sh --project           # 仅当前项目
./install.sh --dry-run
```

安装后重启对应宿主，在业务项目根目录使用 flow skills。

---

## 典型流程（Codex）

```text
flow-codex-init          → 初始化 .flow/
flow-codex-design        → 概要设计 + 开发文档骨架 + task.md + OpenSpec
flow-codex-assign        → 按依赖派发 spec
  └─ flow-codex-receive → flow-codex-apply
  └─ flow-codex-review  → （根调度）→ apply 继续 → report 租约
flow-codex-status        → 查看进度
flow-codex-verify        → 根产物格式；design SQL 契约（§F.1–§F.3）+ archive 前 EXPLAIN 证据（§F.4）
flow-codex-test-design   → 缺仓则 scaffold 模板 + manifest / test-plan
flow-codex-test-assign   → 派发 st-api-* 测试代码
  └─ test-receive → test-apply → test-report
flow-codex-test          → 门禁 + 委托 system-test + 检查清单
flow-codex-system-test   → 测试仓 runner 执行
flow-codex-archive       → 归档
```

Claude Code 将上述 skill 名替换为 `/flow:*` 命令，审核内联在执行 Agent 内完成。完整场景图见 [流程文档.md](./流程文档.md)。

---

## 反馈调查的代码追踪

`feedback` 按目标服务 / 模块判断语言：Java 项目优先使用 IDEA MCP；不可用时暂停，提示用户在 IDEA 中打开对应工程、确认 MCP / 索引就绪，或明确允许本次改用 GitNexus，不静默回退。非 Java 项目保留 GitNexus 优先、不可用时搜索源码的策略。双平台共用 [Trace 规则](./flow/templates/feedback-trace-rules.md)。

Codex feedback 的浏览器操作优先使用 Edge 控制工具；CDP 仅在用户指定或 Edge 控制不可用 / 无法完成操作时备用。既有 `.flow/cdp/` 手册继续复用，工具选择遵循 [浏览器操作规则](./codex/skills/flow-codex-feedback/references/cdp.md)。Codex 使用专属模板覆盖，Claude 保留原有方式。

## 文档索引

| 文档 | 用途 |
|------|------|
| [README.md](./README.md) | 项目框架与安装（本文件） |
| [AGENTS.md](./AGENTS.md) | Cursor/Codex Agent 主入口 |
| [CLAUDE.md](./CLAUDE.md) | 薄路由（双宿主兼容） |
| [docs/claude-code.md](./docs/claude-code.md) | Claude Code Agent 完整指令 |
| [MAINTENANCE.md](./MAINTENANCE.md) | 改 skill / 模板 / 发版规范（**仅 skills 仓库维护**） |
| [CHANGELOG.md](./CHANGELOG.md) | 版本变更记录 |
| [flow/docs/schema.md](./flow/docs/schema.md) | `.flow/` 数据格式 |
| [codex/PLAN.md](./codex/PLAN.md) | Codex 平台边界与生命周期 |
| [flow-redesign.md](./flow-redesign.md) | 设计决策 v3 |
| [流程文档.md](./流程文档.md) | 场景流程与 Mermaid |
| [todo.md](./todo.md) | 开发进度 checklist（维护者） |
| [问题记录.md](./问题记录.md) | 实战踩坑记录 |

---

## 参与维护

修改 skills 或模板前请阅读 [MAINTENANCE.md](./MAINTENANCE.md)。提交前运行对应平台的校验脚本。

## Codex 灵活交付版本

保留既定产物与完整编排，原范围修复允许重开 spec 后直接实施。交付责任见 [delivery](codex/skills/flow-codex-core/references/delivery.md)；新增 `flow-codex-check` 可在任意阶段只读检查实际范围、根文档和提交证据，实施完成前自动使用。

本版仅验证 Codex，不更新或卸载 Claude。旧 Claude 使用旧版独立安装，不能共享新版资源。重装后建议新开会话，从已有需求文件和 Git 状态恢复，不重建 spec、不清空 controller。安装技能不会自动更新业务项目入口或测试仓；将 `flow/templates/codex/flow-delivery-entry.md.tmpl` 合并到业务 AGENTS.md，GLM 执行接线单独交付。

GPT-6 与 GPT-5.6 Sol 共用规则，模型效果以真实回放为准；未运行的模型不声明兼容。

集成测试设计现在先审核可读业务用例，再设计运行、代码、夹具和观测；test-plan 的业务主体和技术附录由同一 test-cases.yaml 派生。存量已审核设计可在原对话按 [controller 协议](flow/docs/test-controller.md) 重开并复核；追加用户授权有正式命令，不修改初始 manifest 或重置状态。


### Codex Git 命名与中文提交

根需求编号贯穿业务、文档和测试提交；新目录及分支由英文短名和初始交期确定。Agent 使用本地脚本校验并提交，描述使用中文；可接入 Codex PreToolUse，用户手动 Git 提交保持原样。安装、撤销、边界及统计见 [Git 规范说明](docs/git-conventions.md)。


### 集成测试全过程观测

测试设计首先生成业务总览与具名明细表，技术附录仍从同一 `test-cases.yaml` 派生。初始化、触发、完成判定、断言、清理和执行成本围绕这些用例设计，静态预检通过不等于服务已就绪。

各测试技能从首次 design 开始维护追加式 `test-timeline.jsonl`，用 `flow-test.ps1 timeline` 的 enter/pause/resume/finish/summary 记录阶段和原因。脚本统计总墙钟耗时、阶段往返、等待与用户介入；未知间隔如实标注，计时失败不阻断测试。实际断言埋点缺失时不推测首次断言时间。计时与30分钟执行硬预算独立，暂停和重启不能延长预算。

范围错误拒绝对应动作；参数、绑定及已授权环境修复后继续，不把所有错误变成用户审批。无关业务仓文件原样保留，经精确内容和构建影响审核排除；真正源码或配置漂移仍须解决。用每批实际覆盖、耗时和介入原因评价改进，不把框架回归当业务验收。详见 [观测与执行约定](codex/skills/flow-codex-core/references/test-observation.md)。
