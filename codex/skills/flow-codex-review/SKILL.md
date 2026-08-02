---
name: flow-codex-review
description: 根据 OpenSpec 设计对一个 Flow spec 实现执行独立只读审核。作为根编排 agent 启动的同级审核 agent 使用。
---

# Codex Flow 审核

读取 `../flow-codex-core/references/platform.md` 和 `references/review-format.md`。这是内部只读
辅助 skill。

## 输入

要求提供 `change_name`、`spec_id`、服务路径、设计路径、变更文件列表和审核轮次。

可选 `review_mode`：

- **默认（业务 spec）**：设计路径为 OpenSpec `design.md`
- **`test`**：`spec_id` 为 `st-api-*`；设计路径为 system-test 的 `test-design.md`、`test-plan.md` +
  `manifest.yaml`（见 `references/review-format.md` §test 模式）

## 审核

1. 读取设计产物和变更文件（按 review_mode 选择 OpenSpec 或 test-plan/manifest）。业务 spec 还读取根 `domain-model.md`、概要设计的「领域事实引用」及同一指纹的 `DOMAIN_VERIFY_RESULT PASS`。
2. 检查正确性、缺失的验收标准、回归风险、不安全行为和缺失测试。业务 spec 消费 Fact ID 时，逐项建立 `Fact ID → 实现位置 → 单元测试` 映射；缺映射、弱化生效条件/反例或没有反例单测时 **REJECT**。
3. 变更涉及列表、分页、报表 SQL 或 Mapper 的 JOIN / 选行 / 过滤时，读取根 `概要设计.md` 的「数据访问契约」和本 spec `design.md`：
   - 契约缺失、未传导到 spec，或未声明查询风险为「无」时 **REJECT**。
   - 逐项比对主表过滤、JOIN 等值键、基数、唯一性/索引依据与跨服务参考实现；偏离没有设计理由时 **REJECT**。
   - `max/min` 选行、相关子查询、`EXISTS/IN`、跨表 `OR`、前置 `%LIKE%`、`GROUP BY + PageHelper count` 均为风险形态；没有明确业务语义、索引路径和允许理由时 **REJECT**。不得以 `max(id)` 臆断「最新」。
   - 检查 Mapper 契约测试覆盖 JOIN 键和禁止形态；在可运行 EXPLAIN 前不接受「性能已验证」声明，并要求测试/发布计划覆盖最终列表 SQL 与分页 count。
4. test 模式额外检查：AC→场景→方法→断言覆盖、无理由 skip、fixtures 预留 ID 合规；审核测试实现正确性，
   不替代 test-design lifecycle verify。
5. 不要编辑文件、提交或扩大范围。
6. 没有可执行问题时返回 `[REVIEW_RESULT] PASS`。
7. 否则返回 `[REVIEW_RESULT] REJECT`，并附带简短的问题列表、文件和行号。
