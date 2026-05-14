---
name: "Flow: Hotfix"
description: "Root agent creates hotfix entry in task.md and child service spec directory, then guides to assign for dispatching"
category: Workflow
tags: [workflow, orchestration, multi-agent, hotfix]
version: "0.2.0"
---

根 agent 为 bug 修复创建 hotfix 条目和 spec 目录，然后走 assign→receive→apply 通道派发编码。

**输入**：`/flow:hotfix <service-name> "bug 描述"`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认指定的 service 在 services 列表中
3. 确认有活跃 change；多个时 **AskUserQuestion** 选择

---

**步骤**

1. **收集信息**

   使用 **AskUserQuestion** 收集：
   - bug 简述（如命令参数已提供则跳过）
   - 影响的服务（如命令参数已提供则跳过）

2. **在根 task.md 写入 hotfix 条目**

   读取 `~/.claude/commands/flow/templates/task-md-maintenance.md`，按第 3.6 节格式，在对应服务章节的 `### Hotfix` 子章节下追加条目：

   ```
   - [ ] hotfix-{YYYYMMDD}-{slug}: {问题简述}
         问题：{1行描述}
         修复：{待编码}
   ```

   如该服务尚无 `### Hotfix` 子章节，先创建。

3. **在子服务创建 hotfix spec 目录**

   从 `.flow/config.yaml` 读取 `child_agent.spec_tool` 和服务 `path`。

   获取目标服务的绝对路径，使用对应的 spec skills（如 `opsx:propose`）在 **`{服务绝对路径}/openspec/changes/`**（opsx 工具链约定路径）下创建标准 spec 目录 `hotfix-{YYYYMMDD}-{slug}/`，内含 proposal.md、design.md 等标准文件。

   **不手动创建 spec 文件**——spec 文档的创建和维护由 spec skills 负责。

4. **引导派发**

   输出：
   ```
   Hotfix 条目已写入 task.md，spec 目录已创建。
   下一步：执行 /flow:assign <service-name> 派发 hotfix 给子 agent。
   ```

---

**约束**

- task.md 维护规则详见 `~/.claude/commands/flow/templates/task-md-maintenance.md`
- **子 agent 的 spec 文档由 spec skills（`child_agent.spec_tool`）创建和维护**，flow 命令不直接手写 spec 文件
- **根 agent 只创建 hotfix 条目和触发 spec skills，不编码**
- hotfix 编码走 assign → receive → apply 通道（与 spec 相同）
- hotfix 条目放在 `### Hotfix` 子章节，不影响 spec 条目和开发顺序