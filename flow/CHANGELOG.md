# Flow Changelog

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
