---
name: "Flow: Apply"
description: "Child agent executes the coding phase — iterates over specs with inline review and unit test loops"
category: Workflow
tags: [workflow, orchestration, multi-agent, executor, coding]
version: "0.2.0"
---

子 agent 阶段二：按 spec 依赖顺序执行编码循环。编码委托给 spec_tool（如 opsx:apply），子 agent 自行唤起审核子 agent、运行测试、提交代码。

**不更新 task.md**——那是 `/flow:report` 的职责。

**输入**：`/flow:apply [spec-name]`
- 无参数：遍历所有未完成且设计已通过的 spec
- 有参数：只执行指定 spec

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: executor`
2. 读取 `root_path`、`service_name`、`spec_tool`、`inline_agents` 配置
3. 确认已执行 `/flow:receive`（存在活跃 change）

---

**步骤**

1. **确定目标 spec 列表**

   读取根 task.md 中本服务章节，提取未完成 spec（`- [ ]`）。

   **无参数模式**：
   - 过滤条件：spec 有对应 `design.md` 文件
   - 按依赖排序（无依赖的先执行）
   - 无 design.md 的 spec 跳过，警告用户："spec {name} 尚未完成设计，请先执行 /flow:design"

   **有参数模式**：
   - 只取指定 spec
   - 检查该 spec 是否有 `design.md`，无则拒绝并提示

   无符合条件的 spec → 提示"所有 spec 已完成或无设计文档"，建议执行 `/flow:report`。

2. **使用 TaskCreate 创建 TodoList**

   为每个目标 spec 创建 todo 项。

3. **逐 spec 执行编码循环**

   按依赖顺序，对每个 spec 执行：

   **a. 读取设计文档**

   读取 spec 的 `design.md`，理解实现方案、涉及文件、边界约束。

   **b. 编码实现**

   使用 `opsx:apply`（或 config 中配置的 `spec_tool`）执行编码。不直接手写代码——委托给 spec_tool 完成。

   **c. 内联审核 agent**

   使用 **Agent tool** 启动内联审核 agent，传入以下 prompt：

   ```
   你是代码审核 agent。你的唯一职责是检查代码实现是否与设计文档一致。

   **输入文件**：
   - 设计文档：{design.md 绝对路径}
   - 变更代码文件列表：{本次变更的文件路径列表}

   **审核步骤**：
   1. 用 Read 工具读取 design.md，提取：
      - 定义的接口/功能列表
      - 数据结构定义
      - 明确标注的"不做什么"（边界约束）
   2. 用 Read 工具逐个读取变更代码文件
   3. 逐项检查：

      **功能覆盖**（逐接口/功能点核对）：
      - design.md 中定义的每个接口是否都有对应实现？
      - 接口签名（参数、返回值）是否与 design.md 一致？
      - 接口行为是否符合 design.md 描述？

      **数据结构一致性**：
      - 字段名、字段类型是否与 design.md 一致？
      - 是否有 design.md 中定义但代码中缺失的字段？
      - 是否有代码中存在但 design.md 中未定义的多余字段？

      **边界约束**：
      - 代码是否实现了 design.md 明确标注"不做什么"的功能？（scope creep）
      - 代码是否引入了 design.md 范围之外的额外依赖？

   **输出格式**（严格按此格式）：

   ## 审核结果：✅ 通过 / ❌ 驳回

   ### 功能覆盖
   - [✅/❌] {接口名}：{状态说明}

   ### 数据结构
   - [✅/❌] {结构名}：{状态说明}

   ### 边界约束
   - [✅/❌] {约束项}：{状态说明}

   ### 问题详情（仅驳回时）
   1. {文件}:{行号} — {问题描述} — {建议修复方式}

   **判定规则**：
   - 所有检查项 ✅ → 整体通过
   - 任何一项 ❌ → 整体驳回
   - 不评价代码风格、性能优劣，只检查与 design.md 的一致性
   ```

   **文档一致性核对**（审核发现不一致时）：

   当审核 agent 发现代码实现与 design.md 不一致时，需判断原因：
   - **代码错误**：代码偏离了设计意图 → 修复代码
   - **设计过时**：实现过程中发现 design.md 需要调整 → 更新 design.md

   判断标准：
   - 如果不一致是因为实现遇到了 design.md 未预见的技术约束 → 更新 design.md
   - 如果不一致是因为编码时疏忽或理解偏差 → 修复代码
   - 如无法判断，列出差异让用户决定

   **重试机制**：
   - ❌ 驳回 → 将驳回原因作为上下文，自动修复代码或更新 design.md → 重新审核
   - 最多重试 **3 次**
   - 超限 → 停止该 spec，输出失败报告，提示用户介入

   **d. 单元测试**

   执行 `inline_agents.unit_test.test_command`（来自 `.flow/config.yaml`）。

   **重试机制**：
   - 失败 → 将测试输出作为上下文，自动修复代码 → 重新测试
   - 最多重试 **3 次**
   - 超限 → 停止该 spec，输出失败报告，提示用户介入

   **e. 提交代码**

   审核和测试均通过后，提交本次变更：

   1. **暂存文件**：
      - 已跟踪的修改文件：`git add {文件路径}`
      - 本次任务新增的文件：`git add {新文件路径}`
      - 只 add 本次 spec 修改/新增的文件，不要 `git add .`
   2. **提交**：使用 `commit_format`（来自 `.flow/config.yaml`）
   3. **commit message 格式**：`{prefix}-{id} c{序号} {type}: {description}`
      - `c{序号}` 表示第几个 spec（c1, c2, c3...）
      - `{type}`：feat / fix / refactor / test / docs
   4. **记录 commit 追溯**：在 spec 工作目录写入（或追加）`commits.md`：
      ```markdown
      | Commit | 时间 | 说明 |
      |--------|------|------|
      | {commit_hash} | {YYYY-MM-DD HH:MM} | {commit_message} |
      ```
      如果 opsx:apply 在一次 spec 中产生了多次提交，依次追加。此文件供 `/flow:report` 读取，是汇报中 commit 信息的权威来源。

4. **全部完成**

   所有 spec 执行完毕后，输出摘要：

   ```
   ## 编码完成

   服务：{service_name}

   ### 执行结果
   - spec1: ✅ 通过（审核 1 次，测试 1 次）
   - spec2: ✅ 通过（审核 2 次，测试 1 次）
   - spec3: ❌ 失败（审核超限，需用户介入）

   ### 下一步
   所有 spec 已完成 → 执行 /flow:report 提交汇报
   有失败 spec → 修复后重新执行 /flow:apply {失败spec名}
   ```

   提示："编码阶段完成。请执行 `/flow:report` 提交汇报（report 会更新 task.md）。"

---

**约束**

- 只处理有 `design.md` 的 spec，无设计文档的必须先走 `/flow:design`
- **编码委托给 spec_tool**（如 opsx:apply），不直接手写代码
- 每个 spec 的审核和测试重试各最多 3 次，超限必须停下来
- 审核只检查代码与 design.md 的一致性，不评价方案优劣
- **不更新 task.md**（task.md 的唯一写入者是 `/flow:report`）
- 不修改其他服务的 task.md 条目
- 不跳过审核或测试步骤