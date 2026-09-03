---
name: flow-codex-feedback
description: 调查线上用户反馈或生产问题，产出结构化调查报告。Intake 后自动 Discover（已有 feedback、KB、CDP playbook）。与 change 体系无关；不修代码、不写 task.md。在收到 bug 反馈、字段异常、接口行为投诉或需 data-fix 时使用。
---

# Codex Flow 反馈调查

读取 `../flow-codex-core/references/platform.md`、`references/workflow.md`、
`references/cdp.md`、`references/discover-kb.md`。

**定位**：独立事件流调查工具。输入原始反馈，输出 `.flow/feedback/{id}/` 下的调查报告。**禁止**在本 skill 内修改业务代码、写入 `task.md` 或创建 OpenSpec change。**禁止**自动执行写库 SQL。

## 输入

- 可选：`feedback_id`（缺省则生成 `{YYYY-MM-DD}-{kebab-slug}`）
- **用户必填**：问题描述 +（接口路径 **或** 业务主键 之一）
- 可选：环境、请求参数、问题数据 JSON、截图说明
- KB / 已有 feedback / CDP playbook **不是**用户必填；由 Discover 自动查找

## 步骤

1. **Intake**
   - 定位根目录（子 agent 经 `config.yaml` 的 `root_path`）
   - 若无 `.flow/feedback/`，创建目录并从 `../flow-codex-core/assets/templates/feedback-index.md.tmpl` 渲染 `_index.md`
   - 创建 `.flow/feedback/{feedback_id}/`
   - 从 `feedback-record.md.tmpl` 渲染 `反馈记录.md`（仅此步骤写入，后续只读）
   - 从 `feedback-report.md.tmpl` 渲染 `调查报告.md`（`status=investigating`，`remediation=pending`）
   - 在 `_index.md` 追加一行

2. **Discover**（用户材料齐后立即执行；产出写入调查日志一轮）
   - **2.1 已有 feedback**：读 `.flow/feedback/_index.md`；按接口/主键/标题关键词 grep 历史目录；命中则日志记 `相关 feedback：{id}`（可填 `duplicate_of`）
   - **2.2 知识库选篇**：按 `references/discover-kb.md`（3 跳、每跳≤3、全程≤8）；日志 `已读 KB：[…]`
   - **2.3 CDP**：按 `references/cdp.md` 读 `{root}/.flow/cdp/README.md` 索引并选用 playbook；缺口记 `CDP 缺口：{场景}`（不阻塞）；**勿**把维护规则写进 `.flow/cdp/README`

3. **Orient** — 理解端/页面/操作/期望 vs 实际；缺材料写入调查日志「待补」

4. **Trace** — 追踪 Controller → Service → SQL → Adapter/Job；先读 `../flow-codex-core/assets/templates/feedback-trace-rules.md`。按目标服务 / 模块判定语言：Java 优先 IDEA MCP，不可用时暂停并提示用户打开对应工程或明确授权 GitNexus，禁止静默回退；非 Java 保留 GitNexus 优先策略。需要查库时遵循已选用的 CDP playbook

5. **Verify** — 假设 → SQL/日志 → 用户回传 → 更新「数据验证」表与调查日志（默认只读查询）

6. **Conclude** — 填根因；更新 frontmatter `type`、`resolution`、`remediation`、`status=confirmed`、`updated`
   - 调查日志一行：`KB 沉淀：否（默认）/ 是（理由：…）`
   - `remediation=data-fix` 时填「数据修复说明」（修改内容 / 根本原因 / 影响范围 + 预览/修正/验证 SQL）

7. **Route** — 输出建议分流；更新 `_index.md` 的 status/type/resolution

## 字段正交（type vs resolution vs remediation）

| 字段 | 管什么 |
|------|--------|
| `type` | 问题性质：`bug` / `data-issue` / `by-design` / `unknown` |
| `resolution` | 收尾路径：`fix-now` / `fix-later` / `data-fix` / `kb-only` / `close` / `pending` |
| `remediation` | 修复形态：`pending` / `data-fix` / `code-fix` / `none` |

典型组合：`type=data-issue` + `resolution=data-fix` + `remediation=data-fix`；`type=bug` + `resolution=fix-now` + `remediation=code-fix`。

## 分流（人工决策，不自动触发）

| resolution | remediation | 下一步 |
|------------|-------------|--------|
| data-fix | data-fix | 将「数据修复说明」交用户/工单执行 SQL；skill **不**自动 UPDATE；完成后可 `closed`（**不强制** kb） |
| fix-now | code-fix | 在 `{fix_service}` 仓库**直接改代码并 commit**；回填「修复记录」与 `fix_commit`；再按 Conclude 的 KB 沉淀行决定是否 `flow-codex-kb` |
| fix-later | code-fix | 记录待修；KB 仅当有稳定新规则时 |
| kb-only | none | `flow-codex-kb feedback/{id}`（须有可沉淀规则） |
| close | none | 更新 `status=closed` 与 `closed` 日期 |
| pending | pending | 保持 `status=investigating`，继续调查 |

**data-fix handoff**：

```text
调查已完成（data-fix）。请按调查报告「数据修复说明」由工单执行修正 SQL，
执行后用验证 SQL 核对。无需改代码；默认不写 KB（个案脏数据）。
确认修复后将 status=closed。
```

**fix-now handoff**：

```text
调查已完成。请在 {service} 仓库直接修复并 commit，
完成后回填 调查报告.md「修复记录」与 frontmatter.fix_commit，
若 Conclude 标明 KB 沉淀=是，再执行 flow-codex-kb feedback/{id}。
```

## 硬性约束

- 禁止修改 `task.md`、禁止创建 OpenSpec change
- 禁止在 Intake 之后修改 `反馈记录.md`
- 禁止自动执行写库 SQL；禁止把反馈流水账 / 运维 SQL / 单次 MERGE 灌进 `local_rag`
- CDP 维护规则只在 `references/cdp.md`，不在 `.flow/cdp/README.md`
- 多轮调查只追加「调查日志」「数据验证」行
- 根/子均可执行；产物始终写**根** `.flow/feedback/`
