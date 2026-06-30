# 开发文档维护规范

> **受众**：在**业务项目**中执行 Flow 的 Agent（`flow-codex-design`、`flow:design`、`flow-codex-report`、`flow:report`、`flow-codex-verify`）。
> **不是** skills 仓库维护文档——维护 `skills` 项目请读仓库根 [MAINTENANCE.md](../../MAINTENANCE.md)（路径相对于业务项目时忽略；在 skills 仓库内为 `/MAINTENANCE.md`）。
>
> 安装后路径：`flow-codex-core/assets/templates/dev-doc-maintenance.md`（Codex）或 `commands/flow/templates/dev-doc-maintenance.md`（Claude）。
> 模板：`开发文档模板.md.tmpl`。协议：`flow/docs/schema.md` §10。

---

## 1. 受众与目的

**读者**：开发、测试、运维、发版负责人。

**目的**：说明本次需求做了什么、业务如何运行、数据如何存取与流转、接口在哪里查、如何上线。**不是** Agent 编排说明书。

---

## 2. 必须章节（MUST）

| 章节 | 内容 |
|------|------|
| §1 需求文档 | 原始需求 Markdown/PDF 链接 |
| §2 需求分析 | 发版范围、背景、现状、需求定义、**相关规则**、影响范围 |
| §3.2.1 业务规则 | 可验证的业务语义（公式、边界、异常业务含义） |
| §3.2.2 存储与数据 | 表/字段语义、读写策略、历史兼容；完整 DDL 见 `发版记录.md` |
| §3.2.3 数据流转 | 配置→持久化→运行时消费链路（服务/接口级） |
| §3.2.4 接口设计 | 路径 + 服务 + Apifox 链接 + 变更类型 + 要点；**禁止完整 JSON** |
| §4 上线 checkList | §4.1 服务-分支；§4.2 SQL/配置摘要 |

---

## 3. 可选章节（MAY）

| 章节 | 条件 | 约束 |
|------|------|------|
| §3.1 前端 | 有前端改动 | **模块/页面级**影响；禁止 `.vue`/`.js` 文件清单 |

---

## 4. 禁止内容（MUST NOT）

- Flow/OpenSpec 编排：spec 名（`c1-xxx`）、`$flow-codex-*`、c7 测试分层、审核返修、报告租约
- 实现级清单：Java 类路径、逐文件改动表
- 完整接口 JSON / 大段字段表（权威在 **Apifox**）
- 照搬 `概要设计.md`：开发顺序、验收标准全文、接口契约草稿 JSON、Flow 测试设计

---

## 5. 与其他文档的边界

| 内容 | 权威文档 |
|------|----------|
| 接口字段类型与示例 | Apifox |
| 类/文件如何实现 | 服务 OpenSpec `design.md` |
| spec 顺序、集成验收、c7 | `概要设计.md` |
| DDL 原文 | `发版记录.md` |
| spec 完成状态 | `task.md` |

---

## 6. 阶段职责

| 阶段 | 对 `开发文档.md` 的动作 |
|------|-------------------------|
| design（根） | §1–§2 从需求填写；§3.2.1–3.2.3 **摘要/占位**；§3.2.4 接口表骨架（Apifox 列「待录入」）；§4.1 填分支；§4.2 留空 |
| apply（执行） | **不**直接改根 `开发文档.md` |
| report（执行） | 按 `dev-doc-update-rules.md` 回写 §3.2.2–3.2.4、§4.2；Apifox 同步 |
| verify（根） | 只读检查格式与禁止项（见 `verify-checklist.md`） |
| archive（根） | 要求 verify 无 ERROR |

---

## 7. 附录：好 vs 坏示例（尺度参考）

**§3.2.1 业务规则 — 好**

```text
effectiveCodes = org0Codes ∪ ancestorCodes ∪ currentCodes
lockedCodes = org0Codes ∪ 上级 codes；保存不得移除 locked 项
```

**§3.2.1 — 坏**（实现清单）

```text
WorkerOnDutyWarnGenerator 改为 queryEffectiveCompanyTypeIds(...)
```

**§3.2.4 接口 — 好**

| 接口 | 服务 | Apifox | 变更 | 说明 |
| GET /rule/companyTypeControl | worker-service | https://app.apifox.com/... | 🆕新增 | 累加型配置查询 |

**§3.2.4 — 坏**（完整 JSON 块）

```json
{ "success": true, "data": { "items": [...] } }
```
