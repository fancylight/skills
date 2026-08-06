---
name: "Flow: Review"
description: "Root-scheduled peer-only code review for one Flow spec (or st-api test spec). Read-only; returns REVIEW_RESULT PASS|REJECT."
category: Workflow
tags: [workflow, orchestration, multi-agent, review]
version: "0.1.0"
---

根据设计产物对**一个** Flow spec 实现执行独立只读审核。由根编排在收到 `[REVIEW_REQUEST]` 后调度（Agent tool 或本命令）；**不是**执行子 agent 的内联职责（lease-v1）。

协议：`~/.claude/commands/flow/docs/control-plane.md`。输出格式对齐 `~/.claude/commands/flow/templates/review-agent-prompt.md` 与 Codex `review-format`。

**输入**（根传入）：`change_name`、`spec_id`、服务绝对路径、`design_path`、变更文件列表、`round`（1..3）。

可选 `review_mode`：

- **默认（业务 spec）**：`design_path` = OpenSpec `design.md`
- **`test`**：`spec_id` 为 `st-api-*`；设计路径为 system-test 的 `test-design.md`、`test-plan.md` + `manifest.yaml`

---

**步骤**

1. 读取设计产物与变更文件（按 `review_mode` 选择 OpenSpec 或 test-plan/manifest）。业务 spec 还读取根 `domain-model.md`、概要设计「领域事实引用」及同一指纹的 `DOMAIN_VERIFY_RESULT PASS`（若存在）。
2. 检查正确性、缺失的验收标准、回归风险、不安全行为、缺失测试。业务 spec 消费 Fact ID 时，逐项建立 `Fact ID → 实现位置 → 单元测试` 映射；缺映射、弱化生效条件/反例或没有反例单测时 **REJECT**。
3. 变更涉及列表、分页、报表 SQL 或 Mapper 的 JOIN / 选行 / 过滤时，读取根 `概要设计.md`「数据访问契约」和本 spec `design.md`：
   - 契约缺失、未传导到 spec，或未声明查询风险为「无」时 **REJECT**
   - 逐项比对主表过滤、JOIN 等值键、基数、唯一性/索引依据与跨服务参考实现；偏离无设计理由时 **REJECT**
   - `max/min` 选行、相关子查询、`EXISTS/IN`、跨表 `OR`、前置 `%LIKE%`、`GROUP BY + PageHelper count` 均为风险形态；无明确业务语义、索引路径和允许理由时 **REJECT**。不得以 `max(id)` 臆断「最新」
   - 检查 Mapper 契约测试覆盖 JOIN 键和禁止形态；在可运行 EXPLAIN 前不接受「性能已验证」声明
4. test 模式额外检查：AC→场景→方法→断言覆盖、无理由 skip、fixtures 预留 ID 合规；审核测试实现正确性，**不**替代 test-design lifecycle verify。
5. **不要**编辑文件、提交或扩大范围。
6. 无问题返回：

```text
[REVIEW_RESULT] PASS
```

7. 否则返回：

```text
[REVIEW_RESULT] REJECT
```

并附简短问题列表、文件和行号（见 `review-agent-prompt.md` 结构）。

---

**约束**

- 只读；不改代码、不 git commit、不更新 task.md
- 词法必须为 `[REVIEW_RESULT] PASS|REJECT`，禁止另造标记
- 根负责中继结果到**同一**执行子 agent，并维护最多 3 轮 REJECT计数
