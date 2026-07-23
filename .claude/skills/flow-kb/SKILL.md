---
name: flow-kb
description: "Knowledge base maintenance — change or feedback entry. Use when: 'update knowledge base', 'maintain KB', 'document feedback investigation'"
license: MIT
metadata:
  author: flow
  version: "0.2.0"
---

知识库维护，根/子均可使用。双入口：

- `/flow:kb <change-name>` — change 上下文
- `/flow:kb feedback/{feedback-id}` — 反馈调查报告

写入前经用户确认。feedback 规则见 commands/flow/templates/feedback-kb-rules.md。
