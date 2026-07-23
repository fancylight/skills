# Flow 验证检查清单

> **受众**：业务项目中执行 `flow-codex-verify`、Codex `flow-codex-archive` 或 Claude `/flow:archive` 步骤 0 的 Agent。
> **不是**跨服务 api.md 契约比对（Claude `flow:verify` / flow-verify 专责）。
> skills 仓库维护者改本文件后须同步 verify/archive skill（见仓库根 MAINTENANCE.md）。

本清单分三层：

- **§A 产物格式**（结构/格式，不判业务语义）
- **§B 发布就绪**（完成度与 git 状态；仅全量 verify）
- **§C 设计过程合规**（领域概念与向下传导；仅 `verify_mode=design`）

| 调用模式 | 章节 |
|----------|------|
| 格式复验（默认轻量） | §A |
| 设计合规（`verify_mode=design`） | §A + §C |
| 全量 verify（test/archive） | §A + §B（**不**默认跑 §C；assign 前单独跑 design 模式） |

`flow-codex-test` / `flow-codex-archive` 前须 **§A + §B 全量** verify 且无 ERROR。`flow-codex-assign` 前须 **§A + §C**（`verify_mode=design`）且无 ERROR。

---

## 输出格式

按项输出 `PASS` / `WARN` / `ERROR`。全量 verify 存在 **ERROR** 时不可进入 `flow-codex-test` 或 `flow-codex-archive`（WARN 需用户确认后可继续）。design 模式存在 **ERROR** 时不可 `flow-codex-assign`。

---

## §A 产物格式（ERROR）

**design 完成后可跑；test/archive 前必跑；design 模式一并跑。** 只读、可机器判定；**不检查**业务逻辑、接口语义、拆法是否最优。

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
| st-api 行型（test-design 后） | 若含集成测试，开发顺序含 `st-api-*（glm-system-test，依赖 …）`；`## glm-system-test` 章节存在 |

### A.4 开发文档格式

读取 `dev-doc-maintenance.md` 与 schema §10。

**ERROR**

- 缺少必须章节：§2、§3.2.1、§3.2.2、§3.2.3、§3.2.4、§4.1、§4.2、§4.3
- §3.2.4 或全文存在 ```json 代码块（完整请求/响应体）
- 含 Flow 编排痕迹：正则 `c\d+-`、`$flow-codex-`、或明显 c7/L1/L2/L3 测试分层描述
- §3.2.4 接口表「服务」列一行多服务名（`+` 或顿号分隔）
- §4.1「服务名称」列仅写 git 仓库名冒充服务（多模块仓未拆可部署单元），或与「git 仓库」列同名且该仓已知为多模块时未拆行
- 正文依赖本地文件引用：如「详见发版记录」「见 openspec/」或明显本地相对路径作为唯一说明
- §4.3 含测试类名、`127.0.0.1`/本机端口、commit hash、或本地启动/服务清单式说明

**WARN**（仅全量 verify 时评估）

- §3.2.4 仍有「待录入」「待补充」
- §3.2.2 或 §3.2.3 仍为 design 占位且无实质内容
- §4.2 仅有「详见发版记录」而无 DDL/配置正文（有发版记录 DDL 时升为 ERROR，见 §B WARN 关联）

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

**仅 test/archive 全量 verify 时执行。** 不适用于 design 后仅跑 §A、也不适用于 `verify_mode=design`。

| 检查项 | 说明 |
|--------|------|
| task.md 完成度 | 全部 spec 条目为 `[x]`，含 `完成：YYYY-MM-DD commit <hash>` |
| 期望分支 | 各涉及服务在 task.md / config 约定的分支；不匹配则 ERROR |
| worktree 洁净 | 各服务 `git status --short` 无未解释的历史改动 |
| 发版记录覆盖 | 有 DDL/配置的 spec 在 `发版记录.md` 中已体现（存在性，非 SQL 正确性） |

**WARN**

- §4.2 为空或仅占位，但发版记录已有 DDL/配置（开发文档 §4.2 应自包含写出 SQL/配置）

---

## §C 设计过程合规（ERROR / WARN）

**仅 `verify_mode=design` 时执行。** 只读；不写 KB、不审代码、不跑集成测试。

**标题匹配规则**（概要设计）：

| 节 | 认可标题（任一） |
|----|------------------|
| 领域概念 | `## 领域概念` |
| 歧义裁决 | `## 歧义裁决` |
| pass 决策表 | `## 审核 pass / 写库决策表` 或 `## 审核 pass` |
| 集成范围 | `## 集成 / 联调范围` 或 `## 集成` |

