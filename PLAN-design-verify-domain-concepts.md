# 改动方案：设计阶段领域概念 + verify §C 设计合规

> **状态**：已实施，待检视  
> **实施者**：由其他 agent 按本文 §3–§11 改 `self/skills` 仓库并提交。  
> **检视者**：编排 agent（或用户指定的审核 agent）按本文 **§检视要求** 对提交做只读 PASS/REJECT，**不**替代实施者改文件。  
> **背景与决策摘要**：见 **§0**。

---

## 0. 背景

### 0.1 问题从哪来

需求 **广火工价登记审批**（`guanghuo-wage-register-audit`，GLW-91477 等）在 **2026-07-16 前后** 声明 design/spec 完成，**07-17 起联调**，至 **07-22** 累计 **20+ 项** 联调修正（见业务项目 `.flow/changes/guanghuo-wage-register-audit/复盘-20260722-联调修正.md`）。

典型线上/联调缺陷（设计阶段本可拦截）：

| 编号 | 现象 | 根因类型 |
|------|------|----------|
| H1 | 登记预警写 `worker_on_duty_warn` vs 产品要 `worker_warn` type=9 | 纪要 **W6 vs W2 未裁决**，design 跟错分支 |
| H2 / H6 | 工区审核用任意 `worker_contract`（含纸质）比工价 | **领域概念缺失**：「腾讯电子合同」未定义为 type=3+company |
| H4 | 工区/项目 pass 在 `workerRegister` / `passWithProjectAudit` 间反复 | **pass 写库决策表缺失**，子 agent 各自发明路径 |
| H3 | c16–c22 首派遗漏或 spec 写错 | 集成范围、矩阵与纪要范围未对齐 |
| H5 | 名册/R40 与工区查询合同维度不一致 | 根概念未 **向下传导** 到各 OpenSpec |

共性：**不是 OpenSpec 结构不能 apply**，而是 **业务语义在 design 阶段未写死、无独立检视**，直到 apply/联调才暴露。

### 0.2 现有 Flow 能力为何没拦住

| 环节 | 当时能力 | 缺口 |
|------|----------|------|
| `flow-codex-design` | Spec 矩阵粒度、openspec readiness 自检 | **无**强制「领域概念 / 歧义裁决 / pass 决策表」 |
| `flow-codex-verify` §A | 文件存在、矩阵行型、OpenSpec 结构 | 明文 **不查业务语义** |
| `flow-codex-verify` §B | test/archive 发布就绪 | 与 design 阶段无关 |
| `flow-codex-review` | apply **后** 代码 vs OpenSpec `design.md` | **设计阶段不介入**；且由根 agent 派同级 agent，**不是用户命令** |
| `flow-codex-kb` | change 完成后可沉淀 | 无 design 阶段 `kb_action` 标注；「KB 建议」常未 merge |

曾讨论把 design 门禁放进 `flow-codex-review`（overview mode），结论 **否**：review 角色是 apply 后代码对照，与用户/子 agent 边界易混淆。

### 0.3 领域概念与 KB 的分工（共识）

- **领域概念**是 design 阶段必须搞清的 **单次需求语义契约**。
- 来源两类：
  1. **KB 已有**（功能域 `## 业务规则` 等）→ 概要设计 `source: kb`，OpenSpec **不得改义**；
  2. **本 change 需求分析产出** → `source: change`，标 `kb_action: 待沉淀 | 无需`，**archive 时**由 `flow-codex-kb` merge 进 KB。
- **Anti-bloat**：change 文档不充当伪 KB；稳定规则进功能域，联调修正留变更记录/复盘。

### 0.4 方案决策（本 PLAN 要落地的）

| 决策 | 内容 |
|------|------|
| D1 | **design 产出规范**：概要设计强制 `## 领域概念` 等节（见 §4） |
| D2 | **检视/enforcement**：`flow-codex-verify` 新增 **`verify_mode=design`** → §A + **§C**；**默认 verify 行为不变** |
| D3 | **assign 门禁**：派发前须 design verify 无 §C/§A ERROR |
| D4 | **kb 补充**：只处理 `source: change` + `kb_action: 待沉淀`（见 §9） |
| D5 | **`flow-codex-review` 不改** |

