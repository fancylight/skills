---
name: flow-assign
description: "Root agent generates an instruction package for a child agent to start work. Use when: 'assign task to service-a', 'generate instructions for the worker service', 'dispatch child agent for login feature'"
license: MIT
metadata:
  author: flow
  version: "0.2.0"
---

根 agent 为指定服务生成子 agent 指令包（含 spec 列表、概要设计路径、工作阶段说明）。

执行 `/flow:assign <service-name>` 开始。