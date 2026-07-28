# 改动方案：设计阶段操作链路 + verify §D 链路合规

> **状态**：待实施
> **实施者**：由其他 agent 按本文 §3–§13 改 `self/skills` 仓库并提交。
> **检视者**：编排 agent（或用户指定的审核 agent）按本文 **§检视要求** 对提交做只读 PASS/REJECT，**不**替代实施者改文件。
> **前置**：`PLAN-design-verify-domain-concepts.md`（§C 设计合规）已实施。本 PLAN 在其之上增加 **§D**，**不改动 §C 任何检查项**。
> **背景与决策摘要**：见 **§0**。

---

## 0. 背景

### 0.1 问题从哪来

需求 **广火工价登记审批**（`guanghuo-wage-register-audit`）在 2026-07-16 声明 design/spec 完成，07-17 起联调。至 07-22 累计 20+ 项联调修正（见业务项目 `.flow/changes/guanghuo-wage-register-audit/复盘-20260722-联调修正.md`），**复盘之后又发生 12 次 commit**，其中 7 项为功能性修正。

把两段合起来看，问题分成性质不同的两类：

| | 上半场（07-17 ~ 07-21） | 下半场（07-22 ~ 07-24） |
|---|---|---|
| 典型 | c16/c19/c20 首派遗漏、BFF 字段不齐、DTO 写错服务 | 与既有代码运行时契约冲突（前置状态拦截、异常分支未回滚、必填字段未装载） |
| 本质 | **设计与代码现实对不上** | **设计对了，但踩到既有实现的隐藏前置条件** |
| 可静态发现 | **是** | 否，需运行时 |

**本 PLAN 只解决上半场。** 下半场归路径级集成测试，不在本文范围（见 §0.5）。

上半场的共性根因：

| 现象 | 根因 |
|------|------|
| 设计出 `component/enter` 一类接口，前端从未调用 | 设计**没有从真实调用方出发**，凭需求文档推导接口 |
| GJG 待审分流、PC 三节点批量等场景漏派 spec | 需求覆盖的**用户路径未被穷举**，只覆盖了主干 |
| BFF 与 provider 两侧字段/路径不一致 | 跨服务调用**只登记了一侧** |

### 0.2 §C 为何拦不住这类

`PLAN-design-verify-domain-concepts.md` 落地的 §C 检查的是**概要设计内部自洽**：领域概念是否定义、歧义是否裁决、术语是否向下传导到 OpenSpec。

它的全部输入都是 **design 阶段自己产出的文档**。当 design 从头到尾对某条用户路径没有认知时，§C 读到的是一份「内部完全自洽、但缺了一整块」的设计——**自洽性检查无法发现缺失**。

`component/enter` 就是典型：领域概念写得清清楚楚、pass 决策表也有、术语传导也一致，唯独没人问「这个接口谁调」。

要发现这类缺失，必须引入一个 **design 之外的、不受 design 影响的信息源**。代码现实（前端调了什么、BFF 转发到哪）就是这个源。

### 0.3 防自证：本方案成立的唯一前提

如果「操作链路」由 AI 从需求文档和概要设计推导出来，它就只是设计的另一种表述，§D 会退化成「设计和设计自己比对」，一个问题都拦不住。

因此 **`as-built` 行必须来自代码检索，且必须留下 `文件:行` 级证据**。这是硬约束，写进 design skill 与 §D 检查项（D.1.2）。凭空写 `as-built` 行、或代码位置留空，视为方案失效。

### 0.4 方案决策（本 PLAN 要落地的）

| 决策 | 内容 | 备选与否决理由 |
|------|------|----------------|
| D1 | 新增 change 级产物 `操作链路.md`（模板 + design 强制产出） | 备选「沉进 KB 产品线层」：链路 80% 跨 change 稳定，长期应进 KB；但检查项尚未验证，先单 change 试点，验证后再迁（见 §13 阶段 C） |
| D2 | `flow-codex-verify` 的 **`verify_mode=design`** 增加 **§D**，即 §A + §C + §D | 不新增 mode，避免 design 阶段要跑两次 verify |
| D3 | §D **只收录机器可判项**（4 项，全 ERROR）；需要产品/测试主观判断的检查项本版**不做** | 用户已明确选 `objective_only`。理由：D.2.1/D.2.2/D.2.5 判据全是代码与文档的客观事实，一个人 + AI 即可产出，不依赖跨角色协作 |
| D4 | 模板保留 `期望结果` 选填列，**§D 不校验** | 为阶段 B（接入 test-design）预留，避免将来改模板返工 |
| D5 | `assign` 门禁扩展为 §A / §C / §D 任一 ERROR 即停止派发 | 与 §C 现有门禁同一处，不新增拦截点 |
| D6 | `flow-codex-review`、`flow-codex-test-design`、`flow-codex-kb` **不改** | 链路本版无断言信息，接 test-design 会产出空壳映射表；KB 迁移属阶段 C |

### 0.5 本 PLAN 不解决什么

