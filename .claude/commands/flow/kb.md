---
name: "Flow: KB"
description: "Maintain knowledge base from change context or feedback investigation report"
category: Workflow
tags: [workflow, knowledge-base, feedback]
version: "0.2.0"
---

知识库维护。根/子均可使用。**写入前经用户确认**。

**输入**（二选一）：

- `/flow:kb <change-name>` — 从 change 产物沉淀
- `/flow:kb feedback/{feedback-id}` — 从反馈调查报告沉淀

---

**前置检查**

1. 根 `.flow/config.yaml` 中 `knowledge_base.enabled=true`；否则停止并说明
2. 读取 KB `maintenance_guide` / `overview`（若配置）

---

**入口 A：change**

1. 读取 `.flow/changes/{change-name}/` 概要设计、开发文档等
2. 提取可复用知识清单，用户确认后写入 KB
3. 若 KB 为 git 仓库，按规范提交

跳过：纯格式调整、普通 bug 修复、无复用价值的内部重构。

---

**入口 B：feedback**

1. 读取 `.flow/feedback/{feedback-id}/调查报告.md`
2. 要求 `status=confirmed`（closed 前一步）
3. 按 `feedback-kb-rules.md`（模板目录）提取清单，用户确认后写入 KB
4. 回写调查报告 `kb_ref`；更新 `_index.md`
5. 提示是否 `status=closed` 并填 `closed`

若 `resolution=fix-now` 且 `fix_commit` 为空，提醒修复是否已完成。

映射与段落模板详见 `~/.claude/commands/flow/templates/feedback-kb-rules.md`（与 Codex `flow-codex-kb/references/` 同源，install 时复制）。

---

**约束**

- feedback 模式不读取 task.md
- feedback-kb 与 report 内 KB 判断独立，不冲突
