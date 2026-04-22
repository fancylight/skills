[根目录](../CLAUDE.md) > **flow**

# Flow — 多 Agent 编排工作流 Skill

> Claude Code Skill，用于管理根 agent（编排者）和子 agent（执行者）之间的协作。

---

## 模块职责

提供一套完整的命令集和模板体系，支撑多 Agent 协作的完整生命周期：
- **项目初始化**：自动识别服务结构，生成 `.flow/` 配置脚手架
- **需求管理**：创建需求（proposal）、拆解任务（tasks）、追踪进度（status）
- **任务分配**：为子 agent 生成标准化指令包（assign）
- **执行与汇报**：子 agent 接收任务（receive）、完成汇报（report）
- **契约验证**：跨服务接口契约一致性检查（verify）
- **归档闭环**：需求完成后的归档与知识审核（archive）

---

## 入口与启动

### 安装入口

```bash
# 方式 1：符号链接（开发推荐）
# Windows (管理员 PowerShell)
New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\commands\flow" -Target "D:\wl\code\skills\flow\commands"

# Linux/macOS
ln -s /path/to/skills/flow/commands ~/.claude/commands/flow

# 方式 2：复制
cp -r flow/commands/ ~/.claude/commands/flow/
```

### 使用入口

| 命令 | 触发方式 | 适用角色 |
|------|---------|---------|
| `/flow:init [需求描述]` | 无参数=项目初始化；有参数=创建新需求 | 根 agent |
| `/flow:assign <service>` | 指定服务名 | 根 agent |
| `/flow:status [change]` | 可选指定需求名 | 根 agent |
| `/flow:verify [change]` | 可选指定需求名 | 根 agent |
| `/flow:archive [change]` | 可选指定需求名 | 根 agent |
| `/flow:receive` | 无参数，自动读取配置 | 子 agent |
| `/flow:report` | 无参数，自动收集信息 | 子 agent |

---

## 对外接口

### 命令文件清单（Claude Code Skill 接口）

所有命令文件位于 `commands/` 目录，采用 YAML frontmatter + Markdown 行为描述的结构：

| 文件 | 命令 | 核心功能 |
|------|------|---------|
| `init.md` | `/flow:init` | 项目初始化 / 创建新需求 |
| `assign.md` | `/flow:assign` | 生成子 agent 指令包 |
| `receive.md` | `/flow:receive` | 子 agent 接收任务 |
| `report.md` | `/flow:report` | 子 agent 提交汇报 |
| `status.md` | `/flow:status` | 查看需求进度 |
| `verify.md` | `/flow:verify` | 验证跨服务接口契约 |
| `archive.md` | `/flow:archive` | 归档已完成需求 |

### 模板文件清单（生成产物模板）

| 文件 | 用途 | 模板引擎 |
|------|------|---------|
| `templates/config.yaml.tmpl` | `.flow/config.yaml` 项目配置 | Handlebars |
| `templates/child-config.yaml.tmpl` | 子 agent 配置 | Handlebars |
| `templates/onboarding.md.tmpl` | 子 agent 启动指南 | Handlebars |
| `templates/services.md.tmpl` | 服务地图文档 | Handlebars |
| `templates/proposal.md.tmpl` | 需求提案文档 | Handlebars |
| `templates/tasks.md.tmpl` | 任务清单文档 | Handlebars |
| `templates/next-tasks.md.tmpl` | 详细任务说明 | Handlebars |
| `templates/assign.md.tmpl` | 子 agent 指令包 | Handlebars |
| `templates/report.md.tmpl` | 完成汇报模板 | Handlebars |

### 设计文档

| 文件 | 内容 |
|------|------|
| `docs/paradigm-v3-root-perspective.md` | GLM Agent 开发范式 V3，定义编排层与执行层的职责边界、复杂度分级（Tier 1/2/3）、状态管理模型、知识库协作模型 |
| `docs/schema.md` | Flow Schema 规范，定义 config.yaml、tasks.md 元数据头、api.md、proposal.md、report 的完整字段与格式规范 |

---

## 关键依赖与配置

### 运行时依赖

- **Claude Code**：命令通过 Claude Code 的 Skill 机制加载，依赖其 `AskUserQuestion`、`TaskCreate` 等工具。
- **文件系统**：命令执行时读写 `.flow/` 目录下的 YAML 和 Markdown 文件。
- **Git**：`report` 命令读取 git log 定位本次工作的 commit。

### 配置结构

由 `init` 命令生成的 `.flow/config.yaml` 示例：

```yaml
project:
  name: ""
  role: "orchestrator"  # orchestrator（根）或 executor（子）
  created: ""

services:
  - name: ""
    path: ""
    type: ""
    description: ""

knowledge_base:
  enabled: false
  path: ""
  child_write: true
  review_on_archive: true

conventions:
  task_id_prefix: ""
  branch_pattern: "feature/<kebab-case>"
  commit_format: "{type}: {description}"

child_agent:
  spec_tool: ""
  onboarding_doc: ".flow/onboarding.md"
```

