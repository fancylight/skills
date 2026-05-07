---
name: "Flow: Verify"
description: "Root agent verifies cross-service API contract consistency between providers and consumers"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.1.0"
---

验证跨服务接口契约的一致性：消费者期望 vs 提供者实现。

**输入**：`/flow:verify [change-name]`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认有活跃的 change；多个时 **AskUserQuestion** 让用户选择

---

**步骤**

1. **读取需求上下文**

   读取活跃 change 的 `task.md` 和 `概要设计.md`：
   - 识别涉及的服务及依赖关系（谁调用谁）

2. **扫描接口文档**

   对每个涉及的服务，扫描其 spec 工作区：

   - **提供者侧**：`api.md` — 该服务对外暴露的接口
   - **消费者侧**：`{provider-name}-api.md` — 消费者期望上游提供的接口

3. **交叉比对**

   对每对消费者-提供者关系，比对：
   - 接口路径、HTTP 方法
   - 请求参数（名称、类型、是否必填）
   - 返回字段（名称、类型、结构）
   - 异常处理约定

   分类结果：
   - ✅ 一致：完全匹配
   - ⚠️ 差异：不一致但可能兼容（如多了可选字段）
   - ❌ 冲突：不兼容（类型不同、必填字段缺失）

4. **输出验证报告**

   ```
   ## 契约验证：{需求名称}

   ✅ {consumer} → {provider} GET /api/v1/users — 一致
   ⚠️ {consumer} → {provider} POST /api/v1/login — 提供者多了可选字段 extra_field
   ❌ {consumer} → {provider} GET /api/v1/perms — 冲突：
      消费者期望 returnType: Boolean，提供者实际 returnType: PermissionResult

   ### 未验证（缺少文档）
   - {service}: 未生成 api.md

   ### 建议
   - ❌ 冲突项需协调，通知相关子 agent 调整
   - 未验证项建议补充接口文档后再归档
   ```

5. **用户确认冲突处理方式**

   如有 ❌ 冲突，AskUserQuestion：通知提供者修改 / 通知消费者适配 / 标记为已知差异

---

**约束**

- **根 agent 不亲自执行验证逻辑**：验证工作委托给 Agent tool 启动的内联 agent，根 agent 只负责收集 api.md 路径和启动 Agent tool
- 只读操作，不修改任何文件
- 比对基于文档内容，不执行实际 API 调用
- 接口文档按优先级查找：活跃 spec change 目录 → 归档 change 目录 → 服务根目录