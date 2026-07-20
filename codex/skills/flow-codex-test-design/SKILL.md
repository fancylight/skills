---
name: flow-codex-test-design
description: 业务 spec verify 全量通过后，产出 glm-system-test 可执行集成测试设计（manifest、test-plan、fixtures、环境契约）。不修改业务服务代码，不写 JUnit。
---

# Codex Flow 集成测试设计

作为根编排 agent 执行。读取 `../flow-codex-core/references/platform.md` 和
`references/manifest-checklist.md`。可选参考 `references/guanghuo-example-index.md` 中的广火样例结构。

## 前置

1. 要求根角色为 `orchestrator`，并明确提供 `change_name`。
2. 要求 `flow-codex-verify` **全量（§A+§B）** 已成功且无 ERROR。
3. 读取 `.flow/changes/<change_name>/概要设计.md` 验收标准与 `task.md`（业务 spec 应已完成或用户指定范围）。

## 输入

- 根 `.flow/changes/<change_name>/概要设计.md`、`task.md`、`发版记录.md`
- 各业务仓 **as-built**（只读）：OpenSpec `design.md`、发版 SQL 路径、关键 Feign/鉴权/端口配置
- 已有 `glm-system-test/changes/<change_name>/`（若存在则增量更新）
- 根 `.flow/config.yaml` 中 `glm-system-test` 的 `path`

## 步骤

1. 从验收表列出每条验收 ID 及是否纳入本地集成（Y/N）、Non-Goals（不测范围）。
2. 只读扫描 as-built：SQL 顺序、服务端口、Feign 常量、WireMock 需求、Redis 鉴权方案。
3. 编写或更新 **glm-system-test** 仓内产物（见 manifest-checklist）。
4. 同步发版 SQL：从业务仓复制到 `glm-system-test/changes/<change_name>/fixtures/release/`，并在根
   `.flow/changes/<change_name>/release-sql/` 保留镜像（若已有则对齐更新）。
5. 在根 `task.md` 追加或更新：
   - `开发顺序` 末行：`st-api-<change_name>（glm-system-test，依赖 — 或 cX…）`
   - `## glm-system-test` 章节与 `st-api-<change_name>` 条目（格式见 `task-md-maintenance.md` §2.7）
   - 完成检查清单：`集成测试设计 READY` — READY 时勾选 `[x]`，BLOCKED 保持 `[ ]`
6. 可选：在根 `.flow/changes/<change_name>/集成测试设计.md` 写摘要并指向 glm-system-test 权威路径。
7. 输出 readiness 结果（见下）。

## 输出（权威路径在 glm-system-test）

| 产物 | 路径 |
|------|------|
| manifest | `glm-system-test/changes/<change_name>/manifest.yaml` |
| test-plan | `glm-system-test/changes/<change_name>/test-plan.md` |
| test-design | `glm-system-test/changes/<change_name>/test-design.md` |
| fixtures | `fixtures/IDS.md`、`seed-fixture.sql`、`cleanup.sql` 等 |
| 环境契约 | `config/services/*/application-system-test.yml` 清单（test-design 列需项，apply 阶段落地） |

## 门禁

- 无 `manifest.yaml` 或 `test-plan.md` → **BLOCKED**，不可进入 `flow-codex-test-assign` 或 `flow-codex-test`。
- 禁止在本阶段编写 `backend-tests/` 下的 Java 测试类（留给 `flow-codex-test-apply`）。
- 禁止修改业务服务源码。

## 结果格式

严格输出：

```text
[TEST_DESIGN_RESULT] READY | BLOCKED
change_name: <name>
artifacts: <absolute path to manifest.yaml>
blocked:
  - <item or none>
next: flow-codex-test-assign
```
