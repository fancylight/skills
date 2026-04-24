# Flow Changelog

## 0.2.0 — 2026-04-24

### 新增（Agent 行为约束机制）
- `onboarding.md.tmpl` 增加「禁区」章节：明确允许/禁止的行为矩阵，以及越权时的处理方式。
- `assign.md.tmpl` 增加「红线提醒」：派任务时强制提醒 5 条越权停止规则。
- `receive.md` 增加「边界确认」步骤：子 agent 启动时必须向用户声明工作范围；增加 `blocked by` 硬约束（依赖未完成时只允许设计、禁止编码）。
- `report.md` 增加「越权行为自检清单」：5 项回溯检查，未通过必须在【遗留问题】中如实汇报。
- `child-config.yaml.tmpl` 增加 `constraints` 配置段：声明跨服务写入、数据库结构变更、用户确认等权限开关。
- `schema.md` 同步更新 `child-config.yaml` 的字段定义，增加 `constraints` 规范。

---

## 0.1.0 — 2026-04-22

### 新增
- 初始化项目 AI 上下文文档（根 `CLAUDE.md`、模块 `CLAUDE.md`）。
- 增加 Schema 规范文档（`docs/schema.md`）。
- 增加基础验证脚本（`scripts/validate.js`）。
- 增加 `CHANGELOG.md` 版本追踪。

### 优化
- 精简 `README.md`，去重信息统一指向 `CLAUDE.md`。
- 修正 `.gitignore` 为文档/模板项目适用。
- 移除所有命令文件与模板中的硬编码项目路径。
- 统一 `assign.md` 命令与 `assign.md.tmpl` 模板格式，删除命令内嵌的重复模板。
- 子 agent 配置模板化（新增 `templates/child-config.yaml.tmpl`）。
- 明确 `report` 命令的 git commit 检测规则（时间范围、任务号匹配）。
- 明确 `status` 命令状态判断优先级。
- `archive` 命令使用 Claude Code 文件操作替代 bash 命令，提升跨平台兼容性。
- 在 `init.md` 中标注 Tier 3 尚未实现。
- 为所有命令 YAML frontmatter 增加 `version` 字段。

### 规范
- 定义 `api.md` 与 `{service}-api.md` 的标准格式（YAML frontmatter + Markdown 表格）。
- 定义 `config.yaml`、tasks.md 元数据头的完整字段规范。