### 0.5 本 PLAN 不解决什么

- 不自动修正已有 change（如广火）的概要设计正文——仅提供模板与 §C 规则；业务项目补写另开任务。
- 不在 verify 里写 KB、不跑集成测试、不审 Java 代码。
- 不替代 Claude 侧跨服务 `api.md` 契约 verify。

---

## 检视要求

> **受众**：对用户承诺「检视实施 agent 提交」的审核 agent（如编排会话中的 Claude/Codex）。  
> **原则**：只读；对照 **本文 PLAN** 与 **实际 diff**；输出 **`[PLAN_REVIEW] PASS`** 或 **`[PLAN_REVIEW] REJECT`** + 可执行问题列表。

### 检视输入（实施 agent 必须提供）

| # | 交付物 | 缺则 |
|---|--------|------|
| I1 | 改动文件完整列表或 `git diff` / PR 链接 | REJECT |
| I2 | `codex/validate.ps1` 执行结果（PASS 或失败日志） | 失败 → REJECT |
| I3 | 简要说明：各 P0 文件是否已改、P1/P2 做了哪些 | 缺 P0 → REJECT |
| I4 | （推荐）对 `guanghuo-wage-register-audit` 或 mock 概要设计跑 design verify 的输出摘要 | 缺不 REJECT，但 WARN |

### 一票否决（任一成立即 REJECT）

| ID | 条件 |
|----|------|
| V1 | 修改了 `codex/skills/flow-codex-review/**` 或引入 design-phase review 到 review skill |
| V2 | **默认** verify（format / 全量 test·archive）行为被破坏：全量仍须 **仅 §A+§B**、不默认跑 §C |
| V3 | P0 五处（§3 表）有遗漏或未实质落实 PLAN 要点 |
| V4 | `verify-checklist.md` 与 `flow-codex-verify/SKILL.md` 对三种 `verify_mode` 表述 **不一致** |
| V5 | `flow-codex-design` / `flow-codex-assign` / `verify` 对「assign 前 design verify」要求 **不一致** |
| V6 | `codex/validate.ps1` 失败且未修复 |
| V7 | 在 verify skill 中增加「自动编辑/修复产物」指令（须保持只读） |

### P0 逐项检视清单

#### P0-1 `flow/templates/overview-design.md.tmpl`

- [ ] 在「服务拆分」**之前**插入：`## 领域概念`、`## 歧义裁决`、`## 审核 pass / 写库决策表`、`## 集成 / 联调范围`
- [ ] 领域概念表含 PLAN §4.1 规定的 mandatory 列（词条、定义、判定条件、来源、影响 spec；kb 引用 / kb_action 条件列）
- [ ] 章节标题与 §5.2 中 §C 检索用标题 **兼容**（允许 PLAN 写的别名，但须在 checklist 或 skill 中写清匹配规则）

#### P0-2 `flow/templates/verify-checklist.md`

- [ ] 文首为 **三层**（§A / §B / §C）+ 调用模式表（format / design / full）
- [ ] §C 含 **C.1.1–C.1.7**、**C.2.1–C.2.4**（ID 可与 PLAN 略有命名差异，但语义须覆盖）
- [ ] 「不在本清单范围」已按 §5.3 更新；**不再**把「业务语义」笼统推给未实现的 design/review
- [ ] archive 用法仍明确：**全量 = §A+§B**，不强制 §C

#### P0-3 `codex/skills/flow-codex-verify/SKILL.md`

- [ ] frontmatter `description` 体现 design 模式与 §C
- [ ] 三种模式表与 checklist 一致
- [ ] 明确 §C 只读、不写 KB、不审代码
- [ ] 引用路径仍为 `../flow-codex-core/assets/templates/verify-checklist.md`（安装副本；**源文件改 `flow/templates/`**）

#### P0-4 `codex/skills/flow-codex-design/SKILL.md`

- [ ] 步骤 4：强制产出领域概念等四节 + KB 先查 + OpenSpec 禁止模糊降义
- [ ] 步骤 5 blocked：领域概念空、缺 pass 表、歧义无裁决
- [ ] 步骤 8/9：提示 `verify_mode=design`；§C ERROR 不得声明 design 完成
- [ ] 服务模式：子 spec 不得擅自改根领域概念

