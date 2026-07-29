---
name: flow-codex-change
description: 将已批准的需求变更应用到现有 Flow 产物和受影响的 OpenSpec 设计。初始设计后范围发生变化时使用。
---

# Codex Flow 需求变更

读取 `../flow-codex-core/references/platform.md`。要求明确指定需求，写入前说明影响范围。更新根概要
设计、任务追踪、依赖关系和受影响服务的 OpenSpec 产物。重新检查受影响 specs 的 OpenSpec
readiness。保留已完成历史；新增后续 specs，不要重写已完成提交。

**新增 spec**：每个新 c 恰好一个 git 仓库；跨仓能力须拆成多个递增 c，禁止 `cN（service-a + service-b）`。写 task 开发顺序须符合 `task-md-maintenance.md` §2.2。

**链路同步**：变更涉及接口新增/删除、路径变化或调用方变化时，**MUST** 同步更新 `操作链路.md`（新增步骤标 `new`/`changed` 并填 `owning spec`；废弃步骤删除或标注），并重跑 `flow-codex-verify`（`verify_mode=design`，§A+§C+§D+§E）确认 §D/§E 无 ERROR。
