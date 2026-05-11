---
name: flow-assign
description: "Root agent assigns work to a child agent — inline execution or instruction package. Use when: 'assign task to service-a', 'start coding for service-b', 'delegate to child agent', 'dispatch to service'"
license: MIT
metadata:
  author: flow
  version: "0.3.0"
---

根 agent 为指定服务派发任务给子 agent。根只负责生成提示词和派发，不编码不提交不更新 task.md。子 agent 入口是 `/flow:receive`。

两种模式：
- **独立指令包**：输出提示词，用户手动粘贴
- **内联执行**：Agent tool 启动一个子 agent

执行 `/flow:assign <service-name>` 开始。