#### P0-5 `codex/skills/flow-codex-assign/SKILL.md`

- [ ] 派发前增加：对本 change 跑 `verify_mode=design`
- [ ] §A 或 §C 存在 ERROR → **停止派发**
- [ ] WARN → 须说明并获用户确认（文案与 verify skill 一致）

### P1 / P2 检视（缺失不必然 REJECT，须在结论中标注）

| 项 | 期望 |
|----|------|
| P1 kb + archive | `flow-codex-kb` 提取规则；archive WARN `kb_action: 待沉淀` |
| P1 CHANGELOG | 有条目描述本次变更 |
| P2 AGENTS.md / codex/PLAN.md | 生命周期补 design verify 节点 |
| P2 Claude flow-design | 若未改，结论注明「Codex-only；Claude 待 follow-up」 |

### 一致性交叉检查

| 检查 | 通过标准 |
|------|----------|
| 模板 ↔ §C | §C 检查的章节名/列能在 overview 模板找到对应 |
| design ↔ assign | 两者均引用同一 `verify_mode=design` 字符串或等价表述 |
| verify ↔ archive | archive 前置仍为全量 §A+§B；**不**要求 archive 前再跑 §C |
| MAINTENANCE §0 | 模板仍只改 `flow/templates/` 源，未在 skill 里 duplicate 整份 checklist |

### 回归预期（检视 agent 应核对文案/log，不要求实施者一定跑业务项目）

- 仅 `verify_mode=format` → 只执行 §A，与改前一致
- `verify_mode=full` / test·archive 前置 → §A+§B，**不含 §C**
- `verify_mode=design` → §A+§C

### 检视输出格式

```markdown
## [PLAN_REVIEW] PASS | REJECT

**范围**：<commit/PR>
**validate.ps1**：PASS | FAIL

### P0
- [PASS|REJECT] P0-1 overview-design.md.tmpl: …
- …

### P1/P2
- [PASS|WARN|SKIP] …

### 一票否决
- V1–V7：无 | 触发 Vx：…

### 问题（REJECT 时必填）
1. <文件>:<行或节> — <与 PLAN 哪条不符> — <实施 agent 应如何改>

### 备注
- …
```

**PASS 条件**：无一票否决；P0 全部 PASS；P1 缺失仅 WARN。

---

## 1. 目标与非目标

### 1.1 目标

| # | 目标 |
|---|------|
| G1 | `flow-codex-design` 在概要设计中**强制产出**领域概念及相关决策表（规范写在 design skill + 模板） |
| G2 | `flow-codex-verify` **默认行为不变**（§A 格式 / §A+§B 全量）；新增 **`verify_mode=design`** 执行 **§C 设计过程合规** |
| G3 | `flow-codex-assign` 派发前强制 design verify（§A+§C）无 ERROR |
| G4 | `flow-codex-kb` 补充：只处理 design 中 `kb_action: 待沉淀` 的稳定条目（archive 提取清单） |
| G5 | `flow-codex-review` **不改** |

### 1.2 非目标

- 不把 design 合规塞进 `flow-codex-review`（避免与用户/子 agent 角色混淆）
- §C 不验证运行时行为、集成测试是否通过、SQL 是否正确
- §C 不替代跨服务 `api.md` 契约比对（仍归 Claude flow-verify）
- 不在 verify 中直接写 KB 文件（写入仍须 kb skill + 用户确认）

---

## 2. 职责边界（实施后）

```text
flow-codex-design
  → 产出：领域概念、歧义裁决、pass 决策表、Spec 矩阵、OpenSpec…
  → 自检：Spec 粒度（现有 blocked 项）

flow-codex-verify
  → 默认 / format：§A（+ 全量时 §B）— 与 today 相同
  → design 模式：§A + §C — assign 前门禁

flow-codex-assign
  → 前置：选中 spec 的 OpenSpec apply-ready + design verify §C 无 ERROR

flow-codex-review（不变）
  → apply 后：OpenSpec design.md vs 变更代码

flow-codex-kb（补充）
  → archive / 用户触发：merge `source: change` + `kb_action: 待沉淀`
```

