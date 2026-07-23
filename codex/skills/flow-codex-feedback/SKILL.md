---
name: flow-codex-feedback
description: 调查线上用户反馈或生产问题，产出结构化调查报告。与 change 体系无关；不修代码、不写 task.md。在收到 bug 反馈、字段异常、接口行为投诉时使用。
---

# Codex Flow 反馈调查

读取 `../flow-codex-core/references/platform.md` 与 `references/workflow.md`。

**定位**：独立事件流调查工具。输入原始反馈，输出 `.flow/feedback/{id}/` 下的调查报告。**禁止**在本 skill 内修改业务代码、写入 `task.md` 或创建 OpenSpec change。

## 输入

- 可选：`feedback_id`（缺省则生成 `{YYYY-MM-DD}-{kebab-slug}`）
- 必填材料：问题描述 +（接口路径 或 业务主键 之一）
- 可选：环境、请求参数、问题数据 JSON、截图说明

## 步骤

1. **Intake**
   - 定位根目录（子 agent 经 `config.yaml` 的 `root_path`）
   - 若无 `.flow/feedback/`，创建目录并从 `../flow-codex-core/assets/templates/feedback-index.md.tmpl` 渲染 `_index.md`
   - 创建 `.flow/feedback/{feedback_id}/`
   - 从 `feedback-record.md.tmpl` 渲染 `反馈记录.md`（仅此步骤写入，后续只读）
   - 从 `feedback-report.md.tmpl` 渲染 `调查报告.md`（`status=investigating`）
   - 在 `_index.md` 追加一行

2. **Orient** — 理解端/页面/操作/期望 vs 实际；缺材料写入调查日志「待补」

3. **Trace** — 追踪 Controller → Service → SQL → Adapter/Job；见 `references/gitnexus.md`

4. **Verify** — 假设 → SQL/日志 → 用户回传 → 更新「数据验证」表与调查日志

5. **Conclude** — 填根因；更新 frontmatter `type`、`resolution`、`status=confirmed`、`updated`

6. **Route** — 输出建议分流；更新 `_index.md` 的 status/type/resolution

## 分流（人工决策，不自动触发）

| resolution | 下一步 |
|------------|--------|
| fix-now | 在 `{fix_service}` 仓库**直接改代码并 commit**；回填「修复记录」与 `fix_commit`；再 `flow-codex-kb feedback/{id}` |
| fix-later / kb-only | `flow-codex-kb feedback/{id}` |
| close | 更新 `status=closed` 与 `closed` 日期 |
| pending | 保持 `status=investigating`，继续调查 |

**fix-now handoff 输出模板**：

```text
调查已完成。请在 {service} 仓库直接修复并 commit，
完成后回填 调查报告.md「修复记录」与 frontmatter.fix_commit，
再执行 flow-codex-kb feedback/{id} 沉淀坑点。
```

## 硬性约束

- 禁止修改 `task.md`、禁止创建 OpenSpec change
- 禁止在 Intake 之后修改 `反馈记录.md`
- 多轮调查只追加「调查日志」「数据验证」行
- 根/子均可执行；产物始终写**根** `.flow/feedback/`