- **不解决运行时契约类缺陷**（既有方法的隐藏前置条件、异常分支未回滚、精度/枚举问题）。这类只能靠路径级集成测试，属独立议题。
- 不自动补写已有 change（如广火）的 `操作链路.md`；仅提供模板与 §D 规则，业务项目补写另开任务。
- §D 不判断链路「设计得对不对」，只判断**链路与设计、链路与代码事实是否对得上**。
- 不生成测试用例、不跑集成测试、不写 KB、不审 Java 代码。
- 不改动 §C 任何检查项与 `overview-design.md.tmpl` 已有章节。

---

## 检视要求

> **受众**：对用户承诺「检视实施 agent 提交」的审核 agent。
> **原则**：只读；对照 **本文 PLAN** 与 **实际 diff**；输出 **`[PLAN_REVIEW] PASS`** 或 **`[PLAN_REVIEW] REJECT`** + 可执行问题列表。

### 检视输入（实施 agent 必须提供）

| # | 交付物 | 缺则 |
|---|--------|------|
| I1 | 改动文件完整列表或 `git diff` / PR 链接 | REJECT |
| I2 | `codex/validate.ps1` 执行结果（PASS 或失败日志） | 失败 → REJECT |
| I3 | 简要说明：P0 五处各自是否已改、P1 做了哪些 | 缺 P0 → REJECT |
| I4 | `codex/install.ps1 -WhatIf` 输出，确认 `操作链路.md.tmpl` 会被安装到 `flow-codex-core/assets/templates/` | 缺 → WARN |
| I5 | dry-run 结果（见 §12.2）：广火补写链路后 §D 输出摘要 | 缺 → WARN；**D.2.2 未触发且未说明原因 → REJECT** |

### 一票否决（任一成立即 REJECT）

| ID | 条件 |
|----|------|
| V1 | 修改了 `codex/skills/flow-codex-review/**` |
| V2 | **默认** verify 行为被破坏：`verify_mode=format` 仍须**仅 §A**；`verify_mode=full` / test·archive 前置仍须**仅 §A+§B**，不得跑 §C 或 §D |
| V3 | P0 五处（§3 表）有遗漏，或未实质落实本文 §4–§8 要点 |
| V4 | `verify-checklist.md` 与 `flow-codex-verify/SKILL.md` 对**四层分层**或**三种 `verify_mode`**表述不一致 |
| V5 | `flow-codex-design` / `flow-codex-assign` / `flow-codex-verify` 对「assign 前 design verify 覆盖 §A+§C+§D」表述不一致 |
| V6 | `codex/validate.ps1` 失败且未修复 |
| V7 | 在 verify skill 中增加「自动编辑/修复产物」指令（须保持只读） |
| V8 | §D 引入了**需要产品/测试主观填写才能判定**的检查项（本版 scope 为 `objective_only`；`期望结果` 列必须是选填且不被校验） |
| V9 | 修改了 `codex/skills/flow-codex-test-design/**` 或 `codex/skills/flow-codex-kb/**`（本版明确不动，避免与阶段 B/C 冲突） |
| V10 | 改动了 §C 已有检查项编号或语义，或删改 `overview-design.md.tmpl` 已有章节 |
| V11 | `as-built` 行的代码位置要求被弱化为可选（破坏 §0.3 防自证前提） |

### P0 逐项检视清单

#### P0-1 `flow/templates/操作链路.md.tmpl`（新建）

- [ ] 文件存在于 `flow/templates/`（**不是** `codex/skills/flow-codex-core/assets/templates/`，后者由 install 生成）
- [ ] 含链路分节结构（`## J{n} {标题}` + 入口说明 + 步骤表）
- [ ] 步骤表必填列齐全：`#`、`触发`、`接口`、`承载服务`、`来源`、`代码位置/依据`、`owning spec`（见 §4.2）
- [ ] `期望结果` 为**选填列**，模板中明确标注「§D 不校验」
- [ ] 模板正文含 §0.3 防自证规则原文（`as-built` 必须来自代码检索）
- [ ] 含「触发」列取值说明：页面/动作、调用方服务名、`定时任务:x`、`MQ:topic`
- [ ] 含 §D 检索标题约定，与 checklist §D 一致

#### P0-2 `flow/templates/verify-checklist.md`

- [ ] 文首由**三层**改为**四层**（§A / §B / §C / §D）
- [ ] 调用模式表「设计合规」行由 `§A + §C` 改为 `§A + §C + §D`
- [ ] 第 19 行附近「`flow-codex-assign` 前须 **§A + §C**」同步改为 `§A + §C + §D`
- [ ] 新增 `## §D 链路合规`，含 **D.1.1 / D.1.2 / D.2.1 / D.2.2 / D.2.5** 五项（编号见 §5.2；**D.2.3 / D.2.4 有意留空**，须在文中注明「预留给阶段 B」）
- [ ] 含降级规则：缺 `操作链路.md` 时 D.1.1 为 WARN、其余 SKIP；`journey_required: true` 时升 ERROR
- [ ] 「不在本清单范围」已按 §5.4 补 §D 边界
- [ ] archive 用法段落仍为 **全量 = §A+§B**，未被改成含 §D

#### P0-3 `codex/skills/flow-codex-verify/SKILL.md`

