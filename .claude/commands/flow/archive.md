---
name: "Flow: Archive"
description: "Root agent archives a completed requirement after release verify (§A+§B+§F) and integration result PASS"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.4.0"
---

归档已完成的大需求。校验分支、归档子服务 spec、终稿发版记录，最后归档根目录。

**输入**：`/flow:archive [change-name]`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认有活跃 change；未指定时 **AskUserQuestion** 选择

---

**步骤**

0. **发布 verify 门禁（只读）**

   执行 `/flow:verify verify_mode=release`（§A+§B+§F）。存在 **ERROR** 时停止归档；§F SQL ERROR 不允许 waive。其它 **WARN** 时 AskUserQuestion 确认。

1. **分支校验与一致性检查**

   从 task.md 元数据头读取 `services` 数组。对每个服务：
   a. 确认仓库存在
   b. 当前分支与 `services[].branch` 一致；不一致则停止并提示（不要静默 checkout 除非用户确认）
   c. 检查 spec 与 task.md 一致性；漂移时 AskUserQuestion
   d. 必要时维护 task.md 反映实际状态

2. **检查完成条件**

   ```
   - [ ] task.md 所有 spec 已完成
   - [ ] release verify（§A+§B+§F）无 ERROR
   - [ ] 集成测试：最近一次 [TEST_VERIFY_RESULT] PASS 且 verify_mode: result，且根 集成测试.md 一致（用户明示跳过仅限不需要集成测试的 change；standalone runner PASS 不能替代）
   - [ ] 集成测试 authorization ceiling ≥ result（若走过 test 链）
   - [ ] 发版记录完整
   - [ ] 知识库已审核（如 review_on_archive: true）
   - [ ] 概要设计 kb_action: 待沉淀 时 WARN 是否先 /flow:kb
   ```

   未满足时展示详情，AskUserQuestion（带警告继续 / 取消）。hotfix 类型可跳过集成测试检查（用户确认）。

3. **子服务归档**

   对每个服务执行 `{spec_tool}:archive`，commit 仅含 spec 移动。

4. **发版记录终稿**

   检查分支是否已合并 main；更新表格「main 已合并」列。

5. **知识库审核**（如 `review_on_archive: true`）

   提示或执行 `/flow:kb` 相关沉淀。

6. **根归档**

   将 `.flow/changes/{change}` 移至 `.flow/changes/archive/{change}-{endDate}/`，更新索引/状态。

---

**约束**

- release verify ERROR 阻断
- 不静默 checkout 脏 worktree
- 不得以 standalone system-test PASS 代替 result verify
