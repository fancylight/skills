# Flow 发布就绪检查清单

> **受众**：业务项目中执行 `flow-codex-verify`、Codex `flow-codex-archive` 或 Claude `/flow:archive` 步骤 0 的 Agent。
> **不是**跨服务 api.md 契约比对（Claude `flow:verify` / flow-verify 专责）。
> skills 仓库维护者改本文件后须同步 verify/archive skill（见仓库根 MAINTENANCE.md）。

---

## 输出格式

按项输出 `PASS` / `WARN` / `ERROR`。存在 **ERROR** 时不可进入 `flow-codex-test` 或 `flow-codex-archive`（WARN 需用户确认后可继续）。

---

## 1. 流程就绪（ERROR）

| 检查项 | 说明 |
|--------|------|
| task.md 完成度 | 全部 spec 条目为 `[x]`，含 `完成：YYYY-MM-DD commit <hash>` |
| 期望分支 | 各涉及服务在 task.md / config 约定的分支；不匹配则 ERROR |
| worktree 洁净 | 各服务 `git status --short` 无未解释的历史改动 |
| OpenSpec | 各 spec 目录存在且设计曾 apply-ready（proposal/design/tasks 齐备） |
| 发版记录 | `发版记录.md` 存在；有 DDL/配置的 spec 在发版记录中已体现 |

---

## 2. 根产物齐全（ERROR）

以下文件均须存在于 `.flow/changes/{change-name}/`：

- `概要设计.md`
- `开发文档.md`
- `task.md`
- `发版记录.md`

---

## 3. 开发文档规范

读取 `dev-doc-maintenance.md` 与 schema §10。

### ERROR

- 缺少必须章节：§2、§3.2.1、§3.2.2、§3.2.3、§3.2.4、§4.1
- §3.2.4 或全文存在 ```json 代码块（完整请求/响应体）
- 含 Flow 编排痕迹：正则 `c\d+-`、`$flow-codex-`、或明显 c7/L1/L2/L3 测试分层描述

### WARN

- 全部 spec 已完成，但 §3.2.4 仍有「待录入」「待补充」
- §3.2.2 或 §3.2.3 仍为 design 阶段占位（如「待实现后补充」）且无实质内容
- §4.2 为空但发版记录已有 DDL/配置

---

## 4. 不在本清单范围

- 跨服务 `api.md` / `{provider}-api.md` 契约比对 → Claude `/flow:verify`
- 概要设计验收标准是否通过 → `flow-codex-test`
- 单元测试是否充分 → apply/report 阶段

---

## Claude archive 用法

`/flow:archive` 执行前运行本清单 §1–§3（跳过 §4 契约项）。有 ERROR 则停止归档。
