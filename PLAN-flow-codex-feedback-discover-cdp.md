# 改动方案：flow-codex-feedback Discover + CDP playbook 体系

> **状态**：已实施（2026-07-24）— 落地于 `self/skills`；须 `codex/install.ps1` 同步到 `~/.agents/skills`。  
> **不实施范围**：不擅自改业务编排仓库（`glm/.flow/cdp/` 仅作 playbook **产物目录**）；不写入 `local_rag` 知识库。  
> **背景**：2026-07-24 礼嘉 A09 反馈调查复盘（出勤 present 滞留、GBP CDP 查库、data-fix 等）。

---

## 0. 背景与共识

### 0.1 用户反馈（skill 设计）

1. 用户只输入**现象 + 大致接口**，agent 应**自行 Discover**：知识库、已有 feedback、CDP 能力 — **不是**用户的必填输入。
2. **CDP 维护规则与 playbook 模板**应落在 **feedback skill 仓库**（本 repo），**不是** `{root}/.flow/cdp/README.md` 的职责。
3. **`local_rag` 知识库**面向开发/测试的长期业务知识；**反馈结论、运维 SQL、单次 MERGE 失效**等**不**以「反馈流水账」形式灌进 KB。
4. 调查报告需支持 **`data-fix`**（不改代码、PG/中间表工单修复）及 **修改内容 / 根本原因 / 影响范围** 三段式。
5. 后续 feedback 可能使用**新的 CDP 模式**；skill 需提供可扩展的 playbook 模板与登记规则。

### 0.2 产物目录 vs skill 规范（分工）

| 层级 | 路径 | 职责 |
|------|------|------|
| Skill 规范 | `self/skills` → `flow-codex-feedback` + `flow/templates` | Discover 步骤、KB 路由、CDP 选用/维护/模板 |
| Playbook 产物 | 编排根仓库 `{root}/.flow/cdp/*.md` | 调查过程中**写出来**的具体操作手册（如 `gbp-database-ops.md`） |
| 调查结论 | `{root}/.flow/feedback/{id}/` | 单次反馈根因、data-fix SQL、验证表 |
| 业务知识库 | `local_rag` | 业务规则、表语义、服务边界（经 `flow-codex-kb` 且多数 feedback **零写入**） |

`.flow/cdp/README.md` **仅保留轻量索引**（链到已有 md + 脚本表），**不写**维护规则。

---

## 1. 目标

| # | 目标 |
|---|------|
| G1 | Intake 后增加 **Discover**：自动查 `_index`、KB 选篇、CDP playbook 选用 |
| G2 | Skill 内定义 **CDP 文档位置、选用流程、新增 playbook 条件、模板** |
| G3 | 报告模板支持 **`remediation=data-fix`** 与「数据修复说明」 |
| G4 | 收紧 **feedback → KB** 门槛，避免流水账 |
| G5 | `codex/validate.ps1` 可验证新增 references / 模板路径存在 |

---

## 2. 建议改动的文件（均在 `self/skills`）

| 优先级 | 文件 | 操作 |
|--------|------|------|
| P0 | `codex/skills/flow-codex-feedback/SKILL.md` | 增加 Discover；引用 `references/cdp.md`；`data-fix` 分流；硬性约束 |
| P0 | `codex/skills/flow-codex-feedback/references/cdp.md` | **新建**：CDP 位置、选用、维护规则、已知 playbook 登记表 |
| P0 | `flow/templates/cdp-playbook.md.tmpl` | **新建**：写入 `{root}/.flow/cdp/{slug}-ops.md` 的模板 |
| P0 | `flow/templates/feedback-report.md.tmpl` | 增加 frontmatter `remediation`；§数据修复说明 |
| P1 | `codex/skills/flow-codex-feedback/references/workflow.md` | `resolution` 增 `data-fix`；`remediation` 枚举 |
| P1 | `codex/skills/flow-codex-feedback/references/discover-kb.md` | **新建**（可选）：KB 3 跳选篇算法详述 |
| P1 | `codex/skills/flow-codex-kb/references/feedback-kb-rules.md` | 收紧：默认不写入；仅「新规则/新语义」 |
| P2 | `CHANGELOG.md` | 记录本变更 |

