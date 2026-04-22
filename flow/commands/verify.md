---
name: "Flow: Verify"
description: "Verify cross-service API contract consistency"
category: Workflow
tags: [workflow, orchestration, multi-agent]
---

验证跨服务接口契约的一致性：消费者期望 vs 提供者实现。

**输入**：`/flow:verify [change-name]`

- `change-name`：可选，指定验证哪个需求。不提供则验证当前活跃需求。

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认有活跃的 change

如有多个活跃 change 且未指定名称，使用 **AskUserQuestion** 让用户选择。

---

**步骤**

1. **读取需求上下文**

   读取活跃 change 的 `tasks.md` 和 `proposal.md`：
   - 识别涉及的服务
   - 识别服务间的依赖关系（谁调用谁）

2. **扫描接口文档**

   对每个涉及的服务，扫描其 spec 工作区（如 `openspec/changes/`）：

   **提供者侧**（被调用方）：
   - 查找 `api.md` — 该服务对外暴露的接口

   **消费者侧**（调用方）：
   - 查找 `{service-name}-api.md` — 消费者期望上游提供的接口

3. **交叉比对**

   对每对消费者-提供者关系：

   a. 读取消费者的 `{provider}-api.md`（期望）
   b. 读取提供者的 `api.md`（实际）
   c. 比对：
      - 接口路径是否一致
      - HTTP 方法是否一致
      - 请求参数（名称、类型、是否必填）
      - 返回字段（名称、类型、结构）
      - 异常处理约定

   分类结果：
   - ✅ 一致：完全匹配
   - ⚠️ 差异：有不一致但可能兼容（如多了可选字段）
   - ❌ 冲突：不兼容的差异（类型不同、必填字段缺失）

4. **输出验证报告**

   ```
   ## 契约验证：{需求名称}

   ### 验证结果

   ✅ {consumer} → {provider} GET /xxx/yyy
      消费者期望 vs 实际实现：一致

   ⚠️ {consumer} → {provider} POST /xxx/zzz
      差异：提供者返回多了 `extraField`（可选字段，兼容）

   ❌ {consumer} → {provider} GET /xxx/aaa
      冲突：
      - 消费者期望 returnType: Boolean
      - 提供者实际 returnType: PermissionResult
      → 需要协调

   ### 未验证（缺少文档）
   - {consumer} → {provider}: 消费者未生成 {provider}-api.md
   - {provider}: 未生成 api.md

   ### 建议
   - ❌ 冲突项需要协调，通知相关子 agent 调整
   - ⚠️ 差异项建议确认是否影响消费者
   - 未验证项建议补充接口文档
   ```

5. **用户确认**

   如有冲突，询问用户如何处理：
   - 通知提供者修改
   - 通知消费者适配
   - 标记为已知差异，暂不处理

---

**约束**

- 只读操作，不修改任何文件
- 比对基于文档内容，不执行实际 API 调用
- 如某服务的接口文档不存在，标注为"未验证"而非报错
- 验证结果不自动写入 tasks.md，由用户决定后续动作
- 接口文档的位置不硬编码，按以下优先级查找：
  1. 服务的活跃 spec change 目录
  2. 服务的归档 spec change 目录
  3. 服务根目录