---

## 3. 涉及文件清单

| 优先级 | 文件 | 动作 |
|--------|------|------|
| P0 | `flow/templates/verify-checklist.md` | 新增 **§C**；更新文首分层说明；调整「不在本清单范围」 |
| P0 | `codex/skills/flow-codex-verify/SKILL.md` | 新增 `verify_mode=design`；更新 description 与「不在范围」 |
| P0 | `flow/templates/overview-design.md.tmpl` | 新增章节：领域概念、歧义裁决、pass 决策表、集成范围 |
| P0 | `codex/skills/flow-codex-design/SKILL.md` | 步骤 4/5 增加领域概念产出要求；步骤 8 提示跑 verify design |
| P0 | `codex/skills/flow-codex-assign/SKILL.md` | 派发前检查增加 design verify |
| P1 | `codex/skills/flow-codex-kb/SKILL.md` | change 入口增加提取规则与 archive 联动说明 |
| P1 | `codex/skills/flow-codex-archive/SKILL.md` | archive 前提示 kb 提取（可选 WARN） |
| P1 | `CHANGELOG.md` | 记录本次变更 |
| P2 | `AGENTS.md` | 生命周期图补充 design verify 节点 |
| P2 | `codex/PLAN.md` | 公开 skill 说明补一句 verify design 模式 |
| P2 | `.claude/skills/flow-design/SKILL.md` | Claude 侧 design 对齐（若结构与 Codex 共享模板则改模板即可） |
| — | `codex/skills/flow-codex-review/*` | **不修改** |

安装后同步路径（`install.ps1` 复制）：`flow/templates/verify-checklist.md` → `flow-codex-core/assets/templates/verify-checklist.md`。

---

## 4. 概要设计模板（`overview-design.md.tmpl`）

在 **「服务拆分」之前** 插入以下章节（顺序固定，便于 §C 按标题检索）：

### 4.1 `## 领域概念`

表格列（mandatory 列）：

| 列 | 说明 |
|----|------|
| 词条 | 产品/测试可读的名称 |
| 定义 | 一句话业务语义 |
| 不是 | 易混淆边界（可选但推荐） |
| 判定条件 | 可验证条件（如 `contract_type=3` + tenant/project/company/worker） |
| 来源 | `kb` \| `change` |
| KB 引用 | `source=kb` 时填功能域路径或 `@feature-xxx` |
| kb_action | `source=change` 时填 `待沉淀` \| `无需` |
| 影响 spec | 关联 c{n} 或 — |

**规则（写入 design skill）**：

- 涉及合同、审核节点、预警类型、身份/权限码等**必须先查 KB 功能域**；有则 `source: kb`，无则 `source: change`
- 不得用实现别名（`wc`、「正式合同」）代替未定义的词条

### 4.2 `## 歧义裁决`

当需求输入（纪要、多方文档）存在冲突说法时使用；无冲突时写「无未裁决歧义」。

| 列 | 说明 |
|----|------|
| 议题 | 如「登记预警写 worker_warn 还是 worker_on_duty_warn」 |
| 选项 A / B | 简短描述 |
| 裁决 | A \| B \| 其他 |
| 依据 | 产品确认 / 纪要 §x / KB ref |
| 回写 | 更新哪条领域概念或验收标准 |

### 4.3 `## 审核 pass / 写库决策表`

**条件 mandatory**：概要设计描述多步审核、状态流转或「通过/驳回」写库时。

| 列 | 说明 |
|----|------|
| 审核节点 | 如工区主管审核 |
| 前置条件 | 引用领域概念词条 |
| 通过动作 | 调用的既有写路径（如 `passWithProjectAudit`） |
| 目标状态 | status / enter_date 等 |
| MUST NOT | 禁止行为（如不得用任意 worker_contract 当腾讯合同） |
|  owning spec | c{n} |

### 4.4 `## 集成 / 联调范围`

| 列 | 说明 |
|----|------|
| 范围 | 首派 / Phase-2 / 不在本次 |
| 说明 | 可测边界 |
| 依赖 spec | c{n} 或 st-api |

