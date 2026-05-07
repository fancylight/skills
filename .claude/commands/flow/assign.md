---
name: "Flow: Assign"
description: "Root agent assigns work to a child agent — inline execution or instruction package for independent session"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.2.0"
---

为指定服务分配子 agent，支持两种模式：内联执行或生成指令包。

**输入**：`/flow:assign <service-name>`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认指定的 service 在 services 列表中，且 `flow_initialized: true`
   - 若 `flow_initialized: false`，提示："该服务尚未初始化，子 agent 收到指令包后需先执行 /flow:init"
3. 确认有活跃 change；多个时 **AskUserQuestion** 选择
4. 使用 **AskUserQuestion** 选择分配模式：
   - **内联执行**：根 agent 直接启动内联编码 agent，自动完成所有 spec 的编码→审核→测试循环。适合小需求、单服务、spec 数量少的场景。无持久记忆，会话结束即消失。**注意：内联 agent 无法调用 skill（如 `opsx:apply`），只能通过原始工具（Read/Edit/Write）完成编码。**
   - **独立指令包**：生成指令包，用户手动在服务目录打开新 Claude Code 会话粘贴。适合大需求、多 spec、需要长期工作的场景。有持久记忆。**子 agent 拥有完整 skill 系统，可调用 `opsx:apply`、`/flow:apply` 等命令。**

---

**步骤**

1. **读取需求上下文**

   读取活跃 change 的：
   - `概要设计.md` — 整体方案和接口契约
   - `task.md` — 找到该服务的 spec 列表（含边界、依赖）

2. **分析依赖状态**

   从 task.md 中找到该服务的 `blocked by` 标记：
   - 依赖服务已完成（`[x]`）→ 读取其 api.md 作为接口契约参考
   - 依赖服务未完成 → 警告用户但不阻止分配

3. **确定任务号**（如配置了 `task_id_prefix`）

   从 task.md 已有的最大编号 +1，生成 `{prefix}-{id}`。

