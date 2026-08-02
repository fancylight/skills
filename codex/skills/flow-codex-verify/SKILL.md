---
name: flow-codex-verify
description: 只读检查 Flow 的领域事实、根产物格式、设计 SQL 数据访问契约与发布就绪；domain 模式独立抽查领域事实证据，design 模式校验 Fact ID 消费、OpenSpec 传导、操作链路与设计文档一致性。不验证业务运行时行为与跨服务 api.md 契约。
---

# Codex Flow 验证

读取 `../flow-codex-core/references/platform.md` 与
`../flow-codex-core/assets/templates/verify-checklist.md`。

对明确指定的 `change_name` 执行只读检查，输出结构化报告：

- **ERROR**：阻断进入 `flow-codex-test`（full）、`flow-codex-archive`（release）或 `flow-codex-assign`（design 模式）
- **WARN**：提示用户确认后可继续；design 模式存在 WARN 时报告末尾 **必须**附编排人确认清单
- **PASS**：该项满足

## 调用模式

| 模式 | 参数 | 执行章节 | 时机 | ERROR 阻断 |
|------|------|----------|------|------------|
| **格式复验** | 默认 / `verify_mode=format` | §A | design 后可选 | 仅当调用方声明为门禁时 |
| **领域事实** | `verify_mode=domain` | §G | DOMAIN_DRAFT → 方案设计前强制 | 方案设计 |
| **设计合规** | `verify_mode=design` | §A + §C + §D + §E + §F.1–§F.3 + Fact ID 消费 | solution design 完成 → **assign 前强制** | assign |
| **全量 verify** | `verify_mode=full` | §A + §B | test 前 | test |
| **发布 verify** | `verify_mode=release` | §A + §B + §F | 集成测试后 → archive 前强制 | archive |

格式复验时 §B / §C / §D / §E / §F / §G 未完成属正常，不得因此报 ERROR。全量 verify **不**默认跑 §C / §D / §E / §F / §G。domain 模式只跑 §G；design 模式 **不**跑 §B、§G 或运行时 F.4；release 模式不跑 §C / §D / §E / §G。

## 检查范围

1. **§G 领域事实真实性**（见 checklist §G，仅 `verify_mode=domain`）：运行确定性领域产物 validator，再独立抽查高风险代码/schema/契约证据；无 ERROR 时输出同一领域模型指纹的 `DOMAIN_VERIFIED`
2. **§A 产物格式**（见 checklist §A）：根四件套、概要设计 Spec 矩阵、task.md 行型与 Spec 粒度、开发文档格式、子 OpenSpec 结构、发版记录行型
3. **§B 发布就绪**（见 checklist §B，仅全量）：spec 完成度、分支、worktree、发版记录覆盖
4. **§C 设计过程合规**（见 checklist §C，仅 `verify_mode=design`）：领域概念、歧义裁决、pass 决策表、集成范围、向下传导
5. **§D 链路合规**（见 checklist §D，仅 `verify_mode=design`）：操作链路结构与证据、变更步骤归属 spec、接口有调用方、跨服务两侧登记
6. **§E 设计文档一致性**（见 checklist §E，仅 `verify_mode=design`）：Apifox、接口表范围、开发文档与 OpenSpec 矛盾、非目标与矩阵矛盾
7. **§F SQL 数据访问门禁**（见 checklist §F）：design 检查数据访问契约和 OpenSpec 传导；release 另检查最终列表 SQL、分页 count SQL 与只读 EXPLAIN 证据

Spec 粒度（1 c = 1 repo）在 design 写 task 时须遵守铁律；verify §A 做只读复验。

## §G 领域事实真实性

- 读取 `.flow/changes/{change_name}/domain-model.md`，运行 core assets 中的 `validate-domain-artifact.ps1`；脚本 ERROR 时逐项原样输出并返回 `[DOMAIN_VERIFY_RESULT] ERROR`。
- 脚本 PASS 后，按 checklist DV.4/DV.5 独立抽查高风险事实的当前代码、schema 或 provider/consumer 契约；不得把领域模型、概要设计或 agent 推断当作证据。
- 确定性 validator 的 PASS 只证明领域产物结构、ID、证据索引和冲突字段满足规则，不代表 DV.4/DV.5/DV.6 语义审核完成。语义审核必须单独执行 replay cases 或 agent 的只读代码/schema/KB 抽查；不得用字符串替换或 validator PASS 冒充该结论。replay fixture 的输出必须明确标记为 `replay-contract-only`。
- 发现未裁决冲突、字段/实体/读写代码直接冲突、缺组成字段或缺不生效分支时输出对应 `DV.* ERROR`；仅 E3 样例支撑时输出 `DV.7 WARN`。
- 无 ERROR 时以 `Get-FileHash -Algorithm SHA256` 计算当前 `domain-model.md` 指纹，输出 `[DOMAIN_VERIFY_RESULT] PASS`、`phase: DOMAIN_VERIFIED` 和 `domain_model_sha256`。
- **只读**：不修改领域模型、不生成方案产物、不写状态文件；领域模型变更后旧 PASS 自动失效。

