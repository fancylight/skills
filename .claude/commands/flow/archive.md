---
name: "Flow: Archive"
description: "Root agent archives a completed requirement, appending end date to directory name"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.3.0"
---

归档已完成的大需求。校验分支、归档子服务 spec、终稿发版记录，最后归档根目录。

**输入**：`/flow:archive [change-name]`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认有活跃 change；未指定时 **AskUserQuestion** 选择

---

**步骤**

0. **发布就绪检查（只读）**

   读取 `~/.claude/commands/flow/templates/verify-checklist.md`，对本 change 执行发布所需 §A+§B+§F（流程/产物、发布就绪、SQL 数据访问门禁）。**不**在此步骤做跨服务 API 契约比对（契约由步骤 2 的 `/flow:verify` 覆盖）。

   存在 **ERROR** 时停止归档并列出项；SQL §F ERROR 不允许 waive。其它 **WARN** 时 AskUserQuestion 确认是否继续。

1. **分支校验与一致性检查**

   从 task.md 元数据头读取 `services` 数组。对每个服务：

   a. **确认仓库存在**：检查 `services[].repo` 对应的目录是否存在（相对于根目录的兄弟目录或 `config.yaml` 中配置的 path）
   b. **切换分支**：进入服务目录，检查当前分支是否与 `services[].branch` 一致。不一致则 `git checkout` 到目标分支
   c. **检查 spec 一致性**：读取服务内 `{spec_tool}/changes/` 下的活跃 spec 目录，与 task.md 中该服务的 spec 列表对比：
      - task.md 中 `[x]` 的 spec 在活跃目录中是否已不存在（被归档）或存在但已完成
      - task.md 中 `[ ]` 的 spec 是否存在且尚未归档
      - 如发现不一致，**AskUserQuestion** 让用户确认处理方式（跳过/手动修复后重试）
   d. **维护 task.md**：如发现 spec 状态漂移（长周期开发常见），更新 task.md 以反映实际状态

2. **检查完成条件**

   ```
   归档条件检查：

   - [ ] task.md 中所有服务的所有 spec 已完成（无 - [ ] 项）
   - [ ] 已执行发布就绪检查（verify-checklist §A+§B+§F 无 ERROR；SQL EXPLAIN evidence 完整）
   - [ ] 已执行 /flow:verify（跨服务接口契约已验证）
   - [ ] 已执行 /flow:test（集成测试已通过）
   - [ ] 知识库已审核（如 review_on_archive: true）
   ```

   如有未满足项，展示详情，**AskUserQuestion** 确认是否仍要归档（带警告继续 / 取消）。
   hotfix 类型（`type: hotfix`）跳过 verify 和 test 检查。

3. **子服务归档**

   对 task.md `services` 数组中的每个服务：

   a. 进入服务目录，确认当前分支为 `services[].branch`
   b. 执行 `{spec_tool}:archive`（参照 `child_agent.spec_tool` 配置的 spec 工具，如 `opsx:archive`），将活跃 spec 归档到 `{spec_tool}/changes/archive/{需求名}-{开始日期}-{结束日期}/` 下
      - 如 spec_tool 的 archive 不支持父目录参数，则先归档到 `archive/` 再手动 `mkdir` 父目录并 `mv` 进去
   c. `git add 归档目录` + `git commit -m "归档: {需求名} — {service_name}"`

   约束：子服务归档产生的 commit 只包含 spec 文件移动，不含代码变更。

4. **发版记录终稿**

   读取 `.flow/changes/{change-name}/发版记录.md`：

   - 对表格中每个服务，检查对应分支是否已合并到 main：
     ```
     git log main | grep <commit-hash>  # 或 git branch -r --merged main | grep <branch>
     ```
   - 已合并 → 表格 `main 已合并` 列填 `✅`，未合并 → 保持 `⬜`
   - 如有未合并的分支，在摘要中提醒用户

5. **知识库审核**（如 `review_on_archive: true`）

   扫描各服务 /flow:report 汇报中的【知识库更新】章节，列出所有知识库变更，请用户确认准确性。

6. **执行归档**

   1. 确定目标目录名：`{需求名}-{开始日期}-{YYYYMMDD结束日期}`
   2. 确保 `.flow/changes/archive/` 目录存在
   3. 将 `.flow/changes/{change-name}-{开始日期}/` 移动到 `archive/` 下
   4. 更新归档后 task.md 元数据：
      ```yaml
      status: archived
      updated: {YYYY-MM-DD}
      archived: {YYYY-MM-DD}
      ```

7. **输出归档摘要**

   ```
   ## 归档完成

   需求：{需求名称}
   归档位置：.flow/changes/archive/{change-name}-{开始日期}-{结束日期}/
   完成情况：{N}/{N} 服务，{M}/{M} spec
   契约验证：✅ 已验证 / ⚠️ 未验证
   集成测试：✅ 已通过 / ⚠️ 未执行
   分支合并：✅ 全部已合并 / ⚠️ {N} 个分支未合并
   ```

---

**约束**

- 归档是移动目录，不删除，保留完整历史
- 不强制阻止带警告的归档，但必须明确告知用户
- 目标归档目录已存在时报错并提示处理方式
- 子服务归档必须由根 agent 在对应服务分支上执行，不可跨分支操作