读取 `.flow/changes/{change}/概要设计.md`；对每个 task spec-id 读取对应服务 `openspec/changes/{spec-id}/design.md` 与 `specs/**/*.md`。输出 `文件:行号` 或章节名。

### C.1 概要设计必备节

| ID | 级别 | 检查项 | 说明 |
|----|------|--------|------|
| C.1.1 | ERROR | 领域概念节存在 | `## 领域概念` 存在且至少 1 行数据行（非仅表头/占位） |
| C.1.2 | ERROR | 词条字段完整 | 每行含 mandatory 列：词条、定义、判定条件、来源、影响 spec |
| C.1.3 | ERROR/WARN | KB 引用可解析 | `来源=kb`（或 `source=kb`）时 KB 引用非空；若根 `config.yaml` 启用 KB 且路径可访问，引用路径或 @feature 须存在（不可访问时 WARN） |
| C.1.4 | ERROR | change 词条 kb_action | `来源=change` 时 kb_action 为 `待沉淀` 或 `无需` |
| C.1.5 | WARN | 歧义裁决 | 同目录存在对齐纪要等且含明显冲突表述时，须有 `## 歧义裁决` 且每议题有唯一「裁决」列；无冲突文档时若写「无未裁决歧义」则 PASS |
| C.1.6 | ERROR | pass 决策表 | 存在多步审核/状态流转描述时须有 pass 决策表（见标题匹配）且覆盖文档中提到的每个审核节点；否则 ERROR。无多步审核时可缺省 |
| C.1.7 | ERROR | 集成范围 | 集成范围节存在；首派 vs Phase-2（或不在本次）有明确标注 |

### C.2 向下传导

| ID | 级别 | 检查项 | 说明 |
|----|------|--------|------|
| C.2.1 | ERROR | 矩阵覆盖影响面 | 领域概念「影响 spec」列中出现的 c{n} 均在 Spec 矩阵中存在 |
| C.2.2 | ERROR | 术语不降级 | 子 OpenSpec（proposal/design/delta spec）出现与根领域概念同主题但**更模糊**的表述，且未引用根词条名。启发式示例：根有「腾讯电子合同 type=3」，子 spec 仅写「正式合同」「worker_contract」而无 type/company 约束。报 ERROR 时须引用根概念行号与子 spec 位置 |
| C.2.3 | ERROR | 裁决已传导 | 歧义裁决表的「回写」项在对应 OpenSpec 或概要设计验收标准中可找到一致表述 |
| C.2.4 | WARN | pass 表与矩阵 | pass 决策表「owning spec」均在矩阵中且职责不空 |

**C.2.2 模糊词示例（首版内联）**：仅写「正式合同」「普通合同」「worker_contract」而无类型/主体约束；仅写「预警」而无 type；仅写「通过」而无写库路径。有根词条名显式引用时不判降级。

### C.2 检测方法

- 读取概要设计与（若存在）同目录 `对齐纪要.md` 等对齐文档
- 对每个 task spec-id 读取对应服务 OpenSpec 设计与 delta specs
- **只读**；不得自动编辑/修复产物

---

## 不在本清单范围

- 跨服务 `api.md` / `{provider}-api.md` 契约比对 → Claude `/flow:verify`
- 运行时业务是否正确、验收是否通过 → `flow-codex-test` / 联调
- 代码是否违背设计 → `flow-codex-review`（apply 后）
- 单元测试是否充分 → apply/report 阶段
- §C 不判断：SQL 正确性、性能、安全 exploit、KB 正文业务是否过时
- BFF 接口是否应归 aggregator → design Spec 矩阵（结构归 §A；语义归 design 产出 + §C 领域概念）

---

## Claude archive 用法

`/flow:archive` 执行前运行本清单 **§A + §B** 全量（**不**强制 §C）。有 ERROR 则停止归档。
