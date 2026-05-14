---
name: "Flow: KB"
description: "Knowledge base maintenance — both root and child agent can use. Reads KB rules, analyzes changes, writes to KB, commits if git repo."
category: Workflow
tags: [workflow, orchestration, multi-agent, knowledge-base]
version: "0.1.0"
---

知识库维护命令，根 agent 和子 agent 均可使用。

**输入**：`/flow:kb <change-name>`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在
2. 读取 `knowledge_base` 配置：
   - `enabled` 必须为 `true`，否则提示"知识库未启用"
   - `path` — 知识库根目录绝对路径
   - `overview` — 知识库概要说明文档路径（如未配置，警告但不中止）
   - `maintenance_guide` — 知识库维护指南文档路径（如未配置，警告但不中止）
3. 确认知识库目录存在，否则提示"知识库路径不存在：{path}"

---

**步骤**

1. **读取 KB 设计文档**

   - 读取 `overview`（如已配置）：理解 KB 的目录结构、内容概要、设计意图
   - 读取 `maintenance_guide`（如已配置）：理解文档命名规范、内容格式要求、判断标准（什么需要记录、什么不需要）

2. **分析本次变更**

   读取活跃 change 的：
   - `概要设计.md` — 整体背景
   - `task.md` — 完成的 spec 清单
   - 各 spec 的 `design.md` — 实现细节

   按维护指南的判断标准，列出需要写入 KB 的内容：
   - 新业务规则
   - 新功能域/模块
   - 坑点/根因
   - 接口变更

   **展示变更清单给用户确认。** 不自动写入。

3. **写入知识库**

   用户确认后，按维护指南的格式规范写入 KB 文件。
   新建文件时遵循 KB 目录结构和命名规范。
   更新已有文件时在对应章节追加，不覆盖原内容。

4. **提交 KB（如为 git 仓库）**

   检查知识库目录是否为 git 仓库（`git status`）：
   - 是 → `git add` 本次修改/新增的文件，`git commit -m "kb: {change-name} — {变更简述}"`
   - 否 → 跳过

5. **输出摘要**

   ```
   ## KB 维护完成
   - 新增：{文件路径列表}
   - 更新：{文件路径列表}
   - 提交：{commit hash 或 跳过}
   ```

---

**约束**
- 遵循 `maintenance_guide` 定义的格式和结构
- KB 提交只涉及本次修改的文件，不用 `git add .`