- [ ] frontmatter `description` 体现 design 模式覆盖链路合规
- [ ] 调用模式表「设计合规」行 = `§A + §C + §D`，与 checklist 一致
- [ ] 「检查范围」新增第 4 条 §D
- [ ] 新增「§D 链路合规」段，含：防自证规则、代码位置存在性校验的降级策略、`journey_required` 开关、输出格式 `[ERROR|WARN|PASS] D.x.x: …`
- [ ] 明确 §D 只读、不编辑产物、不判断链路设计对错
- [ ] 「不在范围」补：§D 不验证运行时行为、不生成测试用例

#### P0-4 `codex/skills/flow-codex-design/SKILL.md`

- [ ] 根模式新增**步骤 3.5「现状链路提取」**（原步骤 4 起编号顺延或保持 3.5 小数编号，二选一但须全文一致）
- [ ] 3.5 明确：从入口端/页面出发做代码检索；前端仓不在 `.flow/config.yaml` 时允许用户提供路径，否则该行标注未校验；**禁止仅凭需求文档臆造 `as-built` 行**
- [ ] 步骤 4 产出物清单加入 `操作链路.md`，并要求先读 `../flow-codex-core/assets/templates/操作链路.md.tmpl`
- [ ] 步骤 5 自检 blocked 项新增本文 §7.3 的三条
- [ ] 步骤 8 文案由 `§C ERROR` 改为 `§C 或 §D ERROR`
- [ ] 服务模式：子 spec 不得改根 `操作链路.md`（变更走 `flow-codex-change`）

#### P0-5 `codex/skills/flow-codex-assign/SKILL.md`

- [ ] 派发前检查第 4 项由「§C 或 §A ERROR」改为「§A、§C 或 §D ERROR」
- [ ] WARN 文案与 verify skill 一致

### P1 / P2 检视（缺失不必然 REJECT，须在结论中标注）

| 项 | 期望 |
|----|------|
| P1 `flow-codex-change` | 变更涉及接口增删/路径变化时 MUST 同步 `操作链路.md` 并重跑 design verify |
| P1 `codex/validate.ps1` | 资源存在性检查追加 `flow/templates/操作链路.md.tmpl` |
| P1 `CHANGELOG.md` | Unreleased 有条目描述本次变更 |
| P2 `AGENTS.md` / `codex/PLAN.md` | 生命周期说明提及链路产物 |
| P2 Claude 侧 | 若未改，结论注明「Codex-only；Claude 待 follow-up」 |

### 一致性交叉检查

| 检查 | 通过标准 |
|------|----------|
| 模板 ↔ §D | §D 检查的列名/标题能在 `操作链路.md.tmpl` 找到对应 |
| §D ↔ 开发文档 | D.2.2 / D.2.5 引用的 §3.2.4 列名（接口、服务、变更类型）与 `dev-doc-maintenance.md` §2 一致 |
| §D ↔ 概要设计 | D.2.1 引用的「Spec 矩阵」列名与 `overview-design.md.tmpl`「服务拆分（Spec 矩阵）」一致 |
| design ↔ assign ↔ verify | 三者均表述为 `verify_mode=design` = §A+§C+§D |
| verify ↔ archive | archive 前置仍为全量 §A+§B，**不**要求含 §C/§D |
| MAINTENANCE §0 / §3.3 | 模板只改 `flow/templates/` 源；未手改 `flow-codex-core/assets/templates/` |
| install 路径 | 未改 `install.ps1`（新模板由通配复制自动覆盖），或若改动须说明理由 |

### 回归预期

- `verify_mode=format` → 仅 §A，与改前一致
- `verify_mode=full` / test·archive 前置 → §A+§B，**不含 §C、不含 §D**
- `verify_mode=design` → §A+§C+§D
- 历史 change 无 `操作链路.md` → D.1.1 WARN，不因此阻断 assign（`journey_required` 未开启时）

### 检视输出格式

```markdown
## [PLAN_REVIEW] PASS | REJECT

**范围**：<commit/PR>
**validate.ps1**：PASS | FAIL
**dry-run D.2.2**：触发 | 未触发（原因：…）

### P0
- [PASS|REJECT] P0-1 操作链路.md.tmpl: …
- …

### P1/P2
- [PASS|WARN|SKIP] …

### 一票否决
- V1–V11：无 | 触发 Vx：…

### 问题（REJECT 时必填）
1. <文件>:<行或节> — <与 PLAN 哪条不符> — <实施 agent 应如何改>

### 备注
- …
```

**PASS 条件**：无一票否决；P0 全部 PASS；P1 缺失仅 WARN；dry-run D.2.2 触发或已说明合理原因。

---

## 1. 目标与非目标

### 1.1 目标

| # | 目标 |
|---|------|
| G1 | design 阶段强制产出 `操作链路.md`，其中 `as-built` 部分**来自代码检索**而非文档推导 |
| G2 | `verify_mode=design` 增加 §D，用「链路 ↔ 设计 ↔ 代码事实」三方比对发现设计缺失 |
| G3 | §D 只含机器可判项，不依赖产品/测试参与即可运行 |
| G4 | `assign` 前置门禁扩展到 §D |
| G5 | 模板为阶段 B（接入 test-design）与阶段 C（沉入 KB）预留扩展位，不返工 |

### 1.2 非目标

