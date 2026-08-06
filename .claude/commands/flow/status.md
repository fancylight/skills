---
name: "Flow: Status"
description: "Root agent views requirement progress across all services, showing spec-level completion"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.4.0"
---

查看大需求在所有服务的进度，精确到 spec 粒度；lease-v1 时附带租约/审核握手观察。

**输入**：`/flow:status [change-name]`

协议：`~/.claude/commands/flow/docs/control-plane.md`。

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`

---

**步骤**

1. **扫描活跃需求**

   列出 `.flow/changes/` 下非 `archive/` 的目录。
   如指定了 change-name，只查看该需求；否则全部展示。

2. **读取 task.md，解析进度**

   对每个活跃 change：
   - 解析元数据头（需求名、类型、状态、Tier、分支、涉及服务、`protocol_version`）
   - 按服务分组统计 spec 完成情况：`[x]` 数 / 总数
   - 识别 `blocked by` 依赖关系
   - 识别 `## 变更通知` 章节（如有，标注有待处理变更）

3. **扫描各服务实际状态与进度文件**

   对每个涉及的服务，检查服务目录：
   - 是否有活跃 spec change
   - 进度文件最新标记：`REVIEW_REQUEST` / `REPORT_REQUEST` / `REPORT complete` / 失败

   综合状态判断（优先级从高到低）：
   1. ⏳ 阻塞：有 `blocked by` 依赖且依赖未完成
   2. ⚠️ 有变更通知：task.md 变更通知章节中有该服务的待处理条目
   3. 🔍 待审核：进度含未中继的 `REVIEW_REQUEST`（lease-v1）
   4. 📝 待报告租约：进度/`REPORT_REQUEST` 等待根 grant
   5. 🔄 开发中：有活跃 spec change
   6. 📋 待开始：task.md 中有任务但无 spec change
   7. ✅ 完成：该服务所有 spec 已 `[x]`
   8. ❓ 未知：无法访问服务目录

4. **输出进度报告**

   ```
   ## 需求进度：{需求名称}

   类型：{feature/hotfix} | Tier：{tier} | 分支：{branch} | protocol：{legacy|lease-v1}
   整体进度：{完成 spec 数}/{总 spec 数} specs 完成

   | 服务 | 状态 | Spec 进度 | 说明 |
   |------|------|-----------|------|
   | service-b | ✅ 完成 | 2/2 | — |
   | service-a | 🔍 待审核 | 1/3 | REVIEW_REQUEST round 1 |
   | service-c | ⏳ 阻塞 | 0/2 | 等待 service-b |

   ### 未完成 Spec 清单
   - …

   ### 建议下一步
   - lease-v1 待审核 → 根执行 peer `/flow:review` 并回传 REVIEW_RESULT
   - 待报告租约 → 串行发放 REPORT_LEASE_GRANTED
   - 依赖已解除 → `/flow:assign <service>`
   ```

---

**约束**

- 只读操作，不修改任何文件
- 服务状态基于 task.md + 进度文件 + 目录扫描综合判断
- 建议下一步基于依赖关系与租约状态自动推导