---
name: flow-design
description: "Design phase for flow workflow. Root agent: create overview design and task.md with spec-level breakdown. Child agent: create per-spec proposal and design, then run inline self-review. Use when: 'create the design for this requirement', 'design the specs for my service', 'run design self-check'"
license: MIT
metadata:
  author: flow
  version: "0.1.0"
---

设计阶段命令，双角色行为：根 agent 生成概要设计和 task.md；子 agent 为每个 spec 做 proposal+design 并内联自检。

执行 `/flow:design` 开始。