- 不检查链路本身的业务正确性（那需要产品视角，属阶段 B）
- 不替代路径级集成测试；运行时契约类缺陷仍会漏
- 不替代 §C（领域概念）与 Claude 侧跨服务 `api.md` 契约 verify
- 不自动生成链路（半自动脚本属 P2 可选，见 §13）

---

## 2. 职责边界（实施后）

```text
flow-codex-design
  → 步骤 3.5：从代码提取 as-built 链路（新增）
  → 步骤 4：产出 概要设计 / 开发文档 / task / 发版记录 / 操作链路（新增）
  → 步骤 5：Spec 粒度 + 领域概念 + 链路自检（扩充）

flow-codex-verify
  → format：§A（不变）
  → design：§A + §C + §D（扩充）
  → full（test/archive 前置）：§A + §B（不变）

flow-codex-assign
  → 前置：OpenSpec apply-ready + design verify 无 §A/§C/§D ERROR

flow-codex-change
  → 接口增删/路径变化时同步链路（P1）

flow-codex-review / test-design / kb（本版不改）
```

---

## 3. 涉及文件清单

| 优先级 | 文件 | 动作 |
|--------|------|------|
| P0 | `flow/templates/操作链路.md.tmpl` | **新建**（§4 全文） |
| P0 | `flow/templates/verify-checklist.md` | 三层→四层；调用模式表；新增 §D；更新「不在范围」 |
| P0 | `codex/skills/flow-codex-verify/SKILL.md` | description、调用模式表、检查范围、新增 §D 段、不在范围 |
| P0 | `codex/skills/flow-codex-design/SKILL.md` | 新增步骤 3.5；步骤 4 产出物；步骤 5 blocked；步骤 8 文案；服务模式约束 |
| P0 | `codex/skills/flow-codex-assign/SKILL.md` | 派发前检查第 4 项扩展到 §D |
| P1 | `codex/skills/flow-codex-change/SKILL.md` | 接口变化时同步链路 |
| P1 | `codex/validate.ps1` | 追加 `操作链路.md.tmpl` 存在性检查 |
| P1 | `CHANGELOG.md` | Unreleased 条目 |
| P2 | `AGENTS.md` / `codex/PLAN.md` | 生命周期提及链路产物 |
| P2 | `.claude/skills/flow-design/SKILL.md` 等 | Claude 侧对齐（可 follow-up） |
| — | `codex/skills/flow-codex-review/**` | **不修改** |
| — | `codex/skills/flow-codex-test-design/**` | **不修改** |
| — | `codex/skills/flow-codex-kb/**` | **不修改** |
| — | `codex/install.ps1` | **不需要改**：`flow/templates/` 下所有文件由通配复制自动安装 |

---

## 4. 新模板 `flow/templates/操作链路.md.tmpl`

### 4.1 设计要点

- **一个文件多条链路**，按 `## J{n} {标题}` 分节，便于 §D 定位与后续按链路派测试
- **一行 = 一次接口调用**。跨服务调用天然表现为相邻两行（上一行的「承载服务」= 下一行的「触发」），无需单列「下游服务」
- 纯内部调用（Feign / 定时任务 / MQ）同样占一行，「触发」填调用方。**这样就不需要维护「内部接口豁免清单」——一个新接口如果连内部调用方都写不出来，本来就该报错**
- `期望结果` 选填，本版不校验，为阶段 B 预留

### 4.2 模板全文

````markdown
# {{requirement_title}} — 操作链路

> 本文件由 `/flow:design`（根模式，步骤 3.5–4）生成，位于 `.flow/changes/{change-name}/操作链路.md`。
> §D 检索标题：`## J{n} …`（链路分节）。

---

## 为什么要有这份文档

概要设计描述「我们打算做什么」，本文件描述「用户/上游实际会走哪条路，这条路上每一跳打到谁」。
两者由**不同信息源**产出，才能互相校验：设计漏掉的路径、设计出来但没人调的接口，只有在这里能被发现。

## 硬约束（违反即方案失效）

1. **`来源=as-built` 的行必须来自代码检索**，并在「代码位置/依据」列留下 `文件:行` 或 `文件#符号` 级证据。
   **禁止**仅凭需求文档、概要设计或记忆推导 `as-built` 行。
2. `来源=changed` 同样须给出被改动位置的代码依据。
3. 拿不到前端/上游代码时，写 `未校验（原因）`，**不要**猜一个路径填进去。
4. 本文件只记录**事实与本次要新增的事实**，不记录设计理由（理由在概要设计）。

## 列取值约定

| 列 | 取值 |
|----|------|
| `#` | 链路内步骤序号，从 1 递增 |
| `触发` | 页面/动作（如 `GJG小程序·扫码进场页·点击提交`）、或调用方服务名、或 `定时任务:{名称}`、或 `MQ:{topic}` |
| `接口` | `METHOD /path`，与开发文档 §3.2.4 写法一致 |
| `承载服务` | **恰好一个可部署服务**（非 git 仓库名），与开发文档 §4.1 口径一致 |
| `来源` | `as-built`（本次不改的既有链路）\| `new`（本次新增）\| `changed`（本次修改） |
| `代码位置/依据` | `as-built`/`changed` 必填：`文件:行`、`文件#符号`，或 `未校验（原因）` |
| `owning spec` | `new`/`changed` 必填：`c{n}`；`as-built` 填 `—` |
| `期望结果`（选填） | 用户可见现象或数据终态。**§D 不校验**，为后续集成测试设计预留 |

