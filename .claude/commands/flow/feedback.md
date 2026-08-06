---
name: "Flow: Feedback"
description: "Investigate production user feedback with Discover (existing feedback, KB, CDP playbook); structured report under .flow/feedback/"
category: Workflow
tags: [workflow, feedback, investigation]
version: "0.2.0"
---

线上反馈调查。输入原始反馈，产出 `.flow/feedback/{id}/` 调查报告。**不修代码、不写 task.md、不建 spec**。**禁止**自动执行写库 SQL。

**输入**：`/flow:feedback "简短标题"`  
可选续查：`/flow:feedback {feedback-id}`

模板：`feedback-index.md.tmpl`、`feedback-record.md.tmpl`、`feedback-report.md.tmpl`、`cdp-playbook.md.tmpl`；规则见 `feedback-kb-rules.md`。协议：`flow/docs/schema.md` feedback 节。

---

**前置检查**

1. 根目录存在 `.flow/config.yaml`（executor 经 `root_path`）
2. 收集：问题描述 +（接口路径 **或** 业务主键 之一）

---

**步骤**

1. **Intake**（新反馈）
   - 无 `.flow/feedback/` 时创建并从 `feedback-index.md.tmpl` 复制 `_index.md`
   - `feedback_id`：`{YYYY-MM-DD}-{kebab-slug}`
   - 渲染 `反馈记录.md`（**仅此步写入，后续只读**）与 `调查报告.md`（`status=investigating`，`remediation=pending`）
   - `_index.md` 追加一行

2. **Discover**（材料齐后立即执行；写入调查日志一轮）
   - **2.1 已有 feedback**：读 `_index.md`；按接口/主键/标题 grep 历史；命中记 `相关 feedback：{id}`（可 `duplicate_of`）
   - **2.2 知识库选篇**：有限跳数选篇（建议 3 跳、每跳≤3、全程≤8）；日志 `已读 KB：[…]`
   - **2.3 CDP**：读 `{root}/.flow/cdp/README.md` 索引并选用 playbook（模板见 `cdp-playbook.md.tmpl`）；缺口记 `CDP 缺口：{场景}`（不阻塞）；**勿**把维护规则写进 cdp README

3. **Orient** — 端/页面/操作/期望 vs 实际；缺材料写入调查日志

4. **Trace** — Controller → Service → SQL → Adapter/Job；查库遵循已选 CDP playbook

5. **Verify** — 假设 → SQL/日志 → 用户回传 → 更新「数据验证」表（默认只读查询）

6. **Conclude** — 填根因；更新 `type`、`resolution`、`remediation`、`status=confirmed`
   - 日志一行：`KB 沉淀：否（默认）/ 是（理由：…）`
   - `remediation=data-fix` 时填「数据修复说明」（修改内容 / 根本原因 / 影响范围 + 预览/修正/验证 SQL）

7. **Route** — 输出建议分流；更新 `_index.md`

---

**字段正交**

| 字段 | 管什么 |
|------|--------|
| `type` | `bug` / `data-issue` / `by-design` / `unknown` |
| `resolution` | `fix-now` / `fix-later` / `data-fix` / `kb-only` / `close` / `pending` |
| `remediation` | `pending` / `data-fix` / `code-fix` / `none` |

**分流（人工）**

| resolution | 下一步 |
|------------|--------|
| data-fix | 交工单执行 SQL；skill **不**自动 UPDATE；默认不写 KB |
| fix-now | 在服务仓直接改代码并 commit；回填 `fix_commit`；再按 KB 沉淀行决定 `/flow:kb feedback/{id}` |
| fix-later / kb-only | `/flow:kb feedback/{id}`（须有可沉淀规则） |
| close | `status=closed`，填 `closed` 日期 |

---

**约束**

- 禁止改 `task.md`、禁止创建 OpenSpec change
- Intake 后禁止改 `反馈记录.md`
- 多轮只追加「调查日志」「数据验证」
