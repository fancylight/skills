# Feedback · CDP playbook 规范

> **受众**：执行 `flow-codex-feedback` Discover / Trace 的 Agent。  
> **规范在本文件**；业务编排仓库 `{root}/.flow/cdp/` 只放**产物** playbook，其 `README.md` 仅做轻量索引（不写维护规则）。

## 1. 文档位置

| 层级 | 路径 | 职责 |
|------|------|------|
| 规范 | 本文件 + `flow/templates/cdp-playbook.md.tmpl` | 选用流程、何时新增、模板 |
| 产物目录 | `{root}/.flow/cdp/*.md` | 可复用的操作手册（如 `gbp-database-ops.md`） |
| 索引 | `{root}/.flow/cdp/README.md` | 表格索引 + 脚本列表；新增 playbook 后**顺手更新一行** |

`root` = 编排 `config.yaml` 的 `root_path`（子 agent 经 config 解析）。

CDP 内容 **不进** `local_rag`；业务规则仍走 `flow-codex-kb`。

## 2. 选用流程

1. 读 `{root}/.flow/cdp/README.md` 索引（目录不存在则调查日志记 `CDP：无目录`，不阻塞）
2. 按场景匹配 playbook，例如：
   - 私有云 GBP 查 PG/MySQL → `gbp-database-ops.md`
   - 公有云 MyDB → `mydb-sql-ops.md`
   - 业务页已登录 fetch → 索引对应项或 `scripts/cdp_*`
3. 读完整 playbook 再动手；**优先 API / Runtime.evaluate + fetch**，少 UI 自动化
4. 无匹配 → §4 缺口处理

## 3. 已知 playbook 登记（skill 侧提示，以各仓 README 为准）

| 场景关键词 | 典型文件名 | 备注 |
|------------|------------|------|
| GBP / 私有云 PG / middleware | `gbp-database-ops.md` | MySQL 常需 Tab + `middlewareType=mysql` |
| MyDB / 公有云 SQL | `mydb-sql-ops.md` | 若仓内尚无则按缺口处理 |
| 已登录业务页 fetch | 见仓内 README | 优先现成 `scripts/cdp_*.py` |

## 4. 缺口处理

- 调查日志：`CDP 缺口：{场景}`
- 向用户说明；**用户确认后**才新建 playbook
- 调查可先依赖用户手动 Network 参数 + 临时脚本，**不阻塞 Conclude**

## 5. 维护规则（写在 skill，不写在 `.flow/cdp/README`）

### 何时新增 playbook（须用户确认）

- 新环境 / 新鉴权 / 新 SQL API 模式，且可在后续 feedback 复用
- 某 CDP 路径在**两次及以上**反馈中重复踩坑

### 不单独建 playbook

- 一次性参数、单 feedback 结论
- 仅适用于单个 project 的数据
- **同一鉴权/API 模式**：合并进已有 playbook，禁止为每个环境 fork 一份副本

### 新增步骤

1. 从 `../flow-codex-core/assets/templates/cdp-playbook.md.tmpl`（源：`flow/templates/cdp-playbook.md.tmpl`）渲染 `{slug}-ops.md` 到 `{root}/.flow/cdp/`
2. 更新 `{root}/.flow/cdp/README.md` 索引表一行
3. 若有通用脚本，放编排仓库 `scripts/cdp_*.py` 并在 playbook 中引用
4. 在触发本次新增的 feedback 调查日志记录：`CDP playbook 新增：{filename}`

## 6. 安全

- 默认只读 SELECT；UPDATE/DELETE 由用户工单执行，skill **不自动**写库
- Token / cookie 勿写入 git 或调查报告正文（可用「已登录会话」描述）