---

## J1 {链路标题，如：广记工扫码登记进场}

**入口**：{端 + 页面 + 用户动作}
**前置**：{进入本链路的前提，选填}

| # | 触发 | 接口 | 承载服务 | 来源 | 代码位置/依据 | owning spec | 期望结果 |
|---|------|------|----------|------|---------------|-------------|----------|
| 1 | {页面·动作} | GET /xxx | {service} | as-built | {file:line} | — | {选填} |
| 2 | {service-上一跳} | POST /yyy | {service} | new | — | c{n} | {选填} |

## J2 {下一条链路}

…

---

## 边界 / 异常链路（推荐，§D 不强制）

拒绝、超时、下游失败、重复提交等分支建议单列为 `## J1-E1 …`。
本版 §D 不校验，但填了对后续集成测试设计有直接价值。

## 未覆盖说明

{本次需求涉及但未纳入链路的入口，及原因。无则写「无」}
````

---

## 5. `verify-checklist.md` 改动

### 5.1 文首分层（替换现有三层表述）

```markdown
本清单分四层：

- **§A 产物格式**（结构/格式，不判业务语义）
- **§B 发布就绪**（完成度与 git 状态；仅全量 verify）
- **§C 设计过程合规**（领域概念与向下传导；仅 `verify_mode=design`）
- **§D 链路合规**（操作链路与设计/代码事实比对；仅 `verify_mode=design`）

| 调用模式 | 章节 |
|----------|------|
| 格式复验（默认轻量） | §A |
| 设计合规（`verify_mode=design`） | §A + §C + §D |
| 全量 verify（test/archive） | §A + §B（**不**默认跑 §C/§D；assign 前单独跑 design 模式） |
```

同步修改其后一句：

```diff
- `flow-codex-assign` 前须 **§A + §C**（`verify_mode=design`）且无 ERROR。
+ `flow-codex-assign` 前须 **§A + §C + §D**（`verify_mode=design`）且无 ERROR。
```

### 5.2 新增 `## §D 链路合规`

置于 §C 之后、「不在本清单范围」之前。

````markdown
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

**D.2.2 例外**：§3.2.4 中「变更类型」为「不变」的行不参与本检查。

### D.3 检测方法

- 只读三份文件：`操作链路.md`、`概要设计.md`、`开发文档.md`；代码位置存在性按 D.1.2 降级规则处理
- 报 ERROR 须同时给出链路侧位置（`J{n} 步骤 {#}`）与设计侧位置（`概要设计.md` 矩阵行 / `开发文档.md` §3.2.4 行）
- **不得**自动编辑或补写 `操作链路.md`
````

### 5.3 输出格式段落

现有「输出格式」段落中一句需扩展：

```diff
- design 模式存在 **ERROR** 时不可 `flow-codex-assign`。
+ design 模式（§A+§C+§D）存在 **ERROR** 时不可 `flow-codex-assign`。
```

### 5.4 更新「不在本清单范围」

追加：

```markdown
- §D 不判断：链路设计得对不对、期望结果是否符合产品预期、既有方法的运行时前置条件（如某方法要求某字段非空）→ 归 `flow-codex-test` / 联调
- §D 不生成集成测试用例 → 归 `flow-codex-test-design`
- §D 不校验代码位置的行号内容是否真的对应该接口（仅校验文件存在性）
```

### 5.5 Claude archive 用法段落

保持不变（**全量 = §A + §B**，不含 §C/§D）。检视时确认未被误改。

---

## 6. `flow-codex-verify/SKILL.md` 改动要点

### 6.1 description（frontmatter）

```yaml
description: 只读检查 Flow 根产物格式与发布就绪；可选 design 模式校验设计过程合规（领域概念、OpenSpec 传导、操作链路与设计一致性）。不验证运行时行为与跨服务 api.md 契约。
```

### 6.2 调用模式表

| 模式 | 参数 | 执行章节 | 时机 | ERROR 阻断 |
|------|------|----------|------|------------|
| **格式复验** | 默认 / `verify_mode=format` | §A | design 后可选 | 仅当调用方声明为门禁时 |
| **设计合规** | `verify_mode=design` | §A + §C + §D | design 完成 → **assign 前强制** | assign |
| **全量 verify** | `verify_mode=full` 或 test/archive 前置 | §A + §B | test / archive | test / archive |

其后一句同步为：

```markdown
格式复验时 §B / §C / §D 未完成属正常，不得因此报 ERROR。全量 verify **不**默认跑 §C / §D。design 模式 **不**跑 §B。
```

### 6.3 检查范围新增第 4 条

```markdown
4. **§D 链路合规**（见 checklist §D，仅 `verify_mode=design`）：操作链路结构与证据、变更步骤归属 spec、接口有调用方、跨服务两侧登记
```

### 6.4 新增段落「§D 链路合规」

