---
name: flow-report
description: "Child agent submits a structured completion report after finishing coding, updates root task.md, and triggers knowledge base maintenance check. Use when: 'I finished coding, submit report', 'report my progress', 'complete this task and report'"
license: MIT
metadata:
  author: flow
  version: "0.2.0"
---

子 agent 完成编码后提交结构化汇报，更新根 task.md、开发文档（§3.2 回写）与发版记录，强制触发知识库维护判断。

执行 `/flow:report` 开始。