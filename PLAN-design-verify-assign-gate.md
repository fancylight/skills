# 改动方案：Design / Verify assign 门禁（§D 操作链路 + §E 文档一致性）

> **状态**：已实施（2026-07-29）  
> **实施者**：按本文 §8 改 `self/skills` 仓库并提交。  
> **检视者**：编排 agent 按本文 **§10** 对提交做只读 PASS/REJECT。  
> **前置**：`PLAN-design-verify-domain-concepts.md`（§C）已实施。  
> **合并**：`PLAN-design-verify-journey.md` 的 §D 内容已并入本文 §5，**勿单独实施 journey PLAN**。  
> **背景与决策摘要**：见 **§0**。

---

## 0. 背景

### 0.1 问题从哪来

| 来源 | 典型缺陷 | §C 能否拦截 |
|------|----------|-------------|
| 广火联调 | 设计了无人调的接口；漏派 spec；BFF/provider 只登记一侧 | 否（§C 只读 design 自身文档） |
| 班组考勤 design | 接口表两行 export；Apifox 未查；§2 与 OpenSpec status 范围矛盾 | 部分（C.2.3 裁决传导） |

**共识（2026-07-29）**：

- **门禁必须在 verify**，不能靠 design agent「设计结束前自检」自证。
- design 只 **产出可被 verify 检查的 artifact**。
- WARN 由 verify 输出 **编排人确认清单**；ERROR 硬挡 assign。

### 0.2 职责边界

| 阶段 | 做什么 | 不做什么 |
|------|--------|----------|
| **design** | 写四件套 + 操作链路 + OpenSpec；Apifox MCP 查链接 | 不声明 verify PASS；不替编排人确认 WARN |
| **verify design** | §A + §C + §D + §E 只读门禁 | 不编辑产物；不读产品 PDF 全文 |
| **assign** | verify 无 ERROR；WARN 已确认 | 不重复格式审查 |

### 0.3 方案决策

| 决策 | 内容 |
|------|------|
| D1 | `verify_mode=design` = **§A + §C + §D + §E**（不新增 mode） |
| D2 | §D = 操作链路（自 journey PLAN）；§E = 设计文档一致性（新增） |
| D3 | design skill **去自检化**；Spec 铁律保留但不等于 assign 门禁 |
| D4 | assign 门禁：§A/§C/§D/§E 任一 ERROR 停止；WARN 须编排人确认 |
| D5 | 根 config 可选 `journey_required` / `apifox_required`（默认 false） |

---

## 1. 目标与非目标

### 1.1 目标

- design 产出 `操作链路.md`（as-built 来自代码检索）
- verify design 模式拦截：链路缺失、接口无调用方、文档矛盾、接口表无变更行
- verify 报告末尾固定 **编排人 WARN 确认清单**

### 1.2 非目标

- §E 不读取产品 PDF 做全文语义比对
- §D/E 不替代运行时联调、集成测试、apply 后 code review
- 不改动 §C 检查项编号与语义
- 不修改 `flow-codex-review`

---

## 2. 实施后生命周期

```text
flow-codex-design
  → 3：Apifox（getStructureInfo + readEntityDetails）
  → 3.5：现状链路提取
  → 4：四件套 + 操作链路.md + OpenSpec
  → 8：提示 verify；不得自声明可 assign

flow-codex-verify verify_mode=design
  → §A + §C + §D + §E
  → ERROR 汇总 + 编排人 WARN 清单

flow-codex-assign
  → §A/§C/§D/§E 无 ERROR；WARN 已确认
```

**不变**：`format` 仅 §A；`full` 仅 §A+§B。

---

## 3. `flow-codex-design/SKILL.md` 改动要点

### 3.1 步骤 3 Apifox

- MCP 可用时：**必须** `getStructureInfo`（`entityType=endpoint`, `projectId`）+ `readEntityDetails`
- **禁止**仅用 `listOpenApiEndpoints` 关键词搜
- 链接：`https://app.apifox.com/link/project/{projectId}/apis/api-{entityId}`

### 3.2 步骤 3.5 现状链路提取

- 读 `操作链路.md.tmpl`
- 从入口端代码检索 as-built；`文件:行` 证据 mandatory
- 禁止仅凭需求文档臆造 as-built

### 3.3 步骤 4 产出物

- 四件套 + **`操作链路.md`**
- §3.2.4 **只列本次新增/修改接口**（§E.2）

### 3.4 步骤 5

```diff
- **设计结束前自检（blocked 若任一成立）**：
+ **Spec 拆分铁律（最终阻断由 verify ERROR 判定；design 不得自声明可 assign）**：
```

- 删除与 §D/§E 重复的三条 blocked（链路/接口无调用方/owning spec）→ 改由 verify

