# Flow 验证检查清单

> **受众**：业务项目中执行 `flow-codex-verify`、Codex `flow-codex-archive` 或 Claude `/flow:archive` 步骤 0 的 Agent。
> **不是**跨服务 api.md 契约比对（Claude `flow:verify` / flow-verify 专责）。
> skills 仓库维护者改本文件后须同步 verify/archive skill（见仓库根 MAINTENANCE.md）。

本清单分两层：**§A 产物格式**（结构/格式，不判业务内容）与 **§B 发布就绪**（完成度与 git 状态）。`flow-codex-test` / `flow-codex-archive` 前须 **§A + §B 全量** verify 且无 ERROR。design 完成后可 **仅跑 §A** 做格式复验。

---

## 输出格式

按项输出 `PASS` / `WARN` / `ERROR`。全量 verify 存在 **ERROR** 时不可进入 `flow-codex-test` 或 `flow-codex-archive`（WARN 需用户确认后可继续）。

---

## §A 产物格式（ERROR）

**design 完成后可跑；test/archive 前必跑。** 只读、可机器判定；**不检查**业务逻辑、接口语义、拆法是否最优。

读取 `dev-doc-maintenance.md`、`task-md-maintenance.md` §2.2 与 `platform.md` Spec 粒度铁律。

### A.1 根产物存在

以下文件均须存在于 `.flow/changes/{change-name}/`：

- `概要设计.md`
- `开发文档.md`
- `task.md`
- `发版记录.md`

### A.2 概要设计 Spec 矩阵

| 检查项 | 说明 |
|--------|------|
| Spec 矩阵存在 | `概要设计.md` 含「服务拆分」/ Spec 矩阵表（列含 Spec、服务） |
| 矩阵行型 | 每行「服务」列恰好一个 repo 名；禁止 `+`、顿号、多服务名 |
| 开发顺序对齐 | 「开发顺序」与矩阵一一对应，非仅按服务枚举 |

### A.3 task.md 格式

| 检查项 | 说明 |
|--------|------|
| 开发顺序行型 | `## 开发顺序` 每行 `{序号}. {spec-id}（{单一 service}，依赖 {spec-id 或 —}）` |
| 单仓约束 | 括号内不得出现 `+` 或多个已知服务名（Spec 粒度铁律） |
| spec 唯一归属 | 同一 `c{n}-…` spec-id 只出现在 **一个** `## {service}` 章节下 |
| 依赖引用 | 依赖须用 `c{n}` 格式，禁止纯数字（见 task-md-maintenance §2.2） |

### A.4 开发文档格式

读取 `dev-doc-maintenance.md` 与 schema §10。

**ERROR**

- 缺少必须章节：§2、§3.2.1、§3.2.2、§3.2.3、§3.2.4、§4.1
- §3.2.4 或全文存在 ```json 代码块（完整请求/响应体）
- 含 Flow 编排痕迹：正则 `c\d+-`、`$flow-codex-`、或明显 c7/L1/L2/L3 测试分层描述
- §3.2.4 接口表「服务」列一行多 repo（`+` 或多服务名）

**WARN**（仅全量 verify 时评估）

- §3.2.4 仍有「待录入」「待补充」
- §3.2.2 或 §3.2.3 仍为 design 占位且无实质内容

### A.5 子 OpenSpec 结构

| 检查项 | 说明 |
|--------|------|
| change 目录 | 每个 task spec-id 在对应服务 repo 下有且仅有 **一个** `openspec/changes/<spec-id>/` |
| 必备文件 | 各 change 含 `proposal.md`、`design.md`、`tasks.md`、`specs/**/*.md` |
| apply-ready | `openspec instructions apply --change <spec-id> --json` 不返回 `state: blocked`（结构门禁，非业务评审） |

### A.6 发版记录行型

| 检查项 | 说明 |
|--------|------|
| 单仓记录 | 每条 commit 记录绑定 **一个** spec + **一个** 服务/repo（如 `c1 @ worker-service`）；禁止一行多仓 |

---

## §B 发布就绪（ERROR）

**仅 test/archive 全量 verify 时执行。** 不适用于 design 后仅跑 §A 的场景。

| 检查项 | 说明 |
|--------|------|
| task.md 完成度 | 全部 spec 条目为 `[x]`，含 `完成：YYYY-MM-DD commit <hash>` |
| 期望分支 | 各涉及服务在 task.md / config 约定的分支；不匹配则 ERROR |
| worktree 洁净 | 各服务 `git status --short` 无未解释的历史改动 |
| 发版记录覆盖 | 有 DDL/配置的 spec 在 `发版记录.md` 中已体现（存在性，非 SQL 正确性） |

**WARN**

- §4.2 为空但发版记录已有 DDL/配置

---

## 不在本清单范围

- 跨服务 `api.md` / `{provider}-api.md` 契约比对 → Claude `/flow:verify`
- 概要设计验收标准是否通过 → `flow-codex-test`
- 单元测试是否充分 → apply/report 阶段
- 业务拆法、接口语义、Non-goals 是否正确 → design / review
- BFF 接口是否应归 aggregator → design Spec 矩阵 + review

---

## Claude archive 用法

`/flow:archive` 执行前运行本清单 **§A + §B** 全量（跳过「不在本清单范围」中的契约项）。有 ERROR 则停止归档。
