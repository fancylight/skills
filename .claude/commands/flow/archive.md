---
name: "Flow: Archive"
description: "Root agent archives a completed requirement, appending end date to directory name"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.2.0"
---

归档已完成的大需求。检查完成条件，确认后移入归档目录并补充结束日期。

**输入**：`/flow:archive [change-name]`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认有活跃 change；未指定时 **AskUserQuestion** 选择

---

**步骤**

1. **检查完成条件**

   ```
   归档条件检查：

   - [ ] task.md 中所有服务的所有 spec 已完成（无 - [ ] 项）
   - [ ] 已执行 /flow:verify（接口契约已验证）
   - [ ] 已执行 /flow:test（集成测试已通过）
   - [ ] 知识库已审核（如 review_on_archive: true）
   ```

   如有未满足项，展示详情，**AskUserQuestion** 确认是否仍要归档（带警告继续 / 取消）。
   hotfix 类型（`type: hotfix`）跳过 verify 和 test 检查。

2. **知识库审核**（如 `review_on_archive: true`）

   扫描各服务 /flow:report 汇报中的【知识库更新】章节，列出所有知识库变更，请用户确认准确性。

3. **执行归档**

   1. 确定目标目录名：`{需求名}-{开始日期}-{YYYYMMDD结束日期}`
   2. 确保 `.flow/changes/archive/` 目录存在
   3. 将 `.flow/changes/{change-name}-{开始日期}/` 移动到 `archive/` 下
   4. 更新归档后 task.md 元数据：
      ```yaml
      status: archived
      updated: {YYYY-MM-DD}
      archived: {YYYY-MM-DD}
      ```

4. **输出归档摘要**

   ```
   ## 归档完成

   需求：{需求名称}
   归档位置：.flow/changes/archive/{change-name}-{开始日期}-{结束日期}/
   完成情况：{N}/{N} 服务，{M}/{M} spec
   契约验证：✅ 已验证 / ⚠️ 未验证
   集成测试：✅ 已通过 / ⚠️ 未执行
   ```

---

**约束**

- 归档是移动目录，不删除，保留完整历史
- 不强制阻止带警告的归档，但必须明确告知用户
- 目标归档目录已存在时报错并提示处理方式