### 3.5 步骤 8

- 提示 `flow-codex-verify`（`verify_mode=design`，§A+§C+§D+§E）
- design **不输出** verify PASS 结论

### 3.6 新增「design 不做的事」

- 不替代 verify；不替编排人确认 WARN；不写 KB

---

## 4. `flow-codex-verify/SKILL.md` 改动要点

### 4.1 调用模式

| 模式 | 章节 |
|------|------|
| format | §A |
| design | **§A + §C + §D + §E** |
| full | §A + §B |

### 4.2 编排人 WARN 清单（存在 WARN 时 mandatory）

```markdown
## 编排人 WARN 确认清单（assign 前）

| ID | 项 | 建议动作 |
|----|-----|----------|
| W1 | … | 确认 / 回 design 修 / waive（说明） |

- ERROR：不可 assign
- WARN：须上表逐项确认；未确认不得 assign
```

---

## 5. `verify-checklist.md` §D（操作链路）

（全文见 `flow/templates/verify-checklist.md` 内 `## §D 链路合规`）

- D.0 降级：`journey_required` 开关
- D.1.1 / D.1.2 结构与证据
- D.2.1 / D.2.2 / D.2.5 与设计交叉比对
- D.2.3 / D.2.4 阶段 B 预留

---

## 6. `verify-checklist.md` §E（设计文档一致性）

| ID | 级别 | 检查项 |
|----|------|--------|
| E.1 | WARN | 新增 REST Apifox「待录入」；`apifox_required: true` 升 ERROR |
| E.2 | ERROR | §3.2.4 不得含「无变更/不变/现网」行 |
| E.3 | ERROR | §2/§3.2.1 与 OpenSpec 可比对字段矛盾 |
| E.4 | ERROR | 非目标与 task/services/矩阵矛盾 |
| E.5 | WARN | 同一 HTTP path 多行（仅 query 差异） |
| E.6 | ERROR | 歧义裁决「裁决」与 OpenSpec 不一致（C.2.3 兜底） |

---

## 7. 其它同步

| 文件 | 改动 |
|------|------|
| `flow/templates/操作链路.md.tmpl` | 新建 |
| `flow/templates/dev-doc-maintenance.md` | §7 design：§3.2.4 只列变更接口 |
| `flow-codex-assign/SKILL.md` | §A/§C/§D/§E ERROR + WARN 清单 |
| `flow-codex-change/SKILL.md` | 链路同步 + 重跑 design verify |
| `codex/validate.ps1` | 检查 `操作链路.md.tmpl` |
| `AGENTS.md` / `CHANGELOG.md` | 生命周期与 Unreleased |

---

## 8. 涉及文件与实施顺序

1. `PLAN-design-verify-assign-gate.md`（本文）
2. `flow/templates/操作链路.md.tmpl`
3. `flow/templates/verify-checklist.md`
4. `codex/skills/flow-codex-design|verify|assign|change/SKILL.md`
5. `dev-doc-maintenance.md` + `validate.ps1` + `AGENTS.md` + `CHANGELOG.md`
6. `PLAN-design-verify-journey.md` 文首标注已合并
7. `codex/validate.ps1` + dry-run

---

## 9. 验收

- [x] `codex/validate.ps1` PASS（2026-07-29，§D/§E 实施后复验）
- [ ] `verify_mode=format` 仅 §A；`full` 仅 §A+§B（回归待业务项目跑）
- [ ] 广火补链路后 D.2.2 可触发（dry-run 待业务项目补 `操作链路.md`）
- [x] 班组考勤 §E dry-run（文档已修后）：
  - E.2：无「无变更」接口行 → PASS
  - E.1：revoke 接口 Apifox「待录入」→ WARN
  - E.3：§2/§3.2.1 与 c1 spec 均 status=2 → PASS
  - D.1.1：无 `操作链路.md` → WARN（`journey_required` 未开）

---

## 10. 检视要求（一票否决摘要）

| ID | 条件 |
|----|------|
| V1 | 修改了 `flow-codex-review/**` |
| V2 | 默认 format/full 行为被破坏 |
| V3 | P0 文件遗漏 |
| V4 | checklist 与 verify skill 对五层/三种 mode 不一致 |
| V5 | design/assign/verify 对 design 模式章节表述不一致 |
| V6 | `validate.ps1` 失败 |
| V7 | verify skill 含自动修复产物指令 |
| V8 | §C 检查项被改动 |
| V9 | 改了 test-design / kb（本版明确不动） |

---

## 修订记录

| 日期 | 说明 |
|------|------|
| 2026-07-29 | 初稿：合并 journey §D + 新增 §E；design 去自检化 |
