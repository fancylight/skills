---
name: flow-codex-test
description: 服务 specs 完成后，从根上下文协调 Flow 集成测试。用户要求测试已完成的多服务需求时使用。
---

# Codex Flow 测试

读取 `../flow-codex-core/references/platform.md`。要求 `flow-codex-verify` **全量（§A+§B）** 已成功。根据概要设计中的
验收标准和 `../flow-codex-core/assets/templates/integration-test.md.tmpl` 生成集成测试计划。需要时
将服务级测试执行委托给子 agents。将命令、结果和阻断项记录到需求集成测试文档。作为根编排 agent
时不要修改业务代码。
