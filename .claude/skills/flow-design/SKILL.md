---
name: flow-design
description: "Design phase — root agent creates overview design, task.md, and per-spec proposal+design; child mode (advanced) for autonomous spec design when knowledge base is mature"
license: MIT
metadata:
  author: flow
  version: "0.3.0"
---

根 agent：与用户协力完成概要设计、task.md，并为每个 spec 在子服务创建 proposal + design（现阶段主线）。
子 agent：为每个 spec 做 proposal + design + 内联自检（远期目标，需知识库成熟后启用）。

**Spec 粒度**：根 task 每个 `c{n}` = 1 git 仓库 = 1 OpenSpec change；跨仓 c 递增，禁止一行多仓。写 task.md 前读 `commands/flow/templates/task-md-maintenance.md` §2.2；概要设计须产出 Spec | 服务 | 职责矩阵。

开发文档规则见安装模板 `commands/flow/templates/dev-doc-maintenance.md`（§4.1 可部署服务、§4.2 SQL 自包含、§4.3 业务验收）。

执行 `/flow:design` 开始。