# Flow 验证检查清单

> **受众**：业务项目中执行 `flow-codex-verify`、Codex `flow-codex-archive` 或 Claude `/flow:archive` 步骤 0 的 Agent。
> **不是**跨服务 api.md 契约比对（Claude `flow:verify` / flow-verify 专责）。
> skills 仓库维护者改本文件后须同步 verify/archive skill（见仓库根 MAINTENANCE.md）。

本清单分六层：

- **§A 产物格式**（结构/格式，不判业务语义）
- **§B 发布就绪**（完成度与 git 状态；仅全量 verify）
- **§C 设计过程合规**（领域概念与向下传导；仅 `verify_mode=design`）
- **§D 链路合规**（操作链路与设计/代码事实比对；仅 `verify_mode=design`）
- **§E 设计文档一致性**（跨文档客观矛盾；仅 `verify_mode=design`）
- **§F SQL 数据访问门禁**（设计契约在 design；EXPLAIN 证据在 release）

| 调用模式 | 章节 |
|----------|------|
| 格式复验（默认轻量） | §A |
| 设计合规（`verify_mode=design`） | §A + §C + §D + §E + §F.1–§F.3 |
| 全量 verify（test 前置） | §A + §B（**不**默认跑 §C/§D/§E/§F；assign 前单独跑 design 模式） |
| 发布 verify（`verify_mode=release`） | §A + §B + §F |

`flow-codex-test` 前须 **§A + §B 全量** verify 且无 ERROR。`flow-codex-assign` 前须 **§A + §C + §D + §E + §F.1–§F.3**（`verify_mode=design`）且无 ERROR。`flow-codex-archive` 前须 **§A + §B + §F** 发布 verify 且无 ERROR。

---

## 输出格式

按项输出 `PASS` / `WARN` / `ERROR`。全量 verify 存在 **ERROR** 时不可进入 `flow-codex-test` 或 `flow-codex-archive`（WARN 需用户确认后可继续）。design 模式（§A+§C+§D+§E）存在 **ERROR** 时不可 `flow-codex-assign`。存在 WARN 时 verify 报告末尾须附 **编排人 WARN 确认清单**（见 `flow-codex-verify` skill）。

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
| st-api 行型（test-design 后） | 若含集成测试，开发顺序含 `st-api-*（{system_test_service}，依赖 …）`；对应 `## {system_test_service}` 章节存在 |

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
| 单仓记录 | 每条 commit 记录绑定 **一个** spec + **一个** 服务/repo（如 `c1 @ <business-service>`）；禁止一行多仓 |

---

## §B 发布就绪（ERROR）

**仅 full/release verify 时执行。** 不适用于 design 后仅跑 §A、也不适用于 `verify_mode=design`。

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

## §D 链路合规（ERROR / WARN）

**仅 `verify_mode=design` 时执行。** 只读；不编辑产物、不判断链路业务正确性、不生成测试用例。

读取 `.flow/changes/{change}/操作链路.md`、`概要设计.md`（Spec 矩阵）、`开发文档.md`（§3.2.4 接口表）。
输出 `文件:行号` 或 `J{n} 步骤 {#}`。

**编号说明**：本版仅实现 D.1.1 / D.1.2 / D.2.1 / D.2.2 / D.2.5。
**D.2.3（期望结果 ↔ 领域概念）与 D.2.4（链路 ↔ pass 决策表）为阶段 B 预留，本版不实现，编号不得占用。**

### D.0 降级与开关

| 情形 | 行为 |
|------|------|
| 缺 `操作链路.md`，且根 `.flow/config.yaml` 未设 `journey_required: true` | D.1.1 **WARN**，D.1.2 / D.2.* **SKIP** |
| 缺 `操作链路.md`，且 `journey_required: true` | D.1.1 **ERROR** |
| `操作链路.md` 存在 | D.1.2 / D.2.* **全部按 ERROR 生效**，与开关无关 |

即：**可以先不写；写了就必须写对。**

### D.1 结构与证据

| ID | 级别 | 检查项 | 说明 |
|----|------|--------|------|
| D.1.1 | WARN/ERROR | 链路文件存在且非空壳 | 至少 1 个 `## J{n}` 分节，且该分节步骤表至少 2 行数据行（1 行不构成链路）。级别见 D.0 |
| D.1.2 | ERROR | 必填列与证据完整 | 每行 `触发`/`接口`/`承载服务`/`来源` 非空；`来源` ∈ `as-built`\|`new`\|`changed`；`来源` ∈ {`as-built`,`changed`} 时「代码位置/依据」非空且形如 `文件:行`、`文件#符号` 或 `未校验（…）`；`来源` ∈ {`new`,`changed`} 时 `owning spec` 非空 |