```markdown
## §D 链路合规

- 读取 `.flow/changes/{change}/操作链路.md`、`概要设计.md` Spec 矩阵、`开发文档.md` §3.2.4
- **防自证**：`as-built` 行须带代码位置证据。整份文件无 `as-built` 行且非纯新建服务时输出 WARN
- 代码位置存在性：仓库在根 `.flow/config.yaml` 登记且可访问时校验文件存在；否则仅校验格式并标注「未校验」
- 缺 `操作链路.md`：默认 D.1.1 WARN、其余 SKIP；根 config 设 `journey_required: true` 时 D.1.1 升 ERROR。文件存在时 D.1.2/D.2.* 一律 ERROR
- 报 ERROR 须同时给出链路侧（`J{n} 步骤 {#}`）与设计侧（矩阵行 / §3.2.4 行）位置
- 输出格式与 §A 相同：`[ERROR|WARN|PASS] D.x.x: …`
- **只读**：不补写链路、不编辑产物、不判断链路业务正确性
```

### 6.5 「不在范围」补充

```markdown
- §D：不验证运行时行为与既有方法的隐藏前置条件、不生成测试用例（归 `flow-codex-test-design` / `flow-codex-test`）
```

---

## 7. `flow-codex-design/SKILL.md` 改动要点

### 7.1 新增步骤 3.5「现状链路提取」

置于现有步骤 3（查询 Apifox）与步骤 4（创建产物）之间：

```markdown
3.5 **现状链路提取**（产出 `操作链路.md` 的 `as-built` 部分）。
   - 先读 `../flow-codex-core/assets/templates/操作链路.md.tmpl`。
   - 从需求涉及的**入口端**（小程序/H5/PC 页面、定时任务、上游 MQ）出发，用代码检索逐跳还原调用链：入口调了哪个接口 → 该接口由哪个可部署服务承载 → 它又调了谁。
   - 每个 `as-built` 步骤 **MUST** 记录 `文件:行` 或 `文件#符号` 级依据。
   - 前端/上游仓库不在根 `.flow/config.yaml` 时，向用户索取路径；拿不到则该行写 `未校验（原因）`。
   - **禁止**仅凭需求文档、概要设计或既有认知推导 `as-built` 行——这会使后续 §D 退化为设计自证。
   - 纯新建服务且无既有链路时，可无 `as-built` 行，但须在「未覆盖说明」写明。
```

### 7.2 步骤 4 产出物

在「创建或修复 `.flow/changes/<change_name>/…`」文件列表中加入 `操作链路.md`，并追加子项：

```markdown
   - 生成 `操作链路.md` 前读取 `../flow-codex-core/assets/templates/操作链路.md.tmpl`。
   - 在步骤 3.5 的 `as-built` 基础上补 `new` / `changed` 步骤，每步填 `owning spec`（与 Spec 矩阵一致）。
   - §3.2.4 每条「新增/修改」接口都必须能在链路中找到调用方；找不到时**先回头质疑该接口是否真的需要**，不要为通过检查而编造调用方。
```

### 7.3 步骤 5 自检 blocked 新增三条

在现有 blocked 列表末尾追加：

```markdown
     - `操作链路.md` 缺失，或无任何 `as-built` 行而本 change 并非纯新建服务
     - 开发文档 §3.2.4 存在「新增/修改」接口未在 `操作链路.md` 中出现
     - 链路中 `new`/`changed` 步骤的 `owning spec` 为空，或不在 Spec 矩阵中
```

### 7.4 步骤 8 文案

```diff
- 8. 提示用户或根 agent 执行 `flow-codex-verify`（`verify_mode=design`）。存在 §C ERROR 时不得声明 design 完成。
+ 8. 提示用户或根 agent 执行 `flow-codex-verify`（`verify_mode=design`，覆盖 §A+§C+§D）。存在 §C 或 §D ERROR 时不得声明 design 完成。
```

### 7.5 服务模式

在末段追加：

```markdown
子 spec **不得**修改根 `操作链路.md`。发现链路与实际实现不符时，向根 agent 报告，由 `flow-codex-change` 统一更新。
```

---

## 8. `flow-codex-assign/SKILL.md` 改动要点

派发前检查第 4 项替换：

```diff
- 4. 对本 change 执行 `flow-codex-verify`（`verify_mode=design`）。存在 §C 或 §A ERROR 时停止派发；WARN 须向用户说明并获确认后继续。
+ 4. 对本 change 执行 `flow-codex-verify`（`verify_mode=design`，覆盖 §A+§C+§D）。存在 §A、§C 或 §D ERROR 时停止派发；WARN 须向用户说明并获确认后继续。
```

不新增 config 开关（`journey_required` 由 verify 侧读取，assign 不重复判断）。

---

## 9. P1 改动

### 9.1 `flow-codex-change/SKILL.md`

在末段追加：

```markdown
**链路同步**：变更涉及接口新增/删除、路径变化或调用方变化时，**MUST** 同步更新 `操作链路.md`（新增步骤标 `new`/`changed` 并填 `owning spec`；废弃步骤删除或标注），并重跑 `flow-codex-verify`（`verify_mode=design`）确认 §D 无 ERROR。
```

### 9.2 `codex/validate.ps1`

在现有共享模板检查附近（第 106–108 行 `$sharedTemplatesDir` 检查之后）追加：

```powershell
@(
    (Join-Path $sharedTemplatesDir "操作链路.md.tmpl")
) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) {
        $errors += "Missing journey template: $_"
    }
}
```

> 注意仓库中已有中文文件名模板（`开发文档模板.md.tmpl`），脚本以 UTF-8 读取，路径拼接方式与现有 feedback 资源检查一致即可。

### 9.3 `CHANGELOG.md`

`## [Unreleased]` → `### Added` 追加：

