# Flow Skill — Agent 入口（Cursor / Codex）

> **Cursor 用户以本文件为唯一项目 Agent 入口。** 给人读的完整框架见 [README.md](./README.md)。本文档供在本仓库或已安装 flow-codex skills 的业务项目中工作的 **AI Agent** 快速定位规则与技能。

---

## 你在哪工作？

| 场景 | 先读什么 | 使用什么 skills |
|------|----------|-----------------|
| **维护本仓库**（`skills`） | [MAINTENANCE.md](./MAINTENANCE.md) | 改 `codex/skills/`、`flow/templates/`；跑 `codex/validate.ps1` |
| **业务编排根目录**（`.flow/config.yaml` → `role: orchestrator`） | 当前 change 的 `概要设计.md`、`task.md`；开发文档规则见安装模板 `dev-doc-maintenance.md` | `flow-codex-design` · `assign` · `status` · `verify` · `test-design` · `test-assign` · `test` · `archive` · `change` · `hotfix` |
| **线上反馈调查**（`.flow/feedback/`，与 change 无关） | 当前 feedback 的 `反馈记录.md`、`调查报告.md` | `flow-codex-feedback` · `flow-codex-kb feedback/{id}` |
| **业务服务目录**（`role: executor`） | 根 `task.md`、服务 OpenSpec、`工作流程.md` | `flow-codex-receive` · `apply` ·（经根调度）`report` |

**维护 skills 仓库时不要读业务 change 里的开发文档来改 skill**；改开发文档规则请编辑 `flow/templates/dev-doc-maintenance.md` 等源文件（见 MAINTENANCE.md §0）。

不要混用 Claude 斜杠命令（`/flow:*`）与 Codex skills（`flow-codex-*`）。

---

## Codex 生命周期（必须遵守）

```text
根：flow-codex-design
  → flow-codex-verify（verify_mode=design，§A+§C+§D+§E）无 ERROR
  → flow-codex-assign
  → 执行：flow-codex-receive → flow-codex-apply
  → 执行返回 REVIEW_REQUEST 并暂停
  → 根启动 flow-codex-review，回传 PASS / REJECT
  → 执行测试、提交，返回 REPORT_REQUEST
  → 根发放串行报告租约
  → 执行：flow-codex-report

业务 verify 全量 PASS 后 — 集成测试：
  flow-codex-test-design → flow-codex-test-assign
  → test-receive → test-apply → test-review → test-report
  → flow-codex-test → flow-codex-system-test（runner）
```

集成测试 spec 使用 `st-api-<change>`（glm-system-test），与业务 `c{n}` 分离。详见 `task-md-maintenance.md` §2.7。

**反馈闭环**（独立于上述 change 生命周期）：

```text
flow-codex-feedback（Intake → Discover → … → Conclude）
  → data-fix：工单 SQL → closed（默认不写 KB）
  → fix-now：直接改代码 →（可选）flow-codex-kb → closed
  → kb-only / 有稳定新规则：flow-codex-kb → closed
  → close
```

Discover 自动查已有 feedback、KB 选篇、`{root}/.flow/cdp` playbook（规范在 skill，产物不进 local_rag）。

详见 [flow/docs/schema.md](./flow/docs/schema.md) §11。feedback 不写 task.md、不走 hotfix 编排。

硬性规则（详见 [codex/PLAN.md](./codex/PLAN.md)、[codex/skills/flow-codex-core/references/platform.md](./codex/skills/flow-codex-core/references/platform.md)）：

- `1 spec = 1 executor = 1 commit`（spec = 根 task 单仓 OpenSpec change，非多仓 bundle）
- 根 task 每个 c{n} = 1 git repo = 1 OpenSpec change；跨仓须 c 递增拆分
- 仅**不同仓库**之间可并行写入；同一仓库禁止并发写入 Agent
- 根追踪文件（`task.md` 等）**串行**更新，禁止并发 report
- 分支不匹配或 worktree 有未确认历史改动时 **停止**，不要静默 checkout
- 每个 OpenSpec change 须 apply-ready，且 `verify_mode=design`（§A+§C+§D+§E）无 ERROR 后，才能声明设计完成 / 派发