4. **执行分配**

   根据用户选择的模式执行：

   ---

   **模式 A：内联执行**

   **重要：根 agent 只收集路径信息，不读取 design.md 内容。所有内容由内联 agent 自行读取。**

   根 agent 收集以下信息（只读路径，不读内容）：
   - 服务名、服务绝对路径
   - 概要设计.md 绝对路径
   - 每个 spec 的 design.md 绝对路径
   - 测试命令（来自 config.yaml）
   - 跨服务上下文（依赖服务状态、已就绪接口契约）
   - spec 列表（从 task.md 提取，只读本服务章节的 spec 名称+边界+依赖）

   **严格要求：每个 spec 必须独立执行一轮 Agent tool 调用，绝对不能把多个 spec 打包给同一个 agent。**

   按 spec 依赖顺序，**逐个 spec** 执行以下 3 步。每步使用 **Agent tool** 启动独立内联 agent，根 agent 只负责编排流程，不执行任何服务目录操作。

   **对每个 spec，依次执行：**

   **Step 1 — 编码（调用 /flow:apply）**

   使用 Agent tool 启动编码 agent，**每次只传一个 spec**，prompt：
   ```
   你是 {service_name} 的编码 agent。工作目录：{服务绝对路径}

   任务：执行 /flow:apply {spec_name} 完成编码→审核→测试循环。

   输出：
   - 修改/新增的文件路径列表
   - 测试结果：✅ 通过 / ❌ 失败
   ```

   ✅ 通过 → 继续 Step 2。
   ❌ 失败 → 将错误信息传给新的编码 agent 重试，最多 3 次。

   **Step 2 — 提交代码**

   使用 Agent tool 启动提交 agent，**只为当前这一个 spec 提交**，prompt：
   ```
   你是提交 agent。工作目录：{服务绝对路径}

   1. 检查本次 spec 变更的文件：git status
   2. 新增的文件执行 git add {文件路径}（不要 git add .）
   3. 已修改的文件也会自动暂存
   4. 提交：git commit -m "{prefix}-{id} c{序号} {type}: {spec描述}"

   输出：commit hash 和提交的文件列表。
   ```

   **Step 3 — 更新 task.md**

   根 agent **自己执行**（不是 Agent tool），读取根 task.md，将当前 spec 勾选为 `[x]`，更新 `updated` 日期。
   这一步由根 agent 直接操作，因为 task.md 是根 agent 的职责范围。

   **循环下一个 spec**

   3 个 step 全部通过后，标记当前 todo 为 completed，下一个 spec 标记为 in_progress，重复 Step 1-3。

   **违规判断**：如果根 agent 发现自己在一个 Agent tool 调用中处理了多个 spec，说明它越界了，应立即停止并重新按单 spec 模式执行。

   ---

   待完成 spec 列表：
   {spec_list}

   跨服务上下文：
   {cross_service_context}

   ---

   **全部完成后**，根 agent 收到结果：
   - 全部 spec ✅ → 提示用户"编码完成，可执行 /flow:test 进行集成测试"
   - 有失败 spec → 列出失败原因，提示用户决定下一步
   - 有 spec 未设计（暂停）→ 提示用户在子目录独立会话中完成设计评审

   ---

   **模式 B：独立指令包**

   使用 `assign.md.tmpl` 模板渲染，模板文件：本命令文件所在目录下的 `templates/assign.md.tmpl`，用 Read 工具按绝对路径读取，注入以下变量：

   | 变量名 | 来源 | 说明 |
   |--------|------|------|
   | `service_name` | config.yaml | 目标服务名 |
   | `onboarding_path` | config.yaml | 根目录 onboarding.md 绝对路径 |
   | `change_name` | 活跃 change | 需求目录名 |
   | `task_id` | 步骤 3 生成 | 任务号（如配置了前缀） |
   | `spec_list` | task.md | 本服务未完成的 spec 列表（Markdown 格式） |
   | `overview_design_path` | 活跃 change | 概要设计.md 绝对路径 |
   | `knowledge_base_path` | config.yaml | 知识库路径（如启用） |
   | `cross_service_context` | 依赖分析 | 依赖服务状态、已就绪接口契约 |
   | `commit_format` | config.yaml | 提交格式 |

   渲染后的指令包示例：

   ```
   你好，我是 {{service_name}} 的子 agent。

   ## 启动指引
   请先阅读：
   1. {{onboarding_path}}（二级架构说明和开发规范）
   2. 确认本服务的 .flow/config.yaml 存在，否则先执行 /flow:init

   ## 当前任务
   需求：{{change_name}}
   {{#if task_id}}任务号：{{task_id}}{{/if}}

   ## 待完成 Spec
   {{spec_list}}

   ## 参考文档
   - 概要设计：{{overview_design_path}}
   {{#if knowledge_base_path}}
   - 知识库：{{knowledge_base_path}}
   {{/if}}

   ## 跨服务上下文
   {{cross_service_context}}

   ## 工作要求
   1. 执行 /flow:receive 接收任务（自动加载工作协议）
   2. 执行 /flow:design 完成 spec 设计并自检
   3. 设计评审通过后执行 /flow:apply 进入编码循环
   4. 所有 spec 完成后执行 /flow:report
   {{#if commit_format}}
   提交格式：{{commit_format}}
   {{/if}}

   注意：先做设计，等评审通过再编码。
   ```

   输出操作指引：
   ```
   📋 指令包已生成

   下一步操作：
   1. 打开新终端
   2. cd {服务绝对路径}
   3. 启动 Claude Code
   4. 粘贴以下指令包

   ---
   {指令包内容}
   ```

5. **更新 task.md**

   在对应服务章节追加：
   - 分配日期
   - 任务号（如有）
   - 分配模式（内联/独立）

---

**约束**

- 两种模式共享：路径必须是绝对路径，不阻止分配有依赖未完成的服务
- 独立模式：指令包不包含根 agent 内部实现细节，依赖状态必须注明
- **内联模式：根 agent 绝对不能读取 design.md 内容或自己编码，所有编码工作必须委托给 Agent tool 启动的内联 agent**
- 内联模式：根 agent 只负责收集路径、生成 prompt、启动 Agent tool、接收结果
- **内联模式：每个 spec 必须独立启动一个 Agent tool 调用，绝对不能把多个 spec 打包给同一个 agent。违反此规则会导致多个 spec 被合并成一个 commit，破坏提交粒度。**
- 内联模式：spec 数量 > 5 或涉及多服务时，建议用户选择独立模式
- 内联模式：spec 无 design.md 时，内联 agent 只做设计不编码（需用户评审后才能编码）
- 内联模式：会话结束即消失，不保证持久记忆