```markdown
- **设计阶段操作链路 + verify §D**：新增 `flow/templates/操作链路.md.tmpl`（一行一次接口调用，`as-built` 行须带 `文件:行` 证据）；`verify-checklist.md` 新增 §D（D.1.1/D.1.2/D.2.1/D.2.2/D.2.5，全 ERROR）；`verify_mode=design` 扩展为 §A+§C+§D；`flow-codex-design` 新增步骤 3.5 现状链路提取与三条 blocked 自检；`flow-codex-assign` 门禁扩展到 §D；`flow-codex-change` 接口变化时同步链路。缺链路文件时默认 WARN（根 config `journey_required: true` 可升 ERROR），文件存在时 §D 全项 ERROR。默认 format / 全量 verify（§A+§B）行为不变；`flow-codex-review` / `test-design` / `kb` 未改。Claude 侧待 follow-up。
```

---

## 10. 明确不改动

| 项 | 说明 |
|----|------|
| `flow-codex-review` | 仍为 apply 后代码 vs OpenSpec `design.md` |
| `flow-codex-test-design` | 本版链路无 `期望结果` 强制列，接入会产出空壳映射表；属阶段 B |
| `flow-codex-kb` | 链路沉入 KB 属阶段 C |
| `overview-design.md.tmpl` | §C 四节保持原样，不因链路而改 |
| `codex/install.ps1` | 新模板由 `flow/templates/` 通配复制自动安装 |
| §C 全部检查项 | 编号与语义不动 |

---

## 11. 实施顺序

```text
1. flow/templates/操作链路.md.tmpl          # 结构先行
2. flow/templates/verify-checklist.md       # §D 全文 + 四层分层
3. codex/skills/flow-codex-verify/SKILL.md
4. codex/skills/flow-codex-design/SKILL.md
5. codex/skills/flow-codex-assign/SKILL.md
6. codex/skills/flow-codex-change/SKILL.md + codex/validate.ps1
7. CHANGELOG.md（+ P2 AGENTS.md / codex/PLAN.md）
8. 跑 codex/validate.ps1
9. codex/install.ps1 -WhatIf 确认新模板会被安装，再正式 install
10. 业务项目 dry-run（见 §12.2）
```

---

## 12. 验收与 dry-run

### 12.1 skills 仓库

- [ ] `codex/validate.ps1` 通过
- [ ] `codex/install.ps1 -WhatIf` 输出含 `操作链路.md.tmpl`
- [ ] checklist 四层结构自洽；archive 段落仍只引用 §A+§B
- [ ] design / assign / verify 三者对 `verify_mode=design` = §A+§C+§D 表述一致
- [ ] §D 中 D.2.3 / D.2.4 编号确实留空并注明预留

### 12.2 业务项目 dry-run（glm · guanghuo-wage-register-audit）

**这一步是方案是否成立的判据，不是走过场。**

1. 对 `.flow/changes/guanghuo-wage-register-audit/` 补写 `操作链路.md`，至少覆盖一条链路：**广记工小程序扫码 → 登记进场**（从 `wxmini-gjg` 扫码页出发，经 `worker-app-agg` 到 `worker-register-service`），`as-built` 行须真实检索代码填写
2. 跑 `flow-codex-verify`（`verify_mode=design`）

| 预期 | 说明 |
|------|------|
| **D.2.2 触发 ERROR** | 开发文档 §3.2.4 中登记为新增/修改、但链路中无任何调用方的接口应被报出 |
| D.2.1 大概率不触发 | 历史漏派的 spec 现已补入矩阵，无法复现 |
| D.2.5 部分可验 | 需构造历史版本才能完整复现 |
| §A / §C | 与改前一致，不得因 §D 引入而变化 |

3. 若 **D.2.2 未触发**：不得直接判 PASS。须逐项核对是否为
   - 开发文档 §3.2.4 未登记该接口（→ 检查项没问题，是文档缺失，另记）
   - path 比对逻辑失效（→ **检查项设计有问题，回炉**）
   并在检视输出中说明。

4. 反向验证：故意在链路中删掉一条 `new` 步骤的 `owning spec`，确认 D.2.1 报 ERROR；恢复后 PASS。

### 12.3 回归

- [ ] `verify_mode=format` 行为与改前一致（仅 §A）
- [ ] test / archive 前置全量仍 §A+§B，**不因缺 `操作链路.md` 而报错**
- [ ] 历史 change（无链路文件、`journey_required` 未开）→ D.1.1 WARN，assign 不被阻断

---

## 13. 风险与缓解

