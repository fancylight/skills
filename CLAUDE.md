# Flow Skill — 多 Agent 编排工作流

> Claude Code Skill，管理根 agent（编排者）与子 agent（执行者）的协作。

---

## 核心文档

| 文档 | 内容 |
|------|------|
| `flow-redesign.md` | **最终设计文档** — 目录结构、命令定义、工作流场景图、Schema 规范 |
| `flow/docs/schema.md` | 数据格式规范 — config.yaml、task.md、api.md 等字段定义 |
| `多阶段AI自动化开发流程（含Mermaid流程图）.md` | 最终愿景 — 多阶段 AI 自动化开发流程 |

---

## 命令清单

| 命令 | 角色 | 说明 |
|------|------|------|
| `/flow:init` | 根/子 | 初始化必要文件 |
| `/flow:design` | 根/子 | 根：概要设计 + task.md；子：spec 设计 + 自检 |
| `/flow:assign` | 根 | 分配任务给子 agent（内联执行 / 独立指令包） |
| `/flow:receive` | 子 | 接收任务，加载工作协议 |
| `/flow:apply` | 子 | 阶段二编码：按 spec 顺序执行编码→审核→测试循环 |
| `/flow:report` | 子 | 汇报，更新根 task.md，触发知识库维护 |
| `/flow:status` | 根 | 查看需求进度（spec 粒度） |
| `/flow:verify` | 根 | 跨服务接口契约验证 |
| `/flow:test` | 根 | 集成测试（HTTP/MQ/DB） |
| `/flow:change` | 根 | 需求变更协议 |
| `/flow:archive` | 根 | 归档已完成需求 |
| `/flow:hotfix` | 子 | 轻量级 bug 修复，跳过设计 |

---

## 目录结构

```
.claude/
├── commands/flow/      ← 12 个命令文件（显式调用）
├── skills/flow-*/      ← 12 个 SKILL.md（语义触发）
└── INSTALL.md          ← 安装说明

flow/
├── docs/schema.md      ← 数据格式规范
└── templates/          ← 命令模板文件

根目录/
├── CLAUDE.md           ← 本文件（项目入口）
├── flow-redesign.md    ← 最终设计文档
├── 多阶段AI自动化开发流程（含Mermaid流程图）.md
└── scripts/validate.js ← 静态验证脚本
```

---

## 安装

见 `.claude/INSTALL.md`。

---

## 设计要点

- **根 agent**：需求拆分、概要设计、维护 task.md、触发集成测试、归档
- **子 agent**：接收任务、spec 设计 + 自检、编码（内联审核/测试）、汇报
- **两种模式**：根指导模式 + 用户直接模式
- **平台限制**：根无法自动启动独立子 agent 会话（用户手动操作）
- **现阶段**：spec 粒度由根定义，子 agent 只做 spec 内部设计
