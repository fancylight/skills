---
name: "Flow: Apply"
description: "Child agent executes the coding phase — iterates over specs with inline review and unit test loops"
category: Workflow
tags: [workflow, orchestration, multi-agent, executor, coding]
version: "0.3.0"
---

子 agent 阶段二：执行单个 spec 的编码循环。编码委托给 spec_tool（如 opsx:apply），子 agent 自行唤起审核 agent、运行测试、提交代码。

**不更新 task.md**——那是 `/flow:report` 的职责。

**输入**：`/flow:apply <spec-name>`（必传，由 `/flow:receive` 确定后传入）

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: executor`
2. 读取 `spec_tool`、`inline_agents` 配置
3. 确认已执行 `/flow:receive`（spec 已确定，design.md 已就绪）

---

**步骤**

1. **验证 spec 就绪**

   检查 spec 目录下 `design.md` 存在。不存在则拒绝："spec {name} 尚未完成设计，请先执行 /flow:design"。

2. **编码实现**

   使用 `spec_tool`（如 `opsx:apply`）执行编码。spec_tool 自行读取 spec 文件（proposal.md、design.md、tasks.md）并生成代码。**不直接手写代码，也不手动转述 design.md 内容——委托给 spec_tool 完成。**

3. **内联审核 agent**

   使用 **Agent tool** 启动内联审核 agent。读取 `本命令文件所在目录下的 templates/review-agent-prompt.md` 模板，替换 `{design.md 绝对路径}` 和 `{本次变更的文件路径列表}` 后传入。

   **文档一致性核对**（审核发现不一致时）：
   - **代码错误**：代码偏离了设计意图 → 修复代码
   - **设计过时**：实现过程中发现 design.md 需要调整 → 更新 design.md
   - 如无法判断，列出差异让用户决定

   **重试机制**：驳回 → 修复 → 重新审核，最多 3 次。超限停止并输出失败报告。

4. **单元测试**

   执行 `inline_agents.unit_test.test_command`。失败 → 修复 → 重新测试，最多 3 次。超限停止并输出失败报告。

5. **提交代码**

   审核和测试均通过后提交：
   - 暂存本次 spec 修改/新增的代码文件
   - **同时暂存本 spec 目录下的 spec 文件**（proposal.md、design.md、tasks.md 等），它们属于本次 spec 的工作产物
   - 不用 `git add .`
   - commit message 格式：`{prefix}-{id} c{序号} {type}: {description}`
   - commit 记录由 `/flow:report` 统一写入 task.md（`完成：{date} commit {hash}`），不在 spec 目录维护 commits.md

6. **输出结果**

   ```
   ## 编码完成 — {spec-name}
   ✅ 通过 | 审核：{n}次 | 测试：{n}次 | commit：{hash}
   下一步：执行 /flow:report 提交汇报
   ```

   失败时输出失败原因，提示用户介入。

---

**约束**

- **不更新 task.md**（唯一写入者是 `/flow:report`）
- **不读取 task.md 找 spec**——spec 已由 `/flow:receive` 确定
- **不手动读取 design.md 并转述**——spec_tool 自行读取 spec 文件
- 审核和测试重试各最多 3 次，超限必须停止