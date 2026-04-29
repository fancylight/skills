---
name: "Flow: Hotfix"
description: "Child agent lightweight bug fix workflow — skips design phase, goes straight to coding"
category: Workflow
tags: [workflow, orchestration, multi-agent, executor, hotfix]
version: "0.1.0"
---

子 agent 轻量级 bug 修复工作流。跳过设计阶段，直接进入编码。

**输入**：`/flow:hotfix "bug 描述"`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: executor`
2. 如配置不存在，提示先执行 `/flow:init`

---

**步骤**

1. **创建 hotfix change**

   在 spec 工作区创建简化 change 目录：
   ```
   {spec工作区}/changes/hotfix-{YYYYMMDD}-{slug}/
   ├── fix.md      ← bug 描述、复现步骤、根因分析、修复方案
   └── tasks.md    ← 极简任务列表
   ```

   **fix.md** 结构：
   ```markdown
   ---
   type: hotfix
   status: in_progress
   service: {service_name}
   created: {YYYY-MM-DD}
   updated: {YYYY-MM-DD}
   ---

   ## Bug 描述
   {用户输入的描述}

   ## 复现步骤
   {待填写}

   ## 根因分析
   {待填写}

   ## 修复方案
   {待填写}
   ```

   **tasks.md**：
   ```markdown
   ---
   requirement: hotfix: {bug 描述}
   type: hotfix
   status: in_progress
   created: {YYYY-MM-DD}
   ---

   ## {service_name}
   - [ ] 定位根因
   - [ ] 实现修复
   - [ ] 验证修复
   ```

2. **使用 TaskCreate 创建 TodoList**

   - [ ] 定位根因，补充 fix.md
   - [ ] 实现修复代码
   - [ ] 内联审核 agent
   - [ ] 单元测试
   - [ ] flow:report

3. **进入简化编码循环**（跳过阶段一设计）

   a. 定位根因，补充 `fix.md` 的复现步骤和根因分析
   b. 实现修复代码
   c. 内联启动审核 agent（同正常流程，审核标准：fix.md 的修复方案）
      - 通过 → 继续
      - 驳回 → 修改 → 重新审核
   d. 执行单元测试（`inline_agents.unit_test.test_command`）
      - 通过 → 继续
      - 失败 → 修复 → 重新测试

4. **执行 `/flow:report`**

   知识库维护：hotfix 只记录"坑点/根因"类型，不记录其他。
   report 完成后自动将 fix.md 状态更新为 `completed`。

---

**约束**

- 跳过阶段一（spec 设计 + 用户评审），直接编码
- 不需要 `/flow:verify`，hotfix 归档时跳过契约验证
- 知识库只记录坑点类型（根因、复现条件、修复思路），不记录接口变更等
- slug 由 bug 描述生成（kebab-case，取前 3-4 个词）