## §C 设计过程合规

- 读取根 `.flow/config.yaml` → `knowledge_base`（与 `flow-codex-kb` 一致）解析 C.1.3
- 标题匹配与检查项以 `verify-checklist.md` §C 为准（含 `## 审核 pass` / `## 集成` 别名）
- C.2.2 术语降级：按 checklist 内联模糊词示例；报 ERROR 须引用根概念行号与子 OpenSpec 位置
- 输出格式与 §A 相同：`[ERROR|WARN|PASS] C.x.x: …`
- **只读**：不写入 KB、不编辑产物、不审代码实现

## §D 链路合规

- 读取 `.flow/changes/{change}/操作链路.md`、`概要设计.md` Spec 矩阵、`开发文档.md` §3.2.4
- **防自证**：`as-built` 行须带代码位置证据。整份文件无 `as-built` 行且非纯新建服务时输出 WARN
- 代码位置存在性：仓库在根 `.flow/config.yaml` 登记且可访问时校验文件存在；否则仅校验格式并标注「未校验」
- 缺 `操作链路.md`：默认 D.1.1 WARN、其余 SKIP；根 config 设 `journey_required: true` 时 D.1.1 升 ERROR。文件存在时 D.1.2/D.2.* 一律 ERROR
- 报 ERROR 须同时给出链路侧（`J{n} 步骤 {#}`）与设计侧（矩阵行 / §3.2.4 行）位置
- 输出格式与 §A 相同：`[ERROR|WARN|PASS] D.x.x: …`
- **只读**：不补写链路、不编辑产物、不判断链路业务正确性

## §E 设计文档一致性

- 读取 `概要设计.md`、`开发文档.md` 与各 task spec 的 OpenSpec design/delta specs
- 读取根 `.flow/config.yaml` → `apifox_required`（默认 false）解析 E.1 级别
- 可比对字段规则见 checklist §E.0；不读取产品 PDF 全文
- 输出格式与 §A 相同：`[ERROR|WARN|PASS] E.x: …`
- **只读**：不编辑产物

## §F SQL 数据访问门禁

- 以 checklist §F 为准；仅扫描本 change 根产物及对应 OpenSpec / 测试 / 发版证据，不执行 SQL 或 EXPLAIN。
- `verify_mode=design` 输出 F.1–F.3；契约应有但缺失或未传导时 ERROR，不能 assign。
- `verify_mode=release` 输出 F.1–F.4；证据不存在、不能定位最终分页 count SQL，或命中非豁免风险计划时 ERROR，不能 archive。
- **只读**：不补写契约、不运行数据库命令、不把代码检索结果冒充计划证据。

## 编排人 WARN 确认清单（design 模式存在 WARN 时 mandatory）

报告末尾追加：

```markdown
## 编排人 WARN 确认清单（assign 前）

| ID | 项 | 建议动作 |
|----|-----|----------|
| W1 | … | 确认 / 回 design 修 / waive（说明） |

- ERROR：不可 assign
- WARN：须上表逐项确认；未确认不得 assign
```

为每个 WARN 检查项分配 W{n}，简述问题与建议动作。

## 不在范围

- 跨服务 api.md 契约比对（Claude Code 的 flow-verify 专责）
- §A / §B：不验证业务运行时行为、接口语义是否「最优」、验收是否通过
- §C：不验证代码实现（归 `flow-codex-review`）、不写入 KB（归 `flow-codex-kb`）
- §G：不生成概要设计、OpenSpec、task 或发版产物；领域产物的结构校验归 `validate-domain-artifact.ps1`
- §D：不验证运行时行为与既有方法的隐藏前置条件、不生成测试用例（归 `flow-codex-test-design` / `flow-codex-test`）
- §E：不读取产品 PDF 全文；SQL 契约与证据归 §F，具体 SQL 实现审查归 `flow-codex-review`
- HTTP 集成测试、单元测试覆盖

不要编辑或静默修复任何文件。按服务汇总阻断项。
