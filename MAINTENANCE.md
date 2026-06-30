# Flow Skill — 维护规范

> **只给维护本仓库（`skills`）的开发者与 Agent 看。**
>
> 在业务项目（如 `glm`）里跑 Flow、写 `开发文档.md` 的 Agent **不要读本文**——应读安装后的 `flow/templates/` 规则（见下文「两类读者」）。

使用 Flow 做业务开发的人读 [README.md](./README.md)。业务项目里工作的 Agent 读 [AGENTS.md](./AGENTS.md)。

---

## 0. 两类读者（勿混淆）

| 你在哪工作 | 读什么 | 不要读 |
|------------|--------|--------|
| **维护 `skills` 仓库**（改 codex skill、模板、install） | 本文 **MAINTENANCE.md** | 不必把本文拷进 skill 正文 |
| **业务项目**（`.flow/changes/...`，design/report/verify） | 安装后的运行时模板（见下表） | **MAINTENANCE.md**（仓库维护专用） |

**`flow/templates/` 源文件**：编辑在仓库里做；**执行**在业务项目里由 Flow skill 引用**安装副本**：

| 源文件（本仓库） | 安装后（Codex） | 安装后（Claude） | 给谁用 |
|------------------|-----------------|------------------|--------|
| `dev-doc-maintenance.md` | `~/.agents/skills/flow-codex-core/assets/templates/` | `~/.claude/commands/flow/templates/` | 业务 Flow：开发文档怎么写 |
| `dev-doc-update-rules.md` | 同上 | 同上 | 业务 Flow：report 怎么回写 |
| `verify-checklist.md` | 同上 | 同上 | 业务 Flow：verify/archive 检查 |
| `开发文档模板.md.tmpl` | 同上 | 同上 | design 生成骨架 |

改上表任一条规则时：**改 `flow/templates/` 源文件**，并同步引用它的 skill/command（§2、§3），**不要**在 MAINTENANCE 里再写一份完整细则。

---

## 1. 仓库职责

| 路径 | 职责 | 修改时注意 |
|------|------|------------|
| `codex/skills/flow-codex-*` | Codex/Cursor 技能实现 | 改完跑 `codex/validate.ps1` |
| `.claude/commands/flow/` | Claude 斜杠命令 | 与 `flow-*` skill 保持一致 |
| `.claude/skills/flow-*` | Claude 技能 | gitignore；改完用 `install.sh` 验证；**需纳入版本库时用 `git add -f .claude/`** |
| `flow/templates/` | **共享模板源** | Codex 覆盖放 `flow/templates/codex/` |
| `flow/docs/schema.md` | `.flow/` 数据格式 | 协议变更须同步两套 skills |
| `scripts/validate.js` | Claude 侧校验 | 注意路径是否仍指向 `.claude/` |
| `install.sh` / `codex/install.ps1` | 安装脚本 | 改模板路径须两边检查 |

**原则**：协议与模板尽量单一来源（`flow/`）；平台差异收敛到 skill 指令与 `codex/PLAN.md`。

---

## 2. 双平台同步清单

修改下列内容时，检查对侧是否需要同步：

| 变更类型 | Claude | Codex |
|----------|--------|-------|
| 新增/改 `.flow` 字段 | `flow/docs/schema.md` + 相关 command/skill | 同上 + `flow-codex-*` |
| 改任务/文档模板 | `flow/templates/*.tmpl` | `install.ps1` 会复制并做 `/flow:` → `$flow-codex-` 替换；特殊项写 `flow/templates/codex/` |
| 改工作流步骤 | `.claude/commands/flow/*.md` + skill | `codex/skills/flow-codex-*/SKILL.md` |
| 改审核/汇报机制 | 内联审核模板 `review-agent-prompt.md` | `flow-codex-review` + `checkpoints.md` |

不允许在 Codex skill 中硬编码 `~/\.claude`、`/flow:`、`TaskCreate` 等 Claude 专属语法（`validate.ps1` 会检查）。

---

## 3. 开发流程

### 3.1 改 Codex skill

1. 编辑 `codex/skills/<name>/SKILL.md`（及 `references/`、`agents/openai.yaml`）
2. 运行 `codex/validate.ps1`，确保无 ERROR
3. 本地 `codex/install.ps1` 安装到 `~/.agents/skills` 做冒烟
4. 更新 [CHANGELOG.md](./CHANGELOG.md)
5. 若涉及用户可见行为，更新 [README.md](./README.md) 或 [AGENTS.md](./AGENTS.md)

