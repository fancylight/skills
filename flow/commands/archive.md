---
name: "Flow: Archive"
description: "Archive a completed requirement"
category: Workflow
tags: [workflow, orchestration, multi-agent]
---

归档已完成的需求。检查完成条件，确认后移入归档目录。

**输入**：`/flow:archive [change-name]`

- `change-name`：可选，指定归档哪个需求。不提供则提示选择。

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认有活跃的 change

如未指定 change-name，使用 **AskUserQuestion** 让用户选择要归档的需求。

---

**步骤**

1. **检查完成条件**

   读取 `tasks.md`，检查：

   ```
   归档条件检查：

   - [ ] 所有服务的任务已完成（tasks.md 中无 `- [ ]` 项）
   - [ ] 跨服务契约已验证（建议先执行 /flow:verify）
   - [ ] 知识库已审核（如启用）
   ```

   逐项检查并报告结果。

2. **处理未满足条件**

   如有未完成项，展示详情：

   ```
   ⚠️ 归档条件未完全满足：

   未完成任务（2 项）：
   - [ ] register-service: 权限校验接口
   - [ ] admin: 强制升级接口

   未验证契约：
   - 建议先执行 /flow:verify

   是否仍要归档？（未完成项将标注在归档记录中）
   ```

   使用 **AskUserQuestion** 确认：
   - 继续归档（带警告）
   - 取消，先完成剩余工作

3. **知识库审核**（如启用）

   如 `knowledge_base.review_on_archive: true`：
   - 扫描各服务的汇报中【知识库更新】章节
   - 列出所有知识库变更
   - 请用户确认是否准确

   ```
   知识库变更审核：

   | 服务 | 文档 | 操作 | 说明 |
   |------|------|------|------|
   | {service} | {path} | 新增 | {说明} |
   | {service} | {path} | 更新 | {说明} |

   以上变更是否准确？
   ```

4. **执行归档**

   ```bash
   mkdir -p .flow/changes/archive
   mv .flow/changes/{change-name} .flow/changes/archive/{change-name}
   ```

   更新归档后的 `tasks.md` 元数据：
   ```yaml
   status: completed
   updated: {当前日期}
   archived: {当前日期}
   ```

5. **输出归档摘要**

   ```
   ## 归档完成

   需求：{需求名称}
   归档位置：.flow/changes/archive/{change-name}/
   状态：已完成

   ### 完成情况
   - 服务：{N}/{N} 完成
   - 契约验证：✅ 已验证 / ⚠️ 未验证
   - 知识库：✅ 已审核 / ⚠️ 未审核

   ### 警告（如有）
   - {未完成项}
   ```

---

**约束**

- 归档前必须展示完成条件检查结果
- 不强制阻止带警告的归档，但必须明确告知用户
- 归档是移动目录，不是删除
- 归档后 tasks.md 保留完整历史（已勾选的 [x] 不删除）
- 如目标归档目录已存在，报错并建议处理方式