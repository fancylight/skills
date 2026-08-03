---
name: flow-codex-core
description: Codex Flow 适配层的内部公共资源和平台规则。仅在其他 flow-codex skill 引用时读取，不作为面向用户的流程入口。
---

# Flow Codex 公共资源

这是 Codex 适配层的公共资源库。

## 必读引用

- 执行任何公开 `flow-codex-*` skill 前，读取 `references/platform.md`。
- 派发、编码、审核或汇报时，读取 `references/checkpoints.md`。
- 执行任一集成测试 skill 或持续 Goal 时，读取 `references/test-controller.md`。
- 从 `assets/templates/` 加载模板。所有路径均相对于当前 skill 目录。

## 平台规则

不要调用 Claude 专属命令语法，也不要依赖用户主目录下的命令目录。公开 skills 使用自身说明和
当前同级 core skill。
