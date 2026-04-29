---
name: flow-test
description: "Root agent triggers integration tests after all services complete — HTTP calls, MQ messages, and direct DB verification based on acceptance criteria in overview design. Use when: 'run integration tests', 'test the full flow', 'verify the requirement end-to-end'"
license: MIT
metadata:
  author: flow
  version: "0.1.0"
---

根 agent 触发集成测试，基于概要设计的验收标准，内联测试 agent 执行 HTTP/MQ/DB 验证。

执行 `/flow:test` 开始。