---

## 5. verify-checklist 新增 §C

### 5.1 文首分层（替换现有「两层」表述）

```markdown
本清单分三层：
- **§A 产物格式**（结构/格式，不判业务语义）
- **§B 发布就绪**（完成度与 git 状态；仅全量 verify）
- **§C 设计过程合规**（领域概念与向下传导；仅 `verify_mode=design`）

| 调用模式 | 章节 |
|----------|------|
| 格式复验（默认轻量） | §A |
| 设计合规 | §A + §C |
| 全量 verify（test/archive） | §A + §B（不默认跑 §C；assign 前单独跑 design 模式） |
```

### 5.2 §C 检查项

#### C.1 概要设计必备节（ERROR）

| ID | 检查项 | 说明 |
|----|--------|------|
| C.1.1 | 领域概念节存在 | `## 领域概念` 存在且至少 1 行数据行 |
| C.1.2 | 词条字段完整 | 每行含：词条、定义、判定条件、来源、影响 spec |
| C.1.3 | KB 引用可解析 | `source=kb` 时 KB 引用非空；若根 `config.yaml` 启用 KB 且路径可访问，引用路径或 @feature 须存在（不可访问时 WARN） |
| C.1.4 | change 词条 kb_action | `source=change` 时 kb_action 为 `待沉淀` 或 `无需` |
| C.1.5 | 歧义裁决 | 纪要/对齐文档存在冲突表述时须有 `## 歧义裁决` 且每议题有唯一「裁决」列；否则 WARN |
| C.1.6 | pass 决策表 | 存在多步审核/状态流转描述时须有 `## 审核 pass` 或 `## 审核 pass / 写库决策表` 且覆盖文档中提到的每个审核节点；否则 ERROR |
| C.1.7 | 集成范围 | `## 集成` 或 `## 集成 / 联调范围` 存在；首派 vs Phase-2 有明确标注 |

#### C.2 向下传导（ERROR / WARN）

| ID | 检查项 | 级别 | 说明 |
|----|--------|------|------|
| C.2.1 | 矩阵覆盖影响面 | ERROR | 领域概念「影响 spec」列中出现的 c{n} 均在 Spec 矩阵中存在 |
| C.2.2 | 术语不降级 | ERROR | 子 OpenSpec（proposal/design/delta spec）出现与根领域概念同主题但**更模糊**的表述，且未引用根词条 ID/名称（启发式：如根有「腾讯电子合同 type=3」，子 spec 仅写「正式合同」「worker_contract」而无 type/company 约束） |
| C.2.3 | 裁决已传导 | ERROR | 歧义裁决表的「回写」项在对应 OpenSpec 或概要设计验收标准中可找到一致表述 |
| C.2.4 | pass 表与矩阵 | WARN | pass 决策表「owning spec」均在矩阵中且职责不空 |

#### C.2 检测方法（写入 verify skill）

- 读取 `.flow/changes/{change}/概要设计.md`、对齐纪要（若同目录存在 `对齐纪要.md` 等则扫描冲突关键词）
- 对每个 task spec-id 读取对应服务 `openspec/changes/{spec-id}/design.md` 与 `specs/**/*.md`
- **只读**；输出 `文件:行号` 或章节名

### 5.3 更新「不在本清单范围」

删除或改写：

```diff
- 业务拆法、接口语义、Non-goals 是否正确 → design / review
+ 运行时业务是否正确、验收是否通过 → flow-codex-test / 联调
+ 代码是否违背设计 → flow-codex-review（apply 后）
+ 跨服务 api.md 契约 → Claude flow-verify
+ §C 不判断：SQL 正确性、性能、安全 exploit、KB 正文业务是否过时
```

---

## 6. `flow-codex-verify/SKILL.md` 改动要点

### 6.1 description（frontmatter）

```yaml
description: 只读检查 Flow 根产物格式与发布就绪；可选 design 模式校验设计过程合规（领域概念与 OpenSpec 传导）。不验证运行时行为与跨服务 api.md 契约。
```

### 6.2 调用模式表（替换 §「调用模式」）

