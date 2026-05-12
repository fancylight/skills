---
name: "Flow: Test"
description: "Root agent triggers integration tests — service-level (delegate to service dir) or cross-service acceptance (HTTP/MQ/DB)"
category: Workflow
tags: [workflow, orchestration, multi-agent, testing]
version: "0.2.0"
---

根 agent 触发集成测试。支持两种模式。

**输入**：`/flow:test [service-name|change-name]`
- 指定 service-name（如 `glm-attendance`）：运行该服务的集成测试（委托 agent 执行 `test_command`）
- 指定 change-name 或不指定：端到端跨服务验收测试（基于概要设计验收标准）

**与 apply.md 的分工**：
- 每个 spec 的单元测试：由 `/flow:apply` 在编码循环中执行（`test_command`）
- 服务的集成测试（如 c10 集成测试 spec）：由 `/flow:test <service>` 触发
- 跨服务端到端验收：由 `/flow:test <change>` 触发

---

## 模式 A：服务集成测试（`/flow:test <service-name>`）

**职责**：委托内联 agent 到服务目录运行 `test_command`，收集结果。根 agent 不亲自执行测试命令。

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认指定的 service 在 services 列表中

**步骤**

1. **读取服务配置**

   从 config.yaml 获取服务的 `path`。读取服务的 `.flow/config.yaml`，获取 `inline_agents.unit_test.test_command`。

2. **内联启动测试 agent**

   使用 **Agent tool** 启动内联 agent。读取 `flow/templates/test-agent-prompt.md` 模板，替换 `{服务绝对路径}` 和 `{test_command}` 后传入。

3. **输出结果**

   将 agent 返回的测试结果展示给用户。

---

## 模式 B：跨服务验收测试（`/flow:test [change-name]`）

**职责**：端到端验证大需求的验收标准（HTTP 调用 / MQ 消息 / DB 直查）。

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认有活跃 change（多个则 AskUserQuestion 选择）

**步骤**

1. **检查完成条件**

   读取 task.md，确认所有服务的所有 spec 已完成（全部 `[x]`）。
   如有未完成项，展示清单并警告，使用 **AskUserQuestion** 确认是否继续。

2. **读取验收标准**

   读取活跃 change 的 `概要设计.md`，提取 `## 验收标准` 章节。
   如验收标准章节不存在或过于笼统，警告用户并建议补充后再测试。

3. **确认测试环境**

   使用 **AskUserQuestion** 逐项确认：
   - 各服务是否已在本地启动？（列出 services 清单，逐个确认地址）
   - 数据库连接（host:port/database）
   - MQ 连接（如概要设计中涉及 MQ）

4. **内联启动集成测试 agent**

   使用 **Agent tool** 启动内联测试 agent，传入：
   - 验收标准内容
   - 环境配置（服务地址、DB、MQ）
   - 概要设计.md 路径

   测试 agent 执行：

   a. **HTTP 接口验证**：对每个接口发请求，验证状态码和响应
   b. **MQ 消息验证**：发送消息，通过 HTTP 或 DB 验证结果
   c. **数据库直查验证**：执行 SELECT 查询，验证数据一致性

5. **输出测试报告**

   ```
   ## 集成测试报告

   需求：{需求名}
   测试时间：{datetime}

   ### 测试结果
   ✅ 用例1：{描述} — 通过
   ❌ 用例2：{描述} — 失败
      实际：{actual} | 期望：{expected}

   ### 汇总
   通过：X / 失败：Y / 共 Z
   ```

6. **建议下一步**

   - 全部通过 → "建议执行 `/flow:verify` + `/flow:archive`"
   - 有失败 → "以下服务需要修复：{列表}。建议重新 `/flow:assign <service>`"

---

**约束**

- 根 agent 不亲自执行测试命令，所有测试工作委托给内联 agent
- 模式 B：只在所有 spec 完成后执行；DB 直查使用只读连接