---

## Skill 清单

### 公开（编排 / 执行入口）

| Skill | 角色 | 说明 |
|-------|------|------|
| `flow-codex-init` | 根/执行 | 初始化 `.flow/` |
| `flow-codex-design` | 根/执行 | 设计阶段；根产出概要设计、开发文档、task、OpenSpec |
| `flow-codex-assign` | 根 | 派发 spec |
| `flow-codex-receive` | 执行 | 加载任务与协议 |
| `flow-codex-apply` | 执行 | OpenSpec 实现；返回 REVIEW_REQUEST |
| `flow-codex-report` | 执行 | 更新根 `task.md`（须报告租约） |
| `flow-codex-status` | 根 | 只读进度 |
| `flow-codex-verify` | 根 | 格式 §A；design 模式 §A+§C+§D+§E（assign 前）；全量 §A+§B（test/archive 前） |
| `flow-codex-test-design` | 根 | verify 后产出 glm-system-test manifest / test-plan |
| `flow-codex-test-assign` | 根 | 向 glm-system-test 派发 `st-api-*` |
| `flow-codex-test-receive` | 执行 | 加载 manifest + test-plan |
| `flow-codex-test-apply` | 执行 | 编写 JUnit / fixtures / test-support |
| `flow-codex-test-report` | 执行 | 更新 task.md st-api 条目（须报告租约） |
| `flow-codex-test` | 根 | 集成测试门禁 + 委托 system-test + 更新检查清单 |
| `flow-codex-system-test` | 根/执行 | glm-system-test runner（doctor/run/evidence） |
| `flow-codex-change` | 根 | 需求变更 |
| `flow-codex-archive` | 根 | 归档 |
| `flow-codex-feedback` | 根/执行 | 线上反馈调查（Discover + 可选 data-fix；`.flow/feedback/`） |
| `flow-codex-kb` | 根/执行 | 知识库维护（change 或 `feedback/{id}` 入口） |
| `flow-codex-hotfix` | 根 | 热修通道（正式 assign 编排；非 feedback 默认路径） |

### 内部（由其他 skill 引用，非用户入口）

| Skill | 说明 |
|-------|------|
| `flow-codex-core` | 平台规则、checkpoint、模板路径 |
| `flow-codex-review` | 根调度的独立审核 Agent |

执行任何 `flow-codex-*` 前，按需读取 `flow-codex-core` 的 `references/platform.md` 与 `references/checkpoints.md`。

---

## 数据与模板

- **格式规范**：[flow/docs/schema.md](./flow/docs/schema.md)
- **模板源**：[flow/templates/](./flow/templates/)（安装时复制到 `flow-codex-core/assets/templates/`，并叠加 `flow/templates/codex/` 覆盖）
- **task.md 维护规则**：`flow/templates/task-md-maintenance.md`（含 §2.7 st-api）、`codex/skills/flow-codex-report/references/task-update-rules.md`、`codex/skills/flow-codex-test-report/references/task-update-rules.md`
- **业务项目文档边界**（概要设计 vs 开发文档）：业务 Flow 读安装模板 `dev-doc-maintenance.md`；skills 维护者读 [MAINTENANCE.md](./MAINTENANCE.md) §5 索引

---

## 维护本仓库时

1. 读 [MAINTENANCE.md](./MAINTENANCE.md)
2. 改 Codex skill → 跑 `codex/validate.ps1`
3. 改共享模板 → 确认 Claude 侧（`.claude/` + `install.sh`）是否需同步
4. 更新 [CHANGELOG.md](./CHANGELOG.md)

Claude Code 完整指令见 [docs/claude-code.md](./docs/claude-code.md)（经 [CLAUDE.md](./CLAUDE.md) 路由）。