| 风险 | 缓解 |
|------|------|
| **又一份没人维护的文档**（KB 产品线层前车之鉴） | 只强制 `new`/`changed` 步骤 + 需求涉及的入口链路，不要求全站链路；`as-built` 由代码检索半自动产出；缺文件默认 WARN 而非 ERROR |
| **AI 编造 `as-built` 行**，§D 退化为自证 | D.1.2 强制代码位置证据 + 存在性校验；无 `as-built` 行时 WARN；design skill 明文禁止推导 |
| **D.2.2 误报**（内部 Feign、运行时拼接 URL、动态路由的前端写法） | 内部调用同样允许作为链路一行（触发填服务名），无需豁免清单；path 无法判定时降 WARN 并输出两侧原文；dry-run 观察一轮 |
| 前端仓不在 `.flow/config.yaml`，无法校验代码位置 | D.1.2 降级为格式校验 + WARN「未校验」，不 ERROR |
| 旧 change 无链路文件 | `journey_required` 默认 false；不 retroactive 卡历史 change |
| **§D 拦截范围被高估** | §0.1 与 §0.5 已写明只覆盖上半场；运行时契约类缺陷仍需集成测试，实施与检视时不得宣称 §D 覆盖该类 |
| Claude / Codex 双平台漂移 | 模板改 `flow/templates/` 单一源；Claude 侧 design 待 follow-up 并在 CHANGELOG 注明 |

### 后续阶段（本 PLAN 不实施，避免 scope 蔓延）

| 阶段 | 内容 | 前置 |
|------|------|------|
| **B** | `期望结果` 列转为条件必填；新增 D.2.3（期望结果 ↔ 领域概念）、D.2.4（链路 ↔ pass 决策表）；`flow-codex-test-design` 以链路为用例来源 | 阶段 A 跑过 ≥1 个完整需求，且有产品/测试可参与填语义列 |
| **C** | 链路 baseline 沉入 KB（`E:\local_rag` 产品线/功能域层），change 内只写 diff | 阶段 A/B 验证检查项稳定 |

---

## 14. 附录 A：`操作链路.md` 示例（广火，结构示意）

> **示例仅示形**。实施 dry-run 时「代码位置/依据」必须替换为真实检索结果，不得照抄本附录。

```markdown
## J1 广记工扫码登记进场

**入口**：GJG 小程序 · 扫码进场页 · 扫码后点击「提交登记」
**前置**：工人已完成实名认证

| # | 触发 | 接口 | 承载服务 | 来源 | 代码位置/依据 | owning spec | 期望结果 |
|---|------|------|----------|------|---------------|-------------|----------|
| 1 | GJG小程序·扫码页·进入 | GET /worker/queryByQrcode | worker-app-agg | as-built | wxmini-gjg/pages/scanQrCode.vue:{line} | — | 回显工人基本信息 |
| 2 | worker-app-agg | GET /register/worker/detail | worker-register-service | as-built | worker-app-agg/.../WorkerAggController.java:{line} | — | — |
| 3 | GJG小程序·扫码页·点击提交 | POST /worker/enter | worker-app-agg | changed | wxmini-gjg/pages/scanQrCode.vue:{line} | c16 | 提交成功并跳转 |
| 4 | worker-app-agg | POST /registerFlow/projectEnter | worker-register-service | changed | worker-app-agg/.../WorkerAggController.java:{line} | c16 | project_worker 状态置待审 |

## J1-E1 扫码登记 — 发起签署失败（边界，§D 不强制）

| # | 触发 | 接口 | 承载服务 | 来源 | 代码位置/依据 | owning spec | 期望结果 |
|---|------|------|----------|------|---------------|-------------|----------|
| 1 | worker-register-service | POST /contract/launch | contract-service | as-built | {file:line} | — | 失败时不应推进登记状态 |

## 未覆盖说明

PC 端花名册批量导入路径本次不改动，未纳入链路。
```

---

## 15. 附录 B：`verify_mode=design` 输出示例（含 §D）

```markdown
## flow-codex-verify · guanghuo-wage-register-audit · mode=design

### §A
- [PASS] A.1 根产物齐全
- [PASS] A.2 Spec 矩阵存在

### §C
- [PASS] C.1.1 领域概念节存在（8 条）
- [WARN] C.1.3 KB 引用「@feature-register」未能解析（KB 路径不可访问）

### §D
- [PASS] D.1.1 操作链路.md 存在，3 条链路
- [WARN] D.1.2 J2 步骤 1 代码位置指向 wxmini-gjg（仓库未在 config 登记，未校验）
- [ERROR] D.2.2 开发文档 §3.2.4 第 7 行 `POST /component/enter`（worker-app-agg，新增）在 操作链路.md 中无任何调用方
        → 请确认该接口是否真的需要；若确需，补出调用它的页面/服务
- [ERROR] D.2.1 操作链路.md J3 步骤 4 owning spec `c24` 不在概要设计 Spec 矩阵中（矩阵最大为 c23）
- [PASS] D.2.5 跨服务调用两侧均已在 §3.2.4 登记（4 处）

**结论**：存在 §D ERROR，不可 assign。
```

---

## 16. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-07-27 | 初稿：操作链路产物 + verify §D（objective_only 范围：D.1.1/D.1.2/D.2.1/D.2.2/D.2.5）；design 步骤 3.5 现状链路提取；assign 门禁扩展；review / test-design / kb 不改；阶段 B/C 明确后置 |
