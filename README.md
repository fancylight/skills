# Flow Skill

多服务、多 Agent 协作研发的 **Skills 工作流框架**。把需求拆分、设计、编码、审核、测试、汇报、集成验证和知识沉淀，编码成可被 AI Agent 重复执行的指令集。

本仓库**不是业务项目**，而是 skills 源码与共享协议（`.flow/`）的定义处。业务项目（如 `glm`）在根目录初始化 `.flow/` 后，安装并调用这里的 skills。

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
- **粒度**：`1 task = 1 spec = 1 executor = 1 commit`（spec = 根 task 单仓 OpenSpec change；跨仓 c 递增，禁止多仓 bundle）。
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