**D.1.2 代码位置存在性**：若该路径所属仓库在根 `.flow/config.yaml` 的 services 中登记且可访问，则校验文件确实存在（不存在 → ERROR）；仓库未登记或不可访问 → 仅校验格式并输出 WARN 提示「未校验」。**不校验行号内容。**

**D.1.2 反自证提示**：整份文件不含任何 `as-built` 行、且本 change 并非纯新建服务时，输出 WARN 并提示「链路可能由设计推导而非代码提取」。

### D.2 与设计的交叉比对

| ID | 级别 | 检查项 | 说明 |
|----|------|--------|------|
| D.2.1 | ERROR | 变更步骤有归属 spec | 链路中 `来源` ∈ {`new`,`changed`} 的每一步，其 `owning spec` 值须在 `概要设计.md`「服务拆分（Spec 矩阵）」的 Spec 列中存在。**抓漏派** |
| D.2.2 | ERROR | 接口有调用方 | `开发文档.md` §3.2.4 接口表中「变更类型」为新增/修改的每一行，其接口 path 须在 `操作链路.md` 中至少出现一次。**抓「设计了但没人调的接口」** |
| D.2.5 | ERROR | 跨服务两侧均登记 | 链路中相邻两步 A→B 构成跨服务调用（`B.触发` = `A.承载服务` 且 `A.承载服务` ≠ `B.承载服务`）时，若 A 或 B 的 `来源` ∈ {`new`,`changed`}，则该步骤的接口 path 须出现在 §3.2.4 接口表中。**抓 BFF 与 provider 只登记一侧** |

**D.2.1 补充**：`owning spec` 填了矩阵中不存在的 `c{n}` 同样 ERROR（写错编号与漏派同等危险）。

**D.2.2 补充**：path 比对忽略路径参数占位差异（`/worker/{id}` 与 `/worker/:id` 视为同一）；无法判定时降 WARN 并输出两侧原文。

**D.2.2 例外**：§3.2.4 中「变更类型」为「不变」的行不参与本检查（design 阶段 §3.2.4 不应含此类行，见 E.2）。

### D.3 检测方法

- 只读三份文件：`操作链路.md`、`概要设计.md`、`开发文档.md`；代码位置存在性按 D.1.2 降级规则处理
- 报 ERROR 须同时给出链路侧位置（`J{n} 步骤 {#}`）与设计侧位置（`概要设计.md` 矩阵行 / `开发文档.md` §3.2.4 行）
- **不得**自动编辑或补写 `操作链路.md`

---

## §E 设计文档一致性（ERROR / WARN）

**仅 `verify_mode=design` 时执行。** 只读；不读取产品 PDF 全文做语义比对；不编辑产物。

读取 `.flow/changes/{change}/概要设计.md`、`开发文档.md`；对每个 task spec-id 读取对应服务 `openspec/changes/{spec-id}/design.md` 与 `specs/**/*.md`。
读取根 `.flow/config.yaml` 解析 `apifox_required`（默认 false）。

### E.0 可比对字段（E.3 用）

以下字段若在 **开发文档 §2 / §3.2.1** 与 **子 OpenSpec design/delta spec** 中**同时出现**，须字面或枚举含义一致（允许同义缩写但禁止矛盾数值/状态）：

- 审核/业务状态码（如 `status=2`、待审/通过/拒绝）
- 类型枚举（如 `type=3`、`type=9`）
- 主体/维度约束（company、org、contract type 等）
- pass/拒绝/写库路径的关键节点名（与 pass 决策表或 §3.2.1 规则对应）

无法确定是否指同一概念时降 WARN 并输出两侧原文，不强行 ERROR。

### E.1 Apifox 链接

| ID | 级别 | 检查项 | 说明 |
|----|------|--------|------|
| E.1 | WARN/ERROR | 新增/修改 REST 接口 Apifox 待录入 | §3.2.4 中「变更类型」为新增/修改的行，Apifox 列为「待录入」「待补充」或空 → WARN；根 config `apifox_required: true` 时升 **ERROR** |

### E.2 接口表范围

| ID | 级别 | 检查项 | 说明 |
|----|------|--------|------|
| E.2 | ERROR | §3.2.4 只列变更接口 | 接口表不得含「变更类型」为无变更/不变/现网/沿用现网 等的行；既有接口说明放 §3.2.3 或概要设计，不进 §3.2.4 |

### E.3 开发文档与 OpenSpec

| ID | 级别 | 检查项 | 说明 |
|----|------|--------|------|
| E.3 | ERROR | §2/§3.2.1 与 OpenSpec 可比对字段矛盾 | 按 E.0 规则；报 ERROR 须引用开发文档位置与子 OpenSpec 位置 |

### E.4 范围与非目标

| ID | 级别 | 检查项 | 说明 |
|----|------|--------|------|
| E.4 | ERROR | 非目标与 task/矩阵矛盾 | 概要设计「非目标」或 §2 明确排除的能力，仍出现在 Spec 矩阵、`task.md` 开发顺序或 §3.2.4 新增/修改接口中 |

