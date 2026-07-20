# 开发文档维护规范

> **受众**：在**业务项目**中执行 Flow 的 Agent（`flow-codex-design`、`flow:design`、`flow-codex-report`、`flow:report`、`flow-codex-verify`）。
> **不是** skills 仓库维护文档——维护 `skills` 项目请读仓库根 [MAINTENANCE.md](../../MAINTENANCE.md)（路径相对于业务项目时忽略；在 skills 仓库内为 `/MAINTENANCE.md`）。
>
> 安装后路径：`flow-codex-core/assets/templates/dev-doc-maintenance.md`（Codex）或 `commands/flow/templates/dev-doc-maintenance.md`（Claude）。
> 模板：`开发文档模板.md.tmpl`。协议：`flow/docs/schema.md` §10。

---

## 1. 受众与目的

**读者**：开发、测试、运维、发版负责人。

**目的**：说明本次需求做了什么、业务如何运行、数据如何存取与流转、接口在哪里查、如何上线与验收。**不是** Agent 编排说明书。文档须**自包含**：读者不应依赖打开其它本地文件才能看懂正文。

---

## 2. 必须章节（MUST）

| 章节 | 内容 |
|------|------|
| §1 需求文档 | 原始需求 Markdown/PDF 链接（用户自维护；Agent 不改内容） |
| §2 需求分析 | 发版范围、背景、现状、需求定义、**相关规则**、影响范围 |
| §3.2.1 业务规则 | 可验证的业务语义（公式、边界、异常业务含义） |
| §3.2.2 存储与数据 | 表/字段语义、读写策略、历史兼容；**完整 SQL 放 §4.2**，此处不写「见发版记录」 |
| §3.2.3 数据流转 | 配置→持久化→运行时消费链路（**服务名 + 接口路径级**；禁止实现类名流水） |
| §3.2.4 接口设计 | 路径 + **恰好一个可部署服务** + Apifox 链接 + 变更类型 + 要点；BFF 对外 HTTP 归 BFF 服务；**禁止完整 JSON**；不写 c ID |
| §4.1 服务-分支 | **服务名称 = 可部署/运行单元**（非 git 仓库名）；多模块仓拆多行，`git 仓库` 列可重复 |
| §4.2 SQL、配置 | DDL/SQL **直接写在本节**（可用代码块）；无配置写「无」；可与发版记录语义一致，但正文自包含 |
| §4.3 测试与验收 | **业务验收语义**（验收点 + 期望行为）；禁止测试类名、本机地址、commit/spec 等 |

---

## 3. 可选章节（MAY）

| 章节 | 条件 | 约束 |
|------|------|------|
| §3.1 前端 | 有前端改动 | **模块/页面级**影响；禁止 `.vue`/`.js` 文件清单 |

---

## 4. 禁止内容（MUST NOT）

适用于开发文档**全文**（§1 用户自维护的原始需求链接除外）：

- Flow/OpenSpec 编排：spec 名（`c1-xxx`）、`$flow-codex-*`、c7 测试分层、审核返修、报告租约
- 本地相对路径、对 `openspec/`、`概要设计.md`、`发版记录.md` 等文件的引用作为正文依赖（如「详见发版记录.md §1」「见 xxx/openspec/...」）
- 实现级堆砌：Java 类名/方法名流水、逐文件改动表、本地路径
- 完整接口 JSON / 大段字段表（权威在 **Apifox**）
- 照搬 `概要设计.md`：开发顺序、验收标准全文、接口契约草稿 JSON、Flow 测试设计
- commit hash、`c{n}-` spec id 写入正文

---

## 5. 章节细则

### 5.1 §4.1 服务-分支

- **服务名称** = 可部署/可运行单元（进程、可独立发布的模块），**不是** git 仓库名。
- 多模块仓（例如 `glm-attendance`）必须拆成实际服务行，如 `clock-record-generate`、`attendance-decide`、`labor-time-calculate`；`git 仓库` 列可重复写同一仓名。
- **禁止**：一行只写仓库名（如仅 `glm-attendance`）冒充服务。
- 其它仓的可部署服务（如 `attendance-service`）各占一行。

**好**

| 序号 | 服务名称 | git 仓库 | 分支名称 |
| --- | ---- | ----- | ---- |
| 1 | clock-record-generate | glm-attendance | feature/xxx |
| 2 | attendance-decide | glm-attendance | feature/xxx |
| 3 | labor-time-calculate | glm-attendance | feature/xxx |
| 4 | attendance-service | glm-attendance-service | feature/xxx |

