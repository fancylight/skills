---
name: flow-assign
description: "Root agent assigns work to a child agent — inline execution or instruction package. Use when: 'assign task to service-a', 'start coding for service-b', 'delegate to child agent', 'dispatch to service'"
license: MIT
metadata:
  author: flow
  version: "0.2.0"
---

根 agent 为指定服务分配子 agent，支持内联执行或生成独立指令包。内联 agent 可调用 skill，必须验证目录，必须收到 report 才能标记完成。

执行 `/flow:assign <service-name>` 开始。