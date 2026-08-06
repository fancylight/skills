---
name: "Flow: Apply"
description: "Child agent executes one assigned Flow spec — coding, review handshake, unit tests, commit. lease-v1 defers review/report to root; legacy keeps inline review."
category: Workflow
tags: [workflow, orchestration, multi-agent, executor, coding]
version: "0.4.0"
---

子 agent 阶段二：对**唯一**已接收的 spec 执行编码循环。编码委托给 `spec_tool`（如 opsx:apply）。**不更新 task.md**——那是 `/flow:report` 的职责。

**输入**：`/flow:apply <spec-name>`（必传，由 `/flow:receive` 确定后传入）

协议见安装后的 `~/.claude/commands/flow/docs/control-plane.md`。解析 `protocol_version`（change 级覆盖根 `flow.protocol_version`；缺省 = `legacy`）。

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: executor`
2. 读取 `spec_tool`、`inline_agents`、根/change 的 `protocol_version`
3. 确认已执行 `/flow:receive`（spec 已确定，design.md 已就绪）

---

**步骤（共用）**

1. **验证 spec 就绪**

   检查 spec 目录下 `design.md` 存在。不存在则拒绝："spec {name} 尚未完成设计，请先执行 /flow:design"。

2. **定位进度文件**

   扫描 `{服务目录}/.flow/{active_change}/spec/progress-*.md`，找到匹配当前 spec 的进行中文件（头部 `# {spec_name}`；排除 `✅ 已完成`）。无则警告但继续。

   追加：`- [APPLY] 开始编码 — {timestamp}`

3. **编码实现**

   使用 `spec_tool`（如 `opsx:apply`）执行编码。**不直接手写代码，也不手动转述 design.md——委托给 spec_tool。**

   追加：`- [APPLY] 编码完成`

---

### A. `protocol_version: lease-v1`（默认新 change）

4. **发出审核请求（禁止自行拉起 review agent）**

   返回并**停止继续编码**：

   ```text
   [REVIEW_REQUEST]
   change_name: <change>
   spec_id: <spec>
   service_path: <absolute path>
   design_path: <absolute path to design.md>
   changed_files:
     - <path>
   round: <1..3>
   ```

   等待根把 `[REVIEW_RESULT] PASS|REJECT` 作为 follow-up 注入本执行上下文。

5. **审核后恢复**

   - `REJECT`：只修复已报告问题；`round += 1`；再次 `[REVIEW_REQUEST]`。连续 3 轮 REJECT → 输出 `[REVIEW_LOOP] STOPPED` / `reason: MAX_REJECT_ROUNDS` 并停止。
   - `PASS`：执行 `inline_agents.unit_test.test_command`。失败 → 修复 → 重跑，最多 3 轮。
   - 测试通过后：`git add` 仅本 spec 相关代码与 spec 文件（不用 `git add .`）；commit message 中文：`{prefix}-{id} {类型}: {中文描述}`。
   - 追加：`- [APPLY] ✅ 通过 — commit: {hash} — {date}`
   - 返回并停止：

   ```text
   [REPORT_REQUEST]
   change_name: <change>
   spec_id: <spec>
   service_path: <absolute path>
   commit_hash: <hash>
   progress_file: <absolute path>
   tests: <summary>
   ```

   等待根发放 `[REPORT_LEASE_GRANTED]` 后再执行 `/flow:report`。**禁止**无 grant 直接 report。

### B. `protocol_version: legacy`（进行中 change 兼容）

4. **内联审核 agent**（旧路径）

   使用 **Agent tool** 启动内联审核。读取 `~/.claude/commands/flow/templates/review-agent-prompt.md`，替换设计路径与变更文件列表。

   驳回 → 修复 → 重审，最多 3 次。追加审核进度行。

5. **单元测试** → 失败最多 3 轮。

6. **提交代码**（规则同 A）。

7. **输出结果**并提示下一步 `/flow:report`（可直接 report；应警告 legacy 路径）。

---

**输出（成功）**

```
## 编码完成 — {spec-name}
✅ 通过 | protocol：{lease-v1|legacy} | commit：{hash}
lease-v1：等待 REPORT_LEASE_GRANTED 后 /flow:report
legacy：下一步 /flow:report
```

---

**约束**

- **不更新 task.md**
- **不读取 task.md 找 spec**——spec 已由 `/flow:receive` 确定
- lease-v1：**禁止**子 agent 自行 Agent 拉起 review；**禁止**无 `REPORT_LEASE_GRANTED` 调用 report
- 审核与测试重试各最多 3 次，超限必须停止
