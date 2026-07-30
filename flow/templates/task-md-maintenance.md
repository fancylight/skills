# task.md 维护范式

> 本文档定义 task.md 的维护规则，供 `flow:design`、`flow:report`、`flow:change`、`flow:assign` 四个命令引用。
> task.md 是**活文档**——每次更新应该用最新状态重写对应区域，而非在旧信息上叠加。

---

## 1. 核心原则

| 原则 | 说明 |
|------|------|
| **重写优于追加** | 更新一个条目/区域时，用当前最新状态重写，不在旧内容后追记 |
| **权威单一来源** | 每条信息只有一个权威位置。任务条目 = spec 状态权威，变更通知 = 仅索引 |
| **spec ID 是通用标识** | 所有交叉引用（依赖、顺序、变更通知）必须用 `c{n}` 格式 |
| **完成后只保留结论** | 完成的 spec 条目只保留：边界 + 完成日期 + commit hash。清理过程性标记 |

---

## 2. 文档结构与职责

```
---
元数据头（YAML frontmatter）
---

## 开发顺序           ← 依赖拓扑，用 spec ID 引用
## {service-name}     ← 每个 spec 的当前状态（权威来源）
  ### Hotfix         ← 本服务 hotfix（如有）
## 完成检查清单        ← 编译/测试的当前通过状态
## 变更通知（待子 agent 感知）  ← 1行索引，子 agent 消费后删除
```

### 2.1 元数据头

```yaml
---
requirement: string          # 需求标题
type: feature|hotfix|refactor
status: planning|in_progress|completed|archived
tier: 1|2|3
branch: string               # 根分支名
services:
  - name: string             # 服务名（与 config.yaml 一致）
    repo: string             # 仓库名（目录名）
    branch: string           # 该服务开发分支
created: YYYY-MM-DD
updated: YYYY-MM-DD          # 任何修改都必须更新此字段
---
```

### 2.2 开发顺序

- 列出所有 spec 的依赖拓扑排序，**每行一个 spec、恰好一个 git 仓库**
- 依赖引用**必须用 spec ID**（`c3`），**禁止**用序号（`3`、`依赖3`）
- 格式：`{序号}. {spec-id}（{单一 service}，依赖 {spec-id 或 —}）`
- **括号内恰好一个服务名**——禁止 `c4（register + aggregator）`、`c5（worker-service + worker-register-service）`
- 跨仓同能力须拆成多个递增 c，不是一行绑多仓
- 正例：`2. c4-sub-job-read（worker-register-service，依赖 c3）`、`3. c5-sub-job-vo（worker-app-aggregator，依赖 c4）`
- 反例：`3. c4-sub-job-read（worker-register-service + worker-app-aggregator，依赖 c3）`（一行多仓）
- 反例：`3. c4-float-validate（glm-attendance，依赖3）`（依赖不用 spec ID）

### 2.3 服务章节

每个服务一个 `## {service-name}` 章节。

**服务头部**：**只保留 1 行**当前状态，每次更新时**替换**，不追加。

```
> 状态：{emoji} {状态文本} | 分配日期：{date} | 模式：{mode} | 任务号：{id}
```

- 禁止多行日期流水（"2026-05-13 c19 新增"、"2026-05-11 追加分配" 等）
- 历史分配信息不保留在头部——需要历史时查 git log

**spec 条目格式**：

```
- [{x| }] {spec-id}: {标题}··
      边界：{boundary}··
      依赖：{spec-id 或 无}··
      完成：{YYYY-MM-DD} commit {hash}   ← 仅已完成时有此行
      ⚠️ 设计修正（{date}）：{1行简述}，详见变更通知   ← 仅被重开时有此行
```
> `··` = 2 个空格。除条目最后一行外，每行末尾必须有。没有就会粘成一段。

**字段顺序**（固定，不可调换）：

```
1. 边界：（必填，spec 范围定义）
2. 依赖：（必填，spec-id 或 无/—）
3. 完成：（仅已完成时有，report 写入）
4. ⚠️ 设计修正：（仅被重开时有，change 写入，放在最后）
```

**约束**：
- 每个 spec 条目**不超过 6 行**（含空行）
- **边界必须 1 行**。用紧凑枚举（`；`分隔），禁止写散文段落。如需展开细节，写入 design.md 并在边界末尾加 `，详见 design.md`
- **禁止在 spec 条目内展开子列表**（如 `已完成：...` / `待完成：...` 多行罗列）。进度跟踪用 `进度：{一句话}`，详情放 design.md
- `⚠️ 设计修正` 只留 1 行简述 + 引用，**不**在此展开详细修改内容，且**必须放在最后一行**（依赖/完成之后）
- 重开时**必须清除**旧的 `完成：date commit hash`
- 重开时**不能**保留删除线旧记录（如 `~~完成：2026-05-11 commit be007113~~`）

