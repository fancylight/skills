---
name: flow-codex-receive
description: 将唯一一个已分配的 Flow spec 加载到服务执行 agent 上下文中。在已分配服务任务开始时、设计或编码前使用。
---

# Codex Flow 接收任务

读取 `../flow-codex-core/references/platform.md`。

## 输入

要求提供 `root_path`、`service_name`、`change_name` 和 `spec_id`。优先使用编排 agent 明确传入的
值；存在多个活跃需求时不要自行推断。

## 流程

1. 读取服务 `.flow/config.yaml`、根 `.flow/config.yaml`、根任务追踪、概要设计和已分配的 OpenSpec
   产物。
2. 只读取相关知识库材料和跨服务契约。
3. 确认当前执行 agent 只负责一个 spec，并检查期望分支。
4. 确认 OpenSpec apply 指令可用。
5. 向进度文件追加 `[RECEIVE] complete`，并概述已接收范围。

遇到产物缺失、分配歧义、分支不匹配或 OpenSpec 指令阻断时停止。
