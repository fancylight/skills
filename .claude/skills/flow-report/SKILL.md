---
name: flow-report
description: "Child agent submits a structured completion report after finishing coding, updates root task.md, and triggers knowledge base maintenance check. Use when: 'I finished coding, submit report', 'report my progress', 'complete this task and report'"
license: MIT
metadata:
  author: flow
  version: "0.3.0"
---

子 agent 完成编码后提交结构化汇报，更新根 task.md、开发文档（§3.2 + §4.1/§4.2/§4.3 回写）与发版记录，强制触发知识库维护判断。

开发文档回写须读 `commands/flow/templates/dev-doc-update-rules.md`：§4.1 可部署服务（非仓名）、§4.2 SQL 自包含、§4.3 业务验收语义。

执行 `/flow:report` 开始。