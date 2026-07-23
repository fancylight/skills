---
name: flow-codex-kb
description: 维护 Flow 知识库。支持 change 上下文或 feedback 调查报告。持久业务规则、坑点、已知问题、运维指引时使用。
---

# Codex Flow 知识库

读取根 `config.yaml` 的 `knowledge_base` 配置。针对持久业务规则、集成契约、运维指引和可复用坑点提出简短 diff。**写入前请求确认**。

跳过：纯格式调整、无复用价值的 typo、一次性已处理脏数据（feedback 模式可仅 closed 不写 KB）。

## 入口 A：change（现有）

**输入**：`change-name`（`.flow/changes/{change-name}/`）

**数据源**：概要设计、开发文档、report 上下文

**步骤**：

1. 确认 KB 已启用
2. 读取 change 产物，提取可复用知识
3. 用户确认后写入 KB
4. 若 git 仓库，按 KB 规范提交

## 入口 B：feedback（新增）

**输入**：`feedback/{feedback-id}`（例如 `feedback/2026-07-20-seal-status-mismatch`）

**数据源**：`.flow/feedback/{feedback-id}/调查报告.md`

**步骤**：

1. 确认 KB 已启用；未启用则停止并说明
2. 读取 `调查报告.md`；要求 `status=confirmed`（closed 前一步）
3. 按 `references/feedback-kb-rules.md` 提取清单，**用户确认后**写入 KB
4. 回写调查报告 frontmatter `kb_ref`
5. 更新 `.flow/feedback/_index.md` 对应行
6. 提示是否将 feedback `status=closed` 并填 `closed` 日期

若 `resolution=fix-now` 且 `fix_commit` 为空，写入 KB 前提醒：修复是否已完成。

## 双入口选择

| 用户意图 | 入口 |
|----------|------|
| 需求/spec 完成后的知识沉淀 | change |
| 线上反馈调查结论沉淀 | feedback/{id} |
