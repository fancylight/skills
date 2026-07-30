---
name: flow-codex-system-test
description: 使用 glm-system-test manifest runner 执行 Flow change 的 API/UI/E2E/CDC 系统测试并收集证据。在 test-design 就绪、用户要求本地集成验证或复现测试证据时使用。
---

# Codex Flow 系统测试执行

读取 `../flow-codex-core/references/platform.md` 和 `references/runtime-contract.md`。
执行前必读 `references/local-pitfalls.md`；GLM 多服务需求另读 glm-system-test 仓内
`docs/local-integration-playbook.md`（路径由根 config 解析）。

使用根 config 中的 **system-test 服务仓** 执行需求级黑盒验证。**不要**修改业务服务代码，不要把被测服务整体替换为 mock，
不要操作 manifest 预留 ID 段之外的共享数据。

## 输入

要求提供 `change_name`。`suite` 可选，默认取 manifest 的 `defaultSuites` 或 `api`；允许
`ui-mock`、`api`、`e2e`、`cdc`、`all`。环境文件默认 `.env.local`。

## 定位

1. 从当前目录向上确认根编排目录包含 `.flow/config.yaml`（`role: orchestrator`）。
2. 从根 config 的 `services` 解析测试仓：`type: system-test`，或 name 为 `system-test` / `glm-system-test`。
3. 读取 `.flow/changes/<change_name>/概要设计.md` 验收标准。
4. 读取 `<test-repo>/changes/<change_name>/manifest.yaml` 和 `test-plan.md`。
5. 测试仓或 manifest 不存在时 **停止**；提示先跑 `flow-codex-test-design`（可 scaffold 模板仓），不要临时拼凑命令。

## 执行

在测试仓目录运行（见 runtime-contract）：

1. `doctor` — 阻断时返回缺失配置或中间件，不编辑业务服务。
2. `run -Suite <suite>` — runner 负责 `up → seed → test → evidence`。
3. 成功时 runner 自动 cleanup；失败时保留现场并返回 cleanup 命令。
4. 统计 passed/failed/skipped；必需用例出现 skip 时整体视为失败。
5. 若 `test-plan.md` 含 SQL 计划验证，使用其中声明的**只读**连接和最终 SQL 执行列表 SQL 与分页 count SQL 的 `EXPLAIN`；保存脱敏后的文本/JSON、参数、环境与时间。不得从 Mapper 源码推测 count SQL，也不得伪造 EXPLAIN。
6. SQL 风险验收：非豁免 `DEPENDENT SUBQUERY`、关键大表 `ALL` 扫描、缺少 final count SQL 或证据，均为 FAIL；豁免必须在数据访问契约中事先批准并写明索引/容量边界。
7. 将摘要写入 `<test-repo>/changes/<change_name>/evidence/summary.md`。
8. 将同一摘要写入根 `.flow/changes/<change_name>/集成测试.md`（命令、结果、SQL 计划证据、阻断项）；
   不修改概要设计或 task 条目状态（task 勾选由 `flow-codex-test` 负责）。

## 结果

严格输出：

```text
[SYSTEM_TEST_RESULT] PASS | FAIL
change_name: <name>
suites: <comma-separated suites>
passed: <count>
failed: <count>
skipped: <count>
evidence: <absolute path>
sql_plan_evidence: <absolute path or none>
retained_state: true | false
cleanup_command: <command or none>
```

PASS 要求所有指定 suite 完成、必需用例无 skip、cleanup 成功且证据存在。