---

## 数据模型

### Change 目录结构（根 agent 维护）

```
.flow/changes/{change-name}/
├── proposal.md       # 需求背景、目标、涉及服务、接口契约
├── tasks.md          # 按服务分组的任务清单（带元数据头）
└── next-tasks.md     # 详细任务说明（Tier 2+ 生成）
```

### tasks.md 元数据头

```markdown
---
requirement: {标题}
status: planning
 tier: {1/2/3}
branch: {分支名}
services: [{服务列表}]
created: {日期}
updated: {日期}
---
```

### 子服务 change 结构（子 agent 维护）

```
openspec/changes/{change-name}/
├── .openspec.yaml
├── proposal.md
├── design.md
├── tasks.md
├── api.md            # 对外暴露的接口
└── {上游服务}-api.md  # 期望上游提供的接口
```

---

## 测试与质量

- **无自动化测试**：本模块为纯文档/模板型 Skill，无单元测试或集成测试。
- **验证方式**：在 Claude Code 中安装后，通过实际对话测试各命令。
- **模板校验**：修改 `.tmpl` 文件后，需检查对应命令文件中的变量注入逻辑是否同步。
- **回归检查**：修改 `commands/*.md` 后，确认 YAML frontmatter 的 `name/description/category/tags` 完整。

---

## 常见问题 (FAQ)

**Q：如何新增一个 flow 命令？**
A：在 `commands/` 目录新建 `{command-name}.md`，参照现有文件的 YAML frontmatter 格式编写。Claude Code 会自动识别 `/flow:{command-name}`。

**Q：模板变量如何与命令逻辑对应？**
A：命令文件中的 Markdown 描述负责逻辑流程，模板文件（`.tmpl`）负责最终输出格式。命令中需明确列出向模板注入的变量名和类型。

**Q：子 agent 可以使用自己的 spec 工具吗？**
A：可以。根 agent 不强制子 agent 使用特定工具，只要求遵守工作循环：接收任务 -> 设计 -> 编码 -> 验证 -> 汇报。

**Q：Tier 分级如何影响流程？**
A：Tier 1（单服务）根 agent 几乎不介入；Tier 2（2-5 服务）根 agent 负责依赖排序和契约验证；Tier 3（5+ 服务）需要分阶段规划（当前未完全实现）。

---

## 相关文件清单

### 命令文件
- `commands/init.md` — 项目初始化 / 创建新需求
- `commands/assign.md` — 生成子 agent 指令包
- `commands/receive.md` — 子 agent 接收任务
- `commands/report.md` — 子 agent 提交汇报
- `commands/status.md` — 查看需求进度
- `commands/verify.md` — 验证跨服务接口契约
- `commands/archive.md` — 归档已完成需求

### 模板文件
- `templates/config.yaml.tmpl` — 项目配置模板
- `templates/child-config.yaml.tmpl` — 子 agent 配置模板
- `templates/onboarding.md.tmpl` — 子 agent 启动指南模板
- `templates/services.md.tmpl` — 服务地图模板
- `templates/proposal.md.tmpl` — 需求提案模板
- `templates/tasks.md.tmpl` — 任务清单模板
- `templates/next-tasks.md.tmpl` — 详细任务说明模板
- `templates/assign.md.tmpl` — 指令包模板
- `templates/report.md.tmpl` — 汇报模板

### 设计文档
- `docs/paradigm-v3-root-perspective.md` — Agent 开发范式 V3 设计文档
- `docs/schema.md` — Schema 规范文档

### 验证脚本
- `../scripts/validate.js` — 静态验证脚本（检查 frontmatter、模板语法、引用一致性）

### 版本记录
- `CHANGELOG.md` — 版本变更记录

---

## 变更记录 (Changelog)

### 2026-04-22（优化迭代）
- 精简 `README.md`，去重信息统一指向 `CLAUDE.md`。
- 移除所有硬编码项目路径，统一使用模板变量与占位符。
- 统一 `assign.md` 命令与模板格式，新增 `child-config.yaml.tmpl`。
- 增加 Schema 规范文档（`docs/schema.md`）。
- 增加基础验证脚本（`../scripts/validate.js`）。
- 增加 `CHANGELOG.md` 与命令 `version` 字段。
- 完善命令逻辑：跨平台归档、状态优先级、report 检测规则、Tier 3 标注。

### 2026-04-22 15:33:54
- 初始化模块 AI 上下文文档（`CLAUDE.md`）。
- 扫描模块全部 17 个文件，提取命令接口、模板结构、设计范式。
- 添加导航面包屑与变更记录。
