---
name: flow-report
description: "Child agent submits structured completion report under report lease (lease-v1) or legacy direct path; updates root task.md and KB hints. Use when: report complete, finish spec, update task.md"
license: MIT
metadata:
  author: flow
  version: "0.4.0"
---

子 agent 汇报。执行 `/flow:report`（正文：commands/flow/report.md）。lease-v1 须先有 REPORT_LEASE_GRANTED。