**坏**

| 序号 | 服务名称 | git 仓库 | 分支名称 |
| --- | ---- | ----- | ---- |
| 1 | glm-attendance | glm-attendance | feature/xxx |

### 5.2 §4.2 SQL、配置

- DDL/SQL **直接写在本节**（Markdown 代码块即可），不要写「详见发版记录.md / openspec / 本地路径」。
- 无配置变更时明确写「无」。
- 可与 `发版记录.md` 语义一致；发版记录仍记录发布侧变更，但**开发文档读者不依赖打开其它本地文件**。

### 5.3 §4.3 测试与验收

写成**业务验收语义**（验收点 + 期望行为）。

**禁止**：

- 测试类名、单测/集成测试清单（如 `RuleDailyTest`）
- commit hash、spec id（`c1`/`c2`/`c3`）
- 本机中间件地址（如 `127.0.0.1:9200`）、本地启动命令、开发环境前置、启动服务清单

**正例**（业务语义）：

- 按天区分进出：日级最多 1 次迟到、1 次早退
- 不区分进出且首末时间相同：只判迟到
- 跨夜班次：按锚点规则落日
- 按区间判定：与既有区间规则兼容
- 配置读写后回显与保存值一致

### 5.4 §3.2.2 / §3.2.3 提醒

- **§3.2.2**：字段语义 + 兼容策略；完整 SQL 放 **§4.2**，不要「见发版记录」。
- **§3.2.3**：服务/接口路径级流转，不要实现类名流水。

---

## 6. 与其他文档的边界

| 内容 | 权威文档 |
|------|----------|
| 接口字段类型与示例 | Apifox |
| 类/文件如何实现 | 服务 OpenSpec `design.md`（**勿写入开发文档正文**） |
| spec 顺序、集成验收编排、c7 | `概要设计.md`（编排用；开发文档 §4.3 只保留业务验收语义） |
| 发版侧 DDL/配置登记 | `发版记录.md`（可与 §4.2 语义一致；开发文档 §4.2 仍须自包含写出） |
| spec 完成状态 | `task.md` |

---

## 7. 阶段职责

| 阶段 | 对 `开发文档.md` 的动作 |
|------|-------------------------|
| design（根） | §1–§2 从需求填写；§3.2.1–3.2.3 **摘要/占位**；§3.2.4 接口表骨架（每行一个**可部署服务**；Apifox 列「待录入」）；§4.1 按可部署单元填分支（多模块仓拆行）；§4.2 留空或「无」；§4.3 写业务验收要点（非测试清单） |
| apply（执行） | **不**直接改根 `开发文档.md` |
| report（执行） | 按 `dev-doc-update-rules.md` 回写 §3.2.1–3.2.4、§4.1（补全本 spec 涉及的可部署服务行）、§4.2、§4.3；Apifox 同步 |
| verify（根） | 只读检查格式与禁止项（见 `verify-checklist.md`） |
| archive（根） | 要求 verify 无 ERROR |

---

## 8. 附录：好 vs 坏示例（尺度参考）

**§3.2.1 业务规则 — 好**

```text
effectiveCodes = org0Codes ∪ ancestorCodes ∪ currentCodes
lockedCodes = org0Codes ∪ 上级 codes；保存不得移除 locked 项
```

**§3.2.1 — 坏**（实现清单）

```text
WorkerOnDutyWarnGenerator 改为 queryEffectiveCompanyTypeIds(...)
```

**§3.2.3 数据流转 — 好**

```text
配置页 → attendance-service POST /rule/... → 表 rule_xxx
      → attendance-decide 消费规则 → 日级迟到/早退结果落库
```

**§3.2.3 — 坏**（类名流水）

```text
RuleDailyServiceImpl → LateEarlyCalculator → AttendanceDecideFacade
```

**§3.2.4 接口 — 好**

| 接口 | 服务 | Apifox | 变更 | 说明 |
| GET /rule/companyTypeControl | worker-service | https://app.apifox.com/... | 🆕新增 | 累加型配置查询 |

**§3.2.4 — 坏**（完整 JSON 块）

```json
{ "success": true, "data": { "items": [...] } }
```

**§4.2 — 好**

```sql
ALTER TABLE rule_late_early ADD COLUMN daily_mode TINYINT NOT NULL DEFAULT 0 COMMENT '...';
```

配置：无

**§4.2 — 坏**

```text
详见发版记录.md §1；SQL 在 openspec/changes/c2-xxx/design.md
```

**§4.3 — 好 / 坏**：见上文 §5.3。
