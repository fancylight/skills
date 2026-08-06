# Flow Skill — Claude Code Agent 入口

> **Cursor 用户**请读 [AGENTS.md](../AGENTS.md)。**维护本仓库**（任一工具）必须先读 [MAINTENANCE.md](../MAINTENANCE.md)。  
> **Claude Code 会话开始：请完整阅读本文件。**

---

## 安装

```bash
./install.sh              # ~/.claude
./install.sh --project    # 当前项目 .claude
./install.sh --dry-run    # 预览
```

安装内容：`commands/flow/*`、`skills/flow-*`、`flow/templates/`（剔除 `templates/codex/`）、`flow/scripts/*.ps1`、`flow/docs/*.md`、`templates/system-test/`。

本仓库 `.claude/` 为开发源码（见 [MAINTENANCE.md](../MAINTENANCE.md) §1）；`install.sh` 复制到 Claude 配置目录。安装后重启或 `/reload-plugins`，输入 `/flow:` 应出现命令补全。

静态校验：`node scripts/validate.js`。

---

## 命令与 Skills

正文唯一源：`.claude/commands/flow/<verb>.md`。Skill 仅为薄 stub，指向 `/flow:<verb>`。

| 命令 | 角色 | 说明 |
|------|------|------|
| `/flow:init` | 根/子 | 初始化 `.flow/` |
| `/flow:design` | 根/子 | domain → DOMAIN_VERIFIED → 方案/链路/SQL/OpenSpec |
| `/flow:verify` | 根 | `format\|domain\|design\|full\|release`（过渡 `legacy-api`） |
| `/flow:assign` | 根 | design 门禁后派发；lease-v1 根循环调度 review/report |
| `/flow:receive` | 子 | 领取任务 |
| `/flow:apply` | 子 | 实现；lease-v1 发 `REVIEW_REQUEST`/`REPORT_REQUEST` |
| `/flow:review` | 根调度 peer | 只读审核，输出 `[REVIEW_RESULT]` |
| `/flow:report` | 子 | lease-v1 须 `REPORT_LEASE_GRANTED` |
| `/flow:status` | 根 | 进度 + protocol 标记 |
| `/flow:change` | 根 | 变更管理 |
| `/flow:archive` | 根 | release verify + 集成测试 PASS |
| `/flow:test` | 根 | controller `next` 编排入口 |
| `/flow:test-design` | 根 | 集成测试设计产物 |
| `/flow:test-verify` | 根 | design/implementation/result 门禁 |
| `/flow:test-assign` | 根 | 派发 st-api |
| `/flow:test-receive` | 子 | 测试任务领取 |
| `/flow:test-apply` | 子 | 测试实现 |
| `/flow:test-report` | 子 | 测试汇报 |
| `/flow:system-test` | 根 | runner / evidence |
| `/flow:feedback` | 根/子 | Discover + CDP；不修代码 |
| `/flow:kb` | 根/子 | change 或 `feedback/{id}` 沉淀 |
| `/flow:hotfix` | 根 | 热修通道 |

模板安装路径：`commands/flow/templates/`。脚本：`commands/flow/scripts/`。协议：`commands/flow/docs/control-plane.md`、`schema.md`、`test-controller.md`。

迁移（进行中 change）：[claude-lease-migration.md](./claude-lease-migration.md)。

---

## 与 Codex 的关键差异

| 项 | Claude Code | Codex |
|----|-------------|-------|
| 触发 | `/flow:*` 斜杠命令 | `flow-codex-*` skill |
| 审核（lease-v1） | 根收 `REVIEW_REQUEST` → 跑 `/flow:review` → follow-up 注入 `REVIEW_RESULT` | 根 pause/resume sibling + `flow-codex-review` |
| 汇报（lease-v1） | 根串行发 `REPORT_LEASE_GRANTED` 后子 `/flow:report` | 同词法，`flow-codex-report` |
| 兼容（legacy） | 内联审核 + 直接 report（警告） | 不适用主路径 |
| 安装 | `install.sh` | `codex/install.ps1` |

**共享 SoT**：`.flow/` 协议、[flow/docs/schema.md](../flow/docs/schema.md)、[flow/docs/control-plane.md](../flow/docs/control-plane.md)、`flow/templates/**`、`flow/scripts/*.ps1`。宿主包只适配触发与 Agent 拉起，**禁止**第二套 lease 语义。

`protocol_version`：缺省 `legacy`（不打断进行中 change）；新建 change 的 design 写 `lease-v1`。

---

## 角色与约束

- **根 Agent**：需求拆分、概要设计、派发、进度、集成测试编排、归档；**不编码、不提交、不写 task.md 完成勾选**
- **子 Agent**：receive → apply →（根调度 review）→（租约后）report
- `1 task = 1 spec = 1 agent = 1 commit`
- 根无法自动启动独立子会话时，需用户在服务目录手动打开 Claude Code；lease-v1 下审核/租约仍由**根会话**调度

场景流程图见 [流程文档.md](../流程文档.md)。
