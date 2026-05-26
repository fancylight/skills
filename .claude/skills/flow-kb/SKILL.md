---
name: flow-kb
description: "Knowledge base maintenance — both root and child agent can use. Reads KB rules, analyzes changes, writes to KB, commits if git repo. Use when: 'update knowledge base', 'maintain KB', 'document this change'"
license: MIT
metadata:
  author: flow
  version: "0.1.0"
---

知识库维护命令，根/子均可使用。读取维护指南和 change 上下文，分析需要记录的内容，经用户确认后写入 KB 并提交。

执行 `/flow:kb <change-name>` 开始。