### 2.4 Hotfix 子章节

hotfix 与 feature spec 生命周期不同，放在每个服务章节**末尾**的 `### Hotfix` 子章节下（feature spec 全部在前，hotfix 垫底）：

```
## {service-name}

> 状态行

- [x] c1-xxx: ...
- [ ] c2-xxx: ...
...

### Hotfix

- [x] hotfix-{YYYYMMDD}-{slug}: {问题简述}··
      问题：{1行描述}··
      修复：{1行描述}··
      完成：{YYYY-MM-DD} commit {hash}
```

⚠️ `### Hotfix` 必须放在 feature spec 之后，否则三级标题会吞掉后续所有条目，造成视觉上全部任务都归属 hotfix。

### 2.5 完成检查清单

- 每个条目对应一个可验证的事实（编译通过 / 测试通过 / spec 完成）
- **变更重开 spec 时，必须同步取消**相关清单条目（`[x]` → `[ ]`）
- 汇报完成勾选前，**必须验证**清单与任务实际状态一致
- 集成测试相关（多服务需求建议包含）：
  - `[ ] 集成测试设计 READY` — `flow-codex-test-design` 产出 manifest + test-plan
  - `[ ] 集成测试代码完成` — `st-api-*` report 勾选
  - `[ ] 集成测试执行 PASS` — `flow-codex-test` 写 `集成测试.md` 且 PASS

### 2.6 变更通知

- 每行一个变更，格式：`- **{service}**：{spec-id} {变更类型} — {1行简述}`
- 仅作为子 agent 的**消费队列**——子 agent receive 时读取并处理，处理后删除对应行
- 详细变更内容记录在 `概要设计.md` 的变更记录章节，**不**在 task.md 展开

### 2.7 集成测试 spec（st-api）

与业务 `c{n}` **分离**，ID 格式：`st-api-{kebab-case}`（通常与 change 目录名一致，如 `st-api-guanghuo-wage-register-audit`）。

集成测试服务名 = 根 `.flow/config.yaml` 中 `type: system-test`（或兼容名 `system-test` / `glm-system-test`）的 `name`，下记为 `{system_test_service}`。首次 `flow-codex-test-design` 可从 skills 模板 scaffold 并登记该服务。

**开发顺序**（追加在业务 spec 之后）：

```text
N. st-api-<change>（{system_test_service}，依赖 cX 或 —）
```

- 括号内服务名与 config `name` 一致（常见 `system-test`；存量项目可为 `glm-system-test`）
- 依赖引用业务 spec 时用 `c{n}`；全部业务完成后可写 `依赖 —`

**服务章节** `## {system_test_service}`：

```
> 状态：{emoji} {状态文本} | 分配日期：{date} | 模式：{mode} | 任务号：{id}

- [{x| }] st-api-<change>: 集成测试代码··
      边界：manifest test-plan 范围；JUnit + fixtures + test-support··
      依赖：cX 或 —··
      完成：{YYYY-MM-DD} commit {hash}   ← 或 local-only
```

- spec 权威在测试仓的 manifest + test-plan，**无 OpenSpec**
- `flow-codex-test-design` 创建条目；`flow-codex-test-report` 勾选完成

---

## 3. 操作规则

### 3.1 创建 task.md（flow:design）

1. 按本文档第 2 节格式规范生成 task.md
2. 概要设计须先有 **Spec | 服务 | 职责** 矩阵，每行恰好一个服务，再据此写 task.md
3. `开发顺序` 中的依赖引用必须用 spec ID；每行括号内一个服务名
4. 每个 spec 条目包含：spec-id、标题、边界、依赖（每个 spec-id 只出现在一个服务章节下）
5. 初始状态：所有 spec `[ ]`，服务头部 `📋 待开始 | 分配日期：—`
6. 初始检查清单：所有条目 `[ ]`

### 3.2 汇报完成（flow:report）

1. 将对应 spec 的 `[ ]` 改为 `[x]`
2. 在条目末尾添加 `完成：{date} commit {hash}`
3. **清除**该条目上旧的 `⚠️ 设计修正` 标记（已修正并完成，不再需要）
4. **重写**服务头部状态行（不追加）
5. 同步勾选相关检查清单条目
6. 更新元数据头 `updated`
7. 如变更通知中有本服务相关条目，处理后删除

### 3.3 变更重开 spec（flow:change）

1. 将 `[x]` 改为 `[ ]`
2. **清除**旧的 `完成：{date} commit {hash}` 行
3. 条目末尾添加 `⚠️ 设计修正（{date}）：{1行简述}，详见变更通知`
4. 同步**取消**相关检查清单条目（`[x]` → `[ ]`）
5. 在 `## 变更通知` 章节追加 1 行索引
6. 详细修正内容写入 `概要设计.md` 变更记录 + 子服务 `design.md` 变更记录段
7. 更新元数据头 `updated`