**不修改**（除非用户另开任务）：已安装的 `~/.agents/skills/`、`glm/.flow/cdp/gbp-database-ops.md` 等内容 playbook 正文。

---

## 3. SKILL.md 步骤变更（摘要）

```text
Intake
Discover   ← 新增
  ├─ 2.1 已有 feedback（_index + grep）
  ├─ 2.2 知识库选篇（见 references/discover-kb.md 或 SKILL 内表）
  └─ 2.3 CDP（读 references/cdp.md → 选用或登记缺口）
Orient
Trace      （Discover 之后）
Verify
Conclude   （含 remediation、KB 是否值得沉淀 一行）
Route
```

**用户必填**仍为：问题描述 +（接口 **或** 业务主键）。Discover 产出写入调查日志一轮。

---

## 4. references/cdp.md 要点（新建文件大纲）

### 4.1 文档位置

- Playbook **产物目录**：`{root}/.flow/cdp/`（`root` = 编排 `config.yaml` 的 `root_path`）
- **索引文件**：`{root}/.flow/cdp/README.md` — 仅表格索引 + 脚本列表，agent 新增 playbook 后**顺手更新索引一行**
- **规范与模板**：本 skill `references/cdp.md` + `flow/templates/cdp-playbook.md.tmpl`

### 4.2 选用流程

1. 读 `{root}/.flow/cdp/README.md` 索引
2. 匹配场景（示例）：
   - 私有云 GBP 查 PG/MySQL → `gbp-database-ops.md`
   - 公有云 MyDB → `mydb-sql-ops.md`
   - 业务页已登录 fetch → 索引中对应项或 `scripts/cdp_*`；无则走 §4.4
3. 读完整 playbook 再 CDP；优先 API，少 UI 自动化

### 4.3 维护规则（写在 skill，不写在 .flow/cdp/README）

**何时新增 playbook**（用户确认后）：

- 新环境/新鉴权/新 SQL API 模式，且可在后续 feedback 复用
- 某 CDP 路径在两次以上反馈中重复踩坑

**不单独建 playbook**：一次性参数、单 feedback 结论、仅适用于单个 project 的数据。

**新增步骤**：

1. 从 `flow/templates/cdp-playbook.md.tmpl` 渲染 `{slug}-ops.md` 到 `{root}/.flow/cdp/`
2. 更新 `{root}/.flow/cdp/README.md` 索引表一行
3. 若有通用脚本，放编排仓库 `scripts/cdp_*.py` 并在 playbook 中引用
4. 在触发本次新增的 feedback 调查日志中记录：`CDP playbook 新增：{filename}`

**边界**：CDP 内容 **不进** `local_rag`；业务规则仍走 KB 维护指南。

### 4.4 缺口处理

- 调查日志：`CDP 缺口：{场景}`
- 向用户说明；**用户确认后**才新建 playbook
- 调查可先依赖用户手动 Network 参数 + 临时脚本，不阻塞 Conclude

---

## 5. KB Discover 选篇（3 跳）

```
API 路径 → 服务架构/各服务/{service}.md
         → relates-to / 功能域/*.md
         → 数据设计/{table}.md
```

- 配置：`config.yaml` → `knowledge_base.path`
- 调查日志：`已读 KB：[相对路径列表]`
- Conclude 一行：`KB 沉淀：否（默认）/ 是（理由：澄清了 xxx 业务规则或字段语义）`
- 写入 KB 仍只经 `flow-codex-kb` + 用户确认；遵循 `知识库维护指南`「修 bug 规则不变 → 不更新」

---

## 6. 报告模板：data-fix

### frontmatter 增加

```yaml
remediation: pending   # pending | data-fix | code-fix | none
```

### 新增章节（`remediation=data-fix` 时必填）