| 模式 | 参数 | 执行章节 | 时机 | ERROR 阻断 |
|------|------|----------|------|------------|
| **格式复验** | 默认 / `verify_mode=format` | §A | design 后可选 | 仅当调用方声明为门禁时 |
| **设计合规** | `verify_mode=design` | §A + §C | design 完成 → **assign 前强制** | assign |
| **全量 verify** | `verify_mode=full` 或 test/archive 前置 | §A + §B | test / archive | test / archive |

### 6.3 新增段落「§C 设计过程合规」

- 读取 KB：根 `.flow/config.yaml` → `knowledge_base`（与 kb skill 一致）
- C.2.2 术语降级：维护一份**模糊词黑名单**（可选放在 `flow/templates/design-compliance-heuristics.md`，P2 再做）；首版在 checklist 内联示例即可
- 输出格式与 §A 相同：`[ERROR|WARN|PASS] C.x.x: …`

### 6.4 「不在范围」微调

```markdown
- §A / §B：不验证业务运行时行为、接口语义是否「最优」、验收是否通过
- §C：不验证代码实现（归 review）、不写入 KB（归 flow-codex-kb）
```

---

## 7. `flow-codex-design/SKILL.md` 改动要点

在步骤 **4**（创建概要设计）中增加：

```markdown
- 在 `概要设计.md` 按模板产出 **§领域概念**、**§歧义裁决**、**§审核 pass 决策表**（条件 mandatory）、**§集成/联调范围**。
- 领域概念：先查 KB 功能域；有则 `source: kb`，无则 `source: change` + `kb_action`。
- 子 OpenSpec 生成时 **MUST** 引用根领域概念词条名，禁止单独发明更模糊的同义表述。
```

在步骤 **5** 设计结束前自检增加（blocked）：

```markdown
- `## 领域概念` 为空或缺少判定条件列
- 存在多步审核但无 pass 决策表
- 歧义裁决议题无唯一「裁决」值
```

步骤 **8** 改为：

```markdown
8. 提示用户或根 agent 执行 `flow-codex-verify`（`verify_mode=design`）。存在 §C ERROR 时不得声明 design 完成。
9. 返回 Spec 矩阵、spec 依赖图、apply-readiness 与 verify design 结果摘要。
```

**服务模式**（子 agent 单 spec design）：生成的 OpenSpec 须与根 `概要设计.md` 领域概念一致；不一致时修复 OpenSpec 而非改根概念（根概念变更走 `flow-codex-change`）。

---

## 8. `flow-codex-assign/SKILL.md` 改动要点

在「派发前检查」增加步骤（建议为第 4 项，原 4→5，原 5→6）：

```markdown
4. 对本 change 执行 `flow-codex-verify`（`verify_mode=design`）。存在 §C 或 §A ERROR 时停止派发；WARN 须向用户说明并获确认后继续。
```

可选：在根 `.flow/config.yaml` 增加开关（P2）：

```yaml
design_verify_before_assign: true  # 默认 true；false 时仅 WARN
```

首版可写死 mandatory，不增加 config 字段。

---

## 9. `flow-codex-kb/SKILL.md` 补充（P1）

在「入口 A：change」步骤 2 后增加提取规则：

```markdown
**从概要设计提取（优先）**：
- 仅处理 `## 领域概念` 中 `source: change` 且 `kb_action: 待沉淀` 的行
- 写入 KB 功能域 `## 业务规则` 或术语子表；不复制 change 全文
- `source: kb` 的词条：archive 时做「实现是否违反 KB」抽检（可选，不写入 kb skill 自动执行）

