---
name: flow-apply
description: "Child agent executes the coding phase — iterates over specs with inline review and unit test loops. Use when: 'start coding', 'apply the specs', 'implement the design', 'begin coding phase', 'execute specs'"
license: MIT
metadata:
  author: flow
  version: "0.2.0"
---

子 agent 阶段二编码：编码委托给 spec_tool（如 opsx:apply），子 agent 自行唤起审核子 agent、运行测试、自提交代码。不更新 task.md（report 的职责）。

执行 `/flow:apply` 或 `/flow:apply spec-name` 开始。