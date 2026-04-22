# Flow — Multi-Agent Orchestration Skill for Claude Code

多 agent 编排工作流 skill，用于管理根 agent（编排者）和子 agent（执行者）之间的协作。

## 项目结构

```
flow/
├── commands/          ← Claude Code skill 文件（/flow:* 命令）
│   ├── init.md        ← 项目初始化 / 创建新需求
│   ├── assign.md      ← 生成子 agent 指令包
│   ├── receive.md     ← 子 agent 接收任务
│   ├── report.md      ← 子 agent 提交汇报
│   ├── status.md      ← 查看需求进度
│   ├── verify.md      ← 验证跨服务接口契约
│   └── archive.md     ← 归档已完成需求
├── templates/         ← 文件模板（init 时复制到项目 .flow/templates/）
│   ├── config.yaml.tmpl
│   ├── onboarding.md.tmpl
│   ├── services.md.tmpl
│   ├── proposal.md.tmpl
│   ├── tasks.md.tmpl
│   ├── next-tasks.md.tmpl
│   ├── assign.md.tmpl
│   └── report.md.tmpl
└── docs/              ← 设计文档
    └── paradigm-v3-root-perspective.md
```

## 安装

### 方式 1：符号链接（推荐，开发时用）

```bash
# Windows (管理员 PowerShell)
New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\commands\flow" -Target "D:\code\self\skills\flow\commands"

# Linux/macOS
ln -s /path/to/skills/flow/commands ~/.claude/commands/flow
```

### 方式 2：复制

```bash
cp -r flow/commands/ ~/.claude/commands/flow/
```

安装后 Claude Code 会自动识别 `/flow:init`、`/flow:assign` 等命令。

## 命令一览

| 命令 | 角色 | 说明 |
|------|------|------|
| `/flow:init` | 根 agent | 初始化项目 或 创建新需求 |
| `/flow:assign <service>` | 根 agent | 为指定服务生成子 agent 指令包 |
| `/flow:status [change]` | 根 agent | 查看需求在各服务的进度 |
| `/flow:verify [change]` | 根 agent | 验证跨服务接口契约一致性 |
| `/flow:archive [change]` | 根 agent | 归档已完成的需求 |
| `/flow:receive` | 子 agent | 接收并启动分配的任务 |
| `/flow:report` | 子 agent | 提交结构化完成汇报 |

## 核心概念

### 两级 Agent 模型

- **根 agent（Orchestrator）**：在项目根目录工作，负责需求拆解、任务分配、进度追踪、契约验证
- **子 agent（Executor）**：在单个服务目录工作，负责设计、编码、测试、知识沉淀

### 复杂度分级（Tier）

| Tier | 场景 | 根 agent 介入度 |
|------|------|----------------|
| 1 | 单服务内需求 | 低（可选归档确认） |
| 2 | 跨 2-5 个服务 | 中（依赖排序、契约验证） |
| 3 | 平台级（5+ 服务） | 高（分阶段规划） |

### 插件式执行层

子 agent 可以使用任何 spec 工具（OpenSpec、自定义等），根 agent 不关心内部实现，只要求子 agent 遵守：领任务 → 设计 → 编码 → 验证 → 汇报。

## 快速开始

```
# 1. 在项目根目录初始化
/flow:init

# 2. 创建需求
/flow:init 统一登录系统改造

# 3. 分配任务给子 agent
/flow:assign user-service

# 4. 子 agent 接收任务
/flow:receive

# 5. 子 agent 完成后汇报
/flow:report

# 6. 查看进度
/flow:status

# 7. 验证接口契约
/flow:verify

# 8. 归档
/flow:archive
```
