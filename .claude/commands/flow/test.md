---
name: "Flow: Test"
description: "Root agent triggers integration tests after all services complete — HTTP calls, MQ, and direct DB verification"
category: Workflow
tags: [workflow, orchestration, multi-agent, testing]
version: "0.1.0"
---

根 agent 在大需求所有服务完成后触发集成测试。

**输入**：`/flow:test [change-name]`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认有活跃 change（多个则 AskUserQuestion 选择）

---

**步骤**

1. **检查完成条件**

   读取 task.md，确认所有服务的所有 spec 已完成（全部 `[x]`）。
   如有未完成项，展示清单并警告，使用 **AskUserQuestion** 确认是否继续测试。

2. **读取验收标准**

   读取活跃 change 的 `概要设计.md`，提取 `## 验收标准` 章节内容。
   如验收标准章节不存在或内容过于笼统，警告用户并建议补充后再测试。

3. **确认测试环境**

   使用 **AskUserQuestion** 逐项确认：
   - 各服务是否已在本地启动？（列出 services 清单，逐个确认地址）
   - 数据库连接（host:port/database）
   - MQ 连接（如概要设计中涉及 MQ）

4. **内联启动集成测试 agent**

   使用 **Agent tool** 启动内联测试 agent，传入：
   - 验收标准内容
   - 环境配置（服务地址、DB、MQ）
   - 概要设计.md 路径（完整背景）

   测试 agent 使用 `integration-test.md.tmpl` 模板生成测试用例，注入以下变量：

   | 变量名 | 来源 | 说明 |
   |--------|------|------|
   | `requirement_name` | change | 需求标题 |
   | `generated_at` | 当前时间 | 生成时间 |
   | `services` | 步骤 3 | 服务地址列表（name, url） |
   | `db_connection` | 步骤 3 | 数据库连接信息 |
   | `mq_connection` | 步骤 3 | MQ 连接信息（如涉及） |
   | `test_case_*` | 验收标准 | 从验收标准推导的用例 |

   测试 agent 执行：

   a. **HTTP 接口验证**
      ```
      请求：{METHOD} {url} {body}
      期望状态码：{code}
      期望响应包含：{字段}
      ```

   b. **MQ 消息验证**
      ```
      发送消息至 topic：{topic}
      消息内容：{payload}
      通过 HTTP 或 DB 验证结果
      ```

   c. **数据库直查验证**
      ```
      执行查询：{SQL}
      期望结果：{条件}
      ```

5. **输出测试报告**

   ```
   ## 集成测试报告

   需求：{需求名}
   测试时间：{datetime}

   ### 测试结果

   ✅ 用例1：{描述} — 通过
   ❌ 用例2：{描述} — 失败
      实际响应：{实际值}
      期望：{期望值}
      涉及服务：{service}

   ### 汇总
   通过：X / 失败：Y / 共 Z 个用例
   ```

6. **根据结果建议下一步**

   - 全部通过 → "建议执行 `/flow:verify` 验证接口契约，再执行 `/flow:archive` 归档"
   - 有失败 → "以下服务需要修复：{列表}。建议重新执行 `/flow:assign <service>`"

---

**约束**

- 只读取概要设计中的验收标准，不自行发散测试范围
- 测试 agent 在本地环境执行，不发布到任何远程环境
- DB 直查使用只读连接（SELECT），不执行写操作
- 测试失败不自动修改任何文件，由用户决定后续动作