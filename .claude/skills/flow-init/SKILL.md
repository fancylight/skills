---
name: flow-init
description: "Initialize flow scaffold for root or child agent. Use when setting up a new project orchestration structure (root mode) or adding a service into the flow system (child mode). Examples: 'initialize flow for this project', 'set up this service as a child agent', 'add this service to flow'"
license: MIT
metadata:
  author: flow
  version: "0.2.0"
---

初始化 `.flow/` 必要文件。根据 role 自动切换模式：根 agent 初始化项目结构，子 agent 初始化服务并向根注册。

执行 `/flow:init` 开始。