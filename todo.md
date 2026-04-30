# Flow Skill — 项目进度

> 追踪 Flow Skill 的开发进度。已完成项标 `[x]`，待完成项标 `[ ]`。

---

## 一、设计文档

- [x] 多阶段 AI 自动化开发流程（`多阶段AI自动化开发流程（含Mermaid流程图）.md`）
- [x] Flow Skill 设计文档 v3（`flow-redesign.md`）
- [x] 数据格式 Schema 规范（`flow/docs/schema.md`）

---

## 二、Slash Commands（`.claude/commands/flow/`）

- [x] `init.md` — 初始化（根模式 + 子模式）
- [x] `design.md` — 设计（根：概要设计 + task.md；子：spec 设计 + 自检）
- [x] `assign.md` — 生成子 agent 指令包
- [x] `receive.md` — 子 agent 接收任务
- [x] `report.md` — 子 agent 汇报
- [x] `status.md` — 查看需求进度
- [x] `verify.md` — 跨服务接口契约验证
- [x] `test.md` — 集成测试
- [x] `change.md` — 需求变更协议
- [x] `archive.md` — 归档已完成需求
- [x] `hotfix.md` — 轻量级 bug 修复

---

## 三、Skills（`.claude/skills/flow-*/`）

- [x] `flow-init/SKILL.md`
- [x] `flow-design/SKILL.md`
- [x] `flow-assign/SKILL.md`
- [x] `flow-receive/SKILL.md`
- [x] `flow-report/SKILL.md`
- [x] `flow-status/SKILL.md`
- [x] `flow-verify/SKILL.md`
- [x] `flow-test/SKILL.md`
- [x] `flow-change/SKILL.md`
- [x] `flow-archive/SKILL.md`
- [x] `flow-hotfix/SKILL.md`

---

## 四、模板（`flow/templates/`）

- [x] `config.yaml.tmpl` — 根 agent 配置
- [x] `child-config.yaml.tmpl` — 子 agent 配置
- [x] `onboarding.md.tmpl` — 子 agent 启动指南（根目录共享版）
- [x] `services.md.tmpl` — 服务地图
- [x] `overview-design.md.tmpl` — 概要设计
- [x] `tasks.md.tmpl` — 任务清单
- [x] `assign.md.tmpl` — 指令包
- [x] `工作流程.md.tmpl` — 子 agent 工作循环
- [x] `fix.md.tmpl` — hotfix change
- [x] `integration-test.md.tmpl` — 集成测试用例

---

## 五、基础设施

- [x] 项目入口 `CLAUDE.md`
- [x] 安装说明 `.claude/INSTALL.md`
- [x] 静态验证脚本 `scripts/validate.js`
- [x] `.gitignore`

---

## 六、Hooks（硬约束）— 待设计

> Slash Commands 和 Skills 是软引导（提示词注入），Hooks 是硬约束（拦截工具调用）。
> 当前 Flow Skill 缺少 Hooks 层，无法强制 agent 遵循工作流。

### 需要设计的 Hook 场景

- [ ] **PreToolUse `git commit`（子 agent）**：检查 `.flow/config.yaml` 是否存在，防止未初始化就提交代码
- [ ] **PreToolUse `git commit`（子 agent）**：检查当前是否有活跃 spec/change，防止无上下文提交
- [ ] **PreToolUse `Write/Edit`（子 agent）**：检查是否已执行 `receive`，防止未接收任务就开始编码
- [ ] **PostToolUse `git commit`（子 agent）**：提醒执行 `/flow:report`，或自动更新 task 状态
- [ ] **PreToolUse `Write`（子 agent）**：防止子 agent 越权修改根目录的 `概要设计.md`（只允许更新 task.md 的勾选状态）
- [ ] **Hook 配置模板**：提供 `settings.json` 片段，用户安装时合并到项目配置

### 待明确问题

- [ ] Hook 脚本放在哪里？`flow/hooks/` 还是 `scripts/`？
- [ ] Hook 如何随 skill 安装？需要修改 INSTALL.md
- [ ] Hook 是否需要区分根 agent 和子 agent 的不同规则？

---

## 七、验证与发布

- [ ] 在 GLM 项目根目录执行 `/flow:init`，验证根 agent 初始化
- [ ] 在 GLM 子服务目录执行 `/flow:init`，验证子 agent 初始化 + 向根注册
- [ ] 执行 `/flow:design`，验证概要设计 + task.md 生成
- [ ] 执行 `/flow:assign <service>`，验证指令包格式
- [ ] 在子服务执行 `/flow:receive` → `/flow:design`（子模式）→ `/flow:report`，验证完整循环
- [ ] 执行 `/flow:status`，验证进度聚合
- [ ] 执行 `/flow:verify`，验证接口契约校验
- [ ] `flow/commands/` 空目录处理（命令源文件在 `.claude/commands/flow/`，此目录是否保留？）

---

## 八、未来规划（不在当前版本）

- [ ] Beads 协议集成（替代文件通信，TaskStore 抽象层已预留）
- [ ] 安装脚本（自动化 junction link / copy）
- [ ] spec 自主拆分（知识库覆盖率达标后，子 agent 可自行定义 spec 粒度）
- [ ] 根 agent 自动启动子 agent（平台限制解除后）