### E.5 接口表重复

| ID | 级别 | 检查项 | 说明 |
|----|------|--------|------|
| E.5 | WARN | 同一 HTTP path 多行 | §3.2.4 中同一 path（忽略 query 差异）出现多行；仅 query/参数说明不同时提示合并或澄清 |

### E.6 歧义裁决兜底

| ID | 级别 | 检查项 | 说明 |
|----|------|--------|------|
| E.6 | ERROR | 裁决与 OpenSpec 不一致 | 存在 `## 歧义裁决` 时，「裁决」列表述须在对应 OpenSpec 或概要设计验收标准中可找到一致表述；与 C.2.3 互补，C.2.3 已 ERROR 时不重复报 E.6 |

### E.7 检测方法

- **只读**；不得自动编辑/修复产物
- 不读取产品 PDF 全文

---

## §F SQL 数据访问门禁（ERROR）

**设计契约仅 `verify_mode=design` 执行 F.1–F.3；运行时 EXPLAIN 仅 `verify_mode=release` 执行 F.1–F.4。**
design 阶段不得伪造运行时计划；但缺少本应存在的契约时不得派发。release 阶段缺证据时不得归档。

### F.1 查询风险判定

根 `概要设计.md` 必须有 `## 数据访问契约`：新增或修改列表、分页、报表 SQL，或改变 JOIN / 选行 / 过滤时，须有风险行；没有此类查询时须明确写「无」。

若对应 OpenSpec `design.md` 或 delta spec 出现 Mapper、SQL、分页、列表、报表、JOIN、子查询、`max/min`、`EXISTS/IN`、`LIKE`、`GROUP BY` 等查询信号，而根契约写「无」或缺失风险行，输出 **ERROR**。

### F.2 契约完整性

每个风险行必须具备以下内容，任一缺失为 **ERROR**：

- 查询入口；主表过滤键；每个 JOIN 的等值键。
- 期望基数与选行语义；`max/min`、去重或相关子查询若允许，须有明确业务语义，禁止以 id 大小臆断「最新」。
- 唯一约束或可用索引左前缀的依据。
- 同字段/同查询的跨服务参考实现；未找到参考实现时记录已检索服务与结论，偏离时同时写理由。
- 风险形态，以及最终列表 SQL 和分页 count SQL 的 EXPLAIN 验收条件。

### F.3 向 OpenSpec 传导

每个涉及 SQL 风险的 OpenSpec `design.md` 必须带本 spec 适用的契约行、允许/禁止 SQL 形态和 Mapper 契约测试要求；与根契约的 JOIN 键、过滤条件、选行优先级或参考实现相矛盾为 **ERROR**。

### F.4 发布 EXPLAIN 证据

每个风险行的 `发版记录.md`「SQL 风险与 EXPLAIN 证据」和 `.flow/changes/<change>/集成测试.md` 必须可定位到：最终绑定后的列表 SQL、框架生成的分页 count SQL、只读 EXPLAIN 文本或 JSON、代表性参数/数据量、环境与时间、验收结论及回滚方案。缺任一项为 **ERROR**。

非预先批准豁免的 `DEPENDENT SUBQUERY`，或关键大表 `ALL` 扫描，为 **ERROR**；豁免必须写明索引/容量边界、风险接受人和失效后的回滚动作。不得以 Mapper 源码、普通 API 断言或小样本计划替代最终分页 count 的 EXPLAIN。

---

## 不在本清单范围

- 跨服务 `api.md` / `{provider}-api.md` 契约比对 → Claude `/flow:verify`
- 运行时业务是否正确、验收是否通过 → `flow-codex-test` / 联调
- 代码是否违背设计 → `flow-codex-review`（apply 后）
- 单元测试是否充分 → apply/report 阶段
- §C 不判断：SQL 正确性、性能、安全 exploit、KB 正文业务是否过时
- BFF 接口是否应归 aggregator → design Spec 矩阵（结构归 §A；语义归 design 产出 + §C 领域概念）
- §D 不判断：链路设计得对不对、期望结果是否符合产品预期、既有方法的运行时前置条件（如某方法要求某字段非空）→ 归 `flow-codex-test` / 联调
- §D 不生成集成测试用例 → 归 `flow-codex-test-design`
- §D 不校验代码位置的行号内容是否真的对应该接口（仅校验文件存在性）
- §E 不读取产品 PDF 做全文语义比对；SQL 契约与证据归 §F，具体代码 SQL 审查归 `flow-codex-review`

---

## Claude archive 用法

`/flow:archive` 执行前运行本清单 **§A + §B + §F** 发布 verify（**不**强制 §C/§D/§E）。有 ERROR 则停止归档。
