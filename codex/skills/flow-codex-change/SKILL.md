---
name: flow-codex-change
description: 将已批准的需求变更应用到现有 Flow 产物和受影响的 OpenSpec 设计。初始设计后范围发生变化时使用。
---

# Codex Flow 需求变更

需求命名、分支与提交遵循 `../flow-codex-core/references/git-conventions.md`；已有需求读取根 change.json；实际写入 Git 仓库前按该规则绑定并校验，提交使用公共脚本，中文描述贯穿业务、文档和测试。

按 `../flow-codex-core/references/first-delivery.md` 核对变动承诺的提供方、消费者、保存校验和最终输出，声明仍有效证据与必须重验范围。按原 spec 修复并在同一对话收尾，不因变化而强制新开对话。

质量要求：读取 ../flow-codex-core/assets/templates/engineering-quality.md 的「设计与验证、文档与汇报」。沿用现有结果与授权机制，不增加阶段。

读取 `../flow-codex-core/references/platform.md`。要求明确指定需求，写入前说明影响范围。更新根概要
设计、任务追踪、依赖关系和受影响服务的 OpenSpec 产物。重新检查受影响 specs 的 OpenSpec
readiness。读取 ../flow-codex-core/references/delivery.md：原范围修复按 task-md-maintenance.md §3.3 重开原 spec，只有新增范围才用 §3.4 新增 spec；保留旧 Git 提交，以后续提交修复。

**新增 spec**：每个新 c 恰好一个 git 仓库；跨仓能力须拆成多个递增 c，禁止 `cN（service-a + service-b）`。写 task 开发顺序须符合 `task-md-maintenance.md` §2.2。

**链路同步**：变更涉及接口新增/删除、路径变化或调用方变化时，**MUST** 同步更新 `操作链路.md`（新增步骤标 `new`/`changed` 并填 `owning spec`；废弃步骤删除或标注），并重跑 `flow-codex-verify`（`verify_mode=design`，§A+§C+§D+§E）确认 §D/§E 无 ERROR。

**SQL 契约同步**：变更新增/修改列表、分页、报表 SQL，或改变 JOIN / 选行 / 过滤逻辑时，**MUST** 同步更新根「数据访问契约」和受影响 OpenSpec；重跑 `flow-codex-verify`（`verify_mode=design`，含 §F.1–§F.3）确认无 ERROR。实现完成后重新设计 SQL 计划验证，归档前执行 `verify_mode=release`。
