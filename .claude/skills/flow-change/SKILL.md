---
name: flow-change
description: "Root agent handles requirement changes mid-development — updates overview design and task.md, appends change notifications for affected child agents. Use when: 'the requirement changed', 'update the spec for this feature', 'business logic has changed for the login flow'"
license: MIT
metadata:
  author: flow
  version: "0.1.0"
---

根 agent 处理大需求进行中的业务变更。核心规则：变更影响已完成 spec 时，重开原 spec 并通过 spec skills 更新子服务 design.md，而非新建 spec。

执行 `/flow:change` 开始。