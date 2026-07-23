# Flow Skill — Claude Code Agent 入口

> **Cursor 用户**请读 [AGENTS.md](../AGENTS.md)。**维护本仓库**（任一工具）必须先读 [MAINTENANCE.md](../MAINTENANCE.md)。  
> **Claude Code 会话开始：请完整阅读本文件。**

---

## 安装

```bash
./install.sh              # ~/.claude
./install.sh --project    # 当前项目 .claude
```

详见 `.claude/INSTALL.md`。安装后重启 Claude Code，输入 `/flow:` 应出现命令补全。

本仓库 `.claude/` 为开发源码（见 [MAINTENANCE.md](../MAINTENANCE.md) §1 关于 gitignore 的说明）；`install.sh` 将其复制到 Claude 配置目录。

---

## 命令与 Skills

| 命令 | 角色 | Skill |
|------|------|-------|
| `/flow:init` | 根/子 | flow-init |
| `/flow:design` | 根/子 | flow-design |
| `/flow:assign` | 根 | flow-assign |
| `/flow:receive` | 子 | flow-receive |
| `/flow:apply` | 子 | flow-apply |
| `/flow:report` | 子 | flow-report |
| `/flow:status` | 根 | flow-status |
| `/flow:verify` | 根 | flow-verify |
| `/flow:test` | 根 | flow-test |
| `/flow:change` | 根 | flow-change |
| `/flow:archive` | 根 | flow-archive |
| `/flow:feedback` | 根/子 | flow-feedback |
| `/flow:kb` | 根/子 | flow-kb（`<change-name>` 或 `feedback/{id}`） |
| `/flow:hotfix` | 根 | flow-hotfix |

执行命令时读取同名 `flow-*` skill 的 `SKILL.md`。模板安装路径：`commands/flow/templates/`（来自 `flow/templates/`）。

---

## 与 Codex 的关键差异

| 项 | Claude Code | Codex |
|----|-------------|-------|
| 审核 | 子 Agent **内联**启动审核 Agent | 根 Agent 调度 `flow-codex-review` |
| 汇报 | 子 Agent 直接 `/flow:report` | 根发放串行租约后 `flow-codex-report` |
| 触发 | `/flow:*` 斜杠命令 | `flow-codex-*` skill 名 |

共享 `.flow/` 协议与 [flow/docs/schema.md](../flow/docs/schema.md)。平台差异见 [codex/PLAN.md](../codex/PLAN.md)。

---

## 角色与约束

- **根 Agent**：需求拆分、概要设计、派发、进度、集成测试、归档；**不编码、不提交、不写 task.md 完成勾选**
- **子 Agent**：receive → apply（编码·内联审核·测试·提交）→ report
- `1 task = 1 spec = 1 agent = 1 commit`
- 根无法自动启动独立子会话，需用户在服务目录手动打开 Claude Code

场景流程图见 [流程文档.md](../流程文档.md)。