### 3.2 改 Claude skill / command

1. 编辑 `.claude/skills/` 或 `.claude/commands/flow/`
2. `./install.sh --dry-run` 预览
3. 运行 `node scripts/validate.js`（若脚本路径有效）
4. 更新 [CHANGELOG.md](./CHANGELOG.md)；必要时更新 [docs/claude-code.md](./docs/claude-code.md)

### 3.3 改共享模板（含业务 Flow 运行时规则）

1. 只改 `flow/templates/`（Codex 覆盖用 `flow/templates/codex/`）
2. 不要手改 `codex/skills/flow-codex-core/assets/templates/`——由 `install.ps1` 生成
3. 若改开发文档/verify 规则：改 `dev-doc-maintenance.md` 等源文件，并同步 §2 中列出的 skill/command
4. 模板正文靠前写受众与禁止项；细则放 `dev-doc-maintenance.md`，不要堆进 MAINTENANCE.md

---

## 4. 本仓库文档体系

| 文件 | 读者 | 何时更新 |
|------|------|----------|
| [README.md](./README.md) | 人 | 架构、安装、目录 |
| [AGENTS.md](./AGENTS.md) | Cursor/Codex Agent（**含**业务项目 Flow） | skill 清单、生命周期 |
| [CLAUDE.md](./CLAUDE.md) | 双宿主薄路由 | 入口指针 |
| [docs/claude-code.md](./docs/claude-code.md) | Claude Code Agent | `/flow:*` 命令 |
| **[MAINTENANCE.md](./MAINTENANCE.md)** | **仅 skills 仓库维护者** | 改 skill/模板流程 |
| [CHANGELOG.md](./CHANGELOG.md) | 所有人 | 发版记录 |
| [flow/docs/schema.md](./flow/docs/schema.md) | skills 维护者 + 业务 Flow | `.flow/` 协议 |
| [flow/templates/dev-doc-*.md](./flow/templates/) 等 | **业务 Flow Agent**（经 install 引用） | 改开发文档/verify 规则时 |

**不要**把 README 全文复制进 AGENTS.md 或 CLAUDE.md。  
**不要**把 `flow/templates/dev-doc-maintenance.md` 的全文复制进 MAINTENANCE.md——维护者只保留 §5 的索引即可。

---

## 5. 维护开发文档规则时（skills 维护者索引）

业务项目里的 `开发文档.md` 细则**不在本文**，见：

| 文档 | 内容 |
|------|------|
| [flow/templates/dev-doc-maintenance.md](./flow/templates/dev-doc-maintenance.md) | 章节结构、MUST/MUST NOT、阶段职责 |
| [flow/templates/dev-doc-update-rules.md](./flow/templates/dev-doc-update-rules.md) | report 增量回写 |
| [flow/templates/verify-checklist.md](./flow/templates/verify-checklist.md) | verify/archive 检查项 |
| [flow/docs/schema.md](./flow/docs/schema.md) §10 | 协议字段 |

你改 `flow-codex-design` / `flow-codex-report` / `flow-codex-verify`（及 Claude 侧 design/report/archive）时，须与上表**保持一致**。  
分工一句话：**概要设计 = Agent 编排；开发文档 = 人读交付**（勿互相照搬）。

---

## 6. 版本与 Changelog

- 功能性 skill 变更记入 [CHANGELOG.md](./CHANGELOG.md)，格式遵循 [Keep a Changelog](https://keepachangelog.com/)
- Skill `metadata.version`（Claude skill frontmatter）随重大变更递增
- 未安装到用户环境前，在 CHANGELOG 用 **Unreleased** 节

---

## 7. 校验命令

```powershell
# Codex（推荐每次改 codex/ 后执行）
.\codex\validate.ps1
```

```bash
# Claude
node scripts/validate.js
./install.sh --dry-run
```

---

## 8. 禁止事项

- 不要在 Codex skill 中引用 Claude 专属命令路径或工具名
- 不要未经 schema 变更修改 `.flow/` 文件含义
- 不要在 **MAINTENANCE.md** 里重复粘贴 `dev-doc-maintenance.md` 全文（业务规则以 `flow/templates/` 为唯一细则源）
- 不要让业务项目的 `开发文档.md` 承载 spec 名、审核返修、Flow 测试分层等编排信息
- 不要删除 [AGENTS.md](./AGENTS.md) / [CLAUDE.md](./CLAUDE.md)——它们是宿主约定入口；内容应薄，框架在 README
