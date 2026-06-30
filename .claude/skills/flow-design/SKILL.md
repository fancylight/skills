---
name: flow-design
description: "Design phase — root agent creates overview design, task.md, and per-spec proposal+design; child mode (advanced) for autonomous spec design when knowledge base is mature"
license: MIT
metadata:
  author: flow
  version: "0.2.0"
---

根 agent：与用户协力完成概要设计、task.md，并为每个 spec 在子服务创建 proposal + design（现阶段主线）。
子 agent：为每个 spec 做 proposal + design + 内联自检（远期目标，需知识库成熟后启用）。

开发文档规则见安装模板 `commands/flow/templates/dev-doc-maintenance.md`。

执行 `/flow:design` 开始。