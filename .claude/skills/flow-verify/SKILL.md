---
name: flow-verify
description: "Root agent verifies cross-service API contract consistency between providers and consumers. Use when: 'verify API contracts', 'check interface consistency', 'do the services agree on the API'"
license: MIT
metadata:
  author: flow
  version: "0.1.0"
---

根 agent 验证跨服务接口契约一致性，比对消费者期望（{provider}-api.md）vs 提供者实现（api.md）。

执行 `/flow:verify` 开始。