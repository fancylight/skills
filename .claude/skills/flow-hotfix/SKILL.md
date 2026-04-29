---
name: flow-hotfix
description: "Child agent lightweight bug fix workflow that skips design phase and goes straight to coding with inline review and unit tests. Use when: 'fix this bug', 'hotfix for the login issue', 'quick fix needed', 'patch this problem'"
license: MIT
metadata:
  author: flow
  version: "0.1.0"
---

子 agent 轻量级 bug 修复，跳过设计阶段，直接编码 → 内联审核 → 单元测试 → report。

执行 `/flow:hotfix "bug 描述"` 开始。