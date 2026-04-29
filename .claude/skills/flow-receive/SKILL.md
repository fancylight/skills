---
name: flow-receive
description: "Child agent receives an assigned task, loads work protocol, and enters design phase. Use when a child agent is starting work on an assigned requirement. Examples: 'receive my task', 'start working on assigned specs', 'load my assignment'"
license: MIT
metadata:
  author: flow
  version: "0.2.0"
---

子 agent 接收根 agent 分配的任务，加载工作协议（工作流程.md + onboarding.md），检查变更通知，判断当前阶段。

执行 `/flow:receive` 开始。