```markdown
## 数据修复说明

修改内容:
根本原因:
影响范围:

### 预览 SQL
...

### 修正 SQL
...

### 验证 SQL
...
```

### resolution 表扩展

| resolution | remediation | 说明 |
|------------|-------------|------|
| data-fix | data-fix | 用户/工单执行 SQL；skill 不自动 UPDATE |
| fix-now | code-fix | 不变 |
| fix-later | code-fix | 不变 |

---

## 7. CDP playbook 模板

见 **`flow/templates/cdp-playbook.md.tmpl`**（§附录 A）。渲染目标：`{root}/.flow/cdp/{{slug}}-ops.md`。

---

## 8. feedback-kb-rules 收紧（P1）

- 删除或弱化「每条 feedback 一条已知问题」默认路径
- 改为决策树：
  1. 是否澄清**稳定业务规则**或**字段语义**？→ 候选 KB（功能域/数据设计）
  2. 是否仅为**单次脏数据 + 已 data-fix**？→ **跳过 KB**，feedback closed 即可
  3. 是否为 **CDP/运维手法**？→ 进 `.flow/cdp` playbook，**不进 KB**

---

## 9. 实施与安装

1. 在 `self/skills` 按 §2 改完
2. 跑 `codex/validate.ps1`
3. 用户执行 `codex/install.ps1`（或现有安装流程）同步到 `~/.agents/skills`
4. **不**自动覆盖各业务仓库内已有 `.flow/cdp/*.md`

---

## 10. 检视清单（实施后）

- [ ] `flow-codex-feedback/SKILL.md` 含 Discover，且 CDP 维护指向 `references/cdp.md` 而非 `.flow/cdp/README` 维护规则
- [ ] `references/cdp.md` 与 `cdp-playbook.md.tmpl` 存在
- [ ] `feedback-report.md.tmpl` 含数据修复说明
- [ ] `workflow.md` 含 `data-fix` / `remediation`
- [ ] `validate.ps1` PASS
- [ ] 未修改 `local_rag`、未在 skill 外擅自改 glm

---

## 附录 A：`flow/templates/cdp-playbook.md.tmpl`

```markdown
# {{title}}

> CDP playbook · 场景：{{scenario}} · 创建：{{created_date}} · 来源 feedback：{{feedback_id}}

## 适用场景

- **何时使用**：
- **何时不用**：

## 环境准备

- Edge：`--remote-debugging-port=9222`（或 `debug-edge.ps1`）
- 浏览器：须已登录 {{platform_url}}
- 页面状态：（例：GBP 数据库运维 → 已选环境/Tab/库）

## 核心方式

<!-- 优先写 API / Runtime.evaluate + fetch，少写 UI 点击 -->

### 鉴权

### 请求格式

### 连接参数如何获取

| 参数 | 获取方式 |
|------|----------|

## 安全与规范

- 默认只读 SELECT
- UPDATE/DELETE 由用户工单执行
- Token 勿提交 git

## 排查清单

| 现象 | 处理 |
|------|------|

## 参考脚本

- `scripts/{{script_name}}.py`（如有）

## 变更记录

| 日期 | 说明 |
|------|------|
| {{created_date}} | 初版，feedback {{feedback_id}} |
```

---

## 附录 B：礼嘉 A09 对方案的验证点（非模板内容）

| 项 | 结论 |
|----|------|
| Discover 应读 KB | `功能域/出勤分析.md` → 读侧只 summary |
| Discover 应读 CDP | `gbp-database-ops.md`；MySQL 需 Tab + `middlewareType=mysql` |
| data-fix | PG UPDATE present，`attendance_count=0` 守卫 |
| 不宜写 KB | 「7 月 present 滞留 20 天」为个案；通用规则「统计只读 summary」已在 KB |
| 不宜 MERGE 补算 | 调查 playbook 级结论，放 feedback 报告或 cdp 排查表，非 KB |

---

**文档版本**：2026-07-24 · 作者：编排复盘草案