**不沉淀**：
- 联调修正、GLW/commit、一次性脏数据
- `kb_action: 无需`
- pass 决策表中纯流程临时约定（除非用户指定沉淀）
```

在 `flow-codex-archive/SKILL.md` 前置增加 WARN：

```markdown
- 若概要设计存在 `kb_action: 待沉淀` 且未执行 kb change 入口，WARN 并提示用户是否先 `flow-codex-kb`
```

---

## 10. `flow-codex-review` — 明确不改动

| 项 | 说明 |
|----|------|
| 触发时机 | 仍为 apply 后 `REVIEW_REQUEST` |
| 执行者 | 根 agent 派同级 review agent |
| 对照物 | OpenSpec `design.md` + 变更文件 |
| 可选增强（**本次不做**） | spec review 增加「代码/query 是否违反根概要设计领域概念」— 若未来要做，单独开 PLAN |

---

## 11. 实施顺序

```text
1. flow/templates/overview-design.md.tmpl     # 结构先行
2. flow/templates/verify-checklist.md         # §C 全文
3. codex/skills/flow-codex-verify/SKILL.md
4. codex/skills/flow-codex-design/SKILL.md
5. codex/skills/flow-codex-assign/SKILL.md
6. codex/skills/flow-codex-kb/SKILL.md + archive/SKILL.md
7. CHANGELOG.md + AGENTS.md + codex/PLAN.md
8. 跑 codex/validate.ps1
9. 业务项目 reinstall skills（install.ps1）
10. 用 guanghuo-wage-register-audit 做 dry-run（见 §12）
```

---

## 12. 验收与 dry-run

### 12.1 skills 仓库

- [ ] `codex/validate.ps1` 通过
- [ ] verify-checklist 三层结构自洽；archive 仍只引用 §A+§B 全量
- [ ] design / assign / verify skill 三者对 `verify_mode=design` 表述一致

### 12.2 业务项目（glm · guanghuo）

对 `.flow/changes/guanghuo-wage-register-audit/`：

1. **补写**（或附录 draft）`## 领域概念` 等节 — 用于验证 §C 能抓到历史缺口
2. 跑 `flow-codex-verify` design 模式 — 预期对**未补写前**的旧概要设计报 C.1.x / C.2.x ERROR
3. 补写后 rerun — §C PASS（或仅剩 KB 路径 WARN）
4. assign 前置 — 有 ERROR 时不应派发

### 12.3 回归

- [ ] 仅跑 format（§A）行为与改前一致
- [ ] test/archive 全量仍 §A+§B，不因缺 §C 而误报（design 模式单独跑）

---

## 13. 风险与缓解

| 风险 | 缓解 |
|------|------|
| §C C.2.2 启发式误报 | 首版 WARN 为主；明确 blacklist 示例；REJECT 需引用根概念行号 |
| 旧 change 无新章节 | assign 前置才强制；历史已 assign 的 change 不 retroactive |
| KB 路径不可用 | C.1.3 降级 WARN，不 ERROR |
| Claude / Codex 双平台漂移 | 模板改 `flow/templates/`；Claude design command 引用同一 overview 模板 |

---

## 14. 附录 A：领域概念示例（广火）

| 词条 | 定义 | 不是 | 判定条件 | 来源 | kb_action | 影响 spec |
|------|------|------|----------|------|-----------|-----------|
| 腾讯电子合同 | 腾讯侧电子劳务合同 | 纸质合同、临时扫码合同 | `worker_contract.contract_type=3` + tenant/project/company/worker | change | 待沉淀 | c3, c5 |
| 登记预警（产品） | 登记环节预警展示 | 在岗预警 type=23 | `worker_warn.type=9`（W6 裁决） | change | 待沉淀 | c5, c9, c23 |
| 工区审核通过 | 工区节点通过后的写库 | 直接 workerRegister 入场 | 见 pass 决策表 | change | 无需 | c16+ |

## 15. 附录 B：verify design 模式输出示例

```markdown
## flow-codex-verify · guanghuo-wage-register-audit · mode=design

### §A
- [PASS] A.2 Spec 矩阵存在
- …

### §C
- [ERROR] C.1.1: 概要设计.md 缺少 `## 领域概念`
- [ERROR] C.1.6: 存在工区/项目/分包审核节点但无 pass 决策表
- [ERROR] C.2.2: c5-area-wage-warn/specs/.../spec.md:12 使用「正式 worker_contract」未绑定 type=3

**结论**：存在 ERROR，不可 assign。
```

---

## 16. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-07-23 | 初稿：design 产出规范 + verify §C + kb 补充；review 不改 |
| 2026-07-23 | 补充 §0 背景、§检视要求（实施交付物、一票否决、P0 清单、输出格式） |
