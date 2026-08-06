---
name: flow-apply
description: "Child agent executes one assigned Flow spec — coding, review handshake, unit tests, commit. lease-v1 defers review/report to root; legacy keeps inline review. Use when: 'start coding', 'apply the specs', 'implement the design', 'begin coding phase', 'execute specs'"
license: MIT
metadata:
  author: flow
  version: "0.4.0"
---

子 agent 编码阶段。执行 `/flow:apply` 或 `/flow:apply spec-name`（正文：commands/flow/apply.md）。
