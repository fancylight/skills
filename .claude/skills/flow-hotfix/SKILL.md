---
name: flow-hotfix
description: "Root agent creates hotfix entry in task.md and child service spec directory, then guides to assign for dispatching. Use when: 'fix this bug', 'hotfix for the login issue', 'quick fix needed', 'patch this problem'"
license: MIT
metadata:
  author: flow
  version: "0.2.0"
---

根 agent 为 bug 修复创建 hotfix 条目和 spec 目录，然后走 assign→receive→apply 通道派发编码。编码逻辑由 apply 统一处理。

执行 `/flow:hotfix <service-name> "bug 描述"` 开始。