### 3.4 新增 spec（flow:change）

1. 在对应服务章节末尾追加新条目（格式同 2.3）
2. 同步更新 `开发顺序` 章节
3. 在变更通知中追加 1 行索引
4. **仅限全新工作范围**——已有 spec 能覆盖的变更走 3.3 重开流程

### 3.5 分配任务（flow:assign）

1. **替换**服务头部状态行为：`> 状态：🔄 开发中 | 分配日期：{date} | 模式：{内联/独立} | 任务号：{id}`
2. 不修改 spec 条目状态（那是 report 的职责）
3. 不追加历史分配记录

### 3.6 新增 hotfix（flow:hotfix）

**根 agent 执行**：

1. 在对应服务的 `### Hotfix` 子章节下追加条目：
   ```
   - [ ] hotfix-{YYYYMMDD}-{slug}: {问题简述}
         问题：{1行描述}
         修复：{待编码}
   ```
2. 在子服务使用 spec skills（如 openspec）创建标准 spec 目录 `hotfix-{YYYYMMDD}-{slug}/`，内含 proposal.md、design.md 等标准文件
3. 不影响 spec 条目和开发顺序
4. 提示用户使用 `/flow:assign <service>` 派发 hotfix（assign 识别 hotfix 条目，告诉子 agent 跳过设计阶段用户评审）

**子 agent 编码**：走 assign → receive（识别 type=hotfix → 跳过用户设计评审）→ apply（正常编码循环）→ report

**report 更新**：
- `[ ]` → `[x]`
- 追加 `完成：{date} commit {hash}` + `修复：{1行描述}`

---

## 4. 反例（来自真实 task.md 的退化案例）

| 反例 | 违反原则 | 正确做法 |
|------|---------|---------|
| 开发顺序写 `依赖3` 而非 `依赖 c3` | spec ID 是通用标识 | `依赖 c3` |
| `c4（register + aggregator）` 一行绑两仓 | 1 c = 1 仓库 | 拆成 c4 register、c5 aggregator 递增 |
| 开发顺序括号内多个服务名 | §2.2 每行一仓 | 每行恰好一个服务名 |
| c10 条目 15 行，4 个不同日期的 ⚠️ 交叉 | 重写优于追加 | 重开时重写条目，控制在 6 行内 |
| c18 `[ ]` + `~~完成：2026-05-11~~` 并存 | 重写优于追加 | 重开时清除旧完成记录 |
| glm-attendance 头部 6 行日期流水 | 权威单一来源 | 1 行当前状态，历史在 git log |
| 变更通知写详细修正内容，任务条目里又写一遍 | 权威单一来源 | 变更通知仅 1 行索引，详情在概要设计.md |
| 完成清单 c10 勾了 `[x]`，但 c10 条目是 `[ ]` 且还在追加用例 | 重写优于追加 | change 重开时同步取消清单 |
| Hotfix 与 feature spec 混排在同一列表 | 生命周期不同 | Hotfix 放独立 `### Hotfix` 子章节 |
| spec 条目换行不打双空格，预览时所有字段粘成一段 | markdown 硬换行 | 除最后一行外每行末尾 2 个空格 |
| ⚠️ 设计修正插在边界和依赖之间，破坏字段顺序 | 固定字段顺序 | ⚠️ 必须放最后一行 |
| 边界写成散文段落（3 行 200+ 字），超 6 行限制 | 边界 1 行 | 用紧凑枚举 + `；`分隔，细节放 design.md |
| spec 条目内展开已完成/待完成子列表，7+ 行 | 6 行限制 | 合并为 `进度：{一句话}`，详情放 design.md |

---

## 5. 格式约束速查

| 约束 | 规则 |
|------|------|
| 依赖引用 | `c{n}` 格式，禁止纯数字 |
| 日期 | `YYYY-MM-DD` |
| spec 条目最大行数 | 6 行（含空行） |
| 换行 | 条目内除最后一行外，每行末尾 **2 个空格**（markdown 硬换行），禁止依赖编辑器软换行 |
| 字段顺序 | 边界 → 依赖 → 完成 → ⚠️设计修正，不可调换 |
| 边界长度 | **1 行**，紧凑枚举（`；`分隔），禁止散文段落 |
| 服务头部最大行数 | 1 行（blocked by 除外） |
| 变更通知每行 | 1 行简述，不含详细修改内容 |
| spec ID 格式 | `c{序号}-{kebab-case}` |
| 集成测试 spec ID | `st-api-{kebab-case}`（仅 system-test 服务章节） |
| hotfix ID 格式 | `hotfix-{YYYYMMDD}-{kebab-slug}` |
