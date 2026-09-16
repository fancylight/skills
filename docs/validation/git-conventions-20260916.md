# Codex Git 规范交付验证（2026-09-16）

本次为单对话自查，不是独立 Agent 审核。实现前基线为 `8540d22f03bcf4427fd2d1cd5164e97ba67325a0`，沿用 `codex/adapter`，没有为实施创建新 worktree。

## 实际验证

- `codex/validate.ps1`：PASS，包含 Git 资源和关键 Skills 路由检查。
- `python -m unittest discover -s flow/scripts/tests -p test_flow_git.py -v`：17 项 PASS，34.110 秒。测试使用临时仓库和临时 worktree，结束清理，不修改业务仓。
- 覆盖真实提交/回执统计、全部提交类型、中文及技术标识、错误编号/分隔符/英文正文拒绝、缺编号/非法日期、绑定漂移、分支错误、无自动 upstream、非 Flow 无编号、存量例外作用域、多仓共用编号、worktree 隔离、受管与未受管命令、字面量 git -C/工作目录切换。
- Git 编排根目录首次初始化：仅已绑定的未跟踪 change.json 可随创建分支保留，额外用户文件仍拒绝。
- 临时仓库直接执行不规范的人工 Git 提交成功；交付统计将其列为来源未确认及 WARN，不阻断人工提交、不改历史。
- 安装/重复安装/撤销测试：PASS，保留其他 hook，重复安装不改变 hooks.json；实际全局重复安装也返回 `changed: false`。
- Windows 安装命令执行：真实运行生成的 commandWindows，输入 PreToolUse JSON 后返回预期 deny。
- `git diff --check`：PASS。

## 当前宿主接线

- 通过桌面内置 `codex-cli 0.154.0-alpha.6.2` 的 app-server `hooks/list` 只读检查，无新增任务或模型调用。
- skills 与 GLM 两个 cwd 均识别 `Flow Git conventions (flow-v1)`，`enabled: true`，`trustStatus: untrusted`，加载无错误。
- **尚未验证受信任后的完整工具调用拦截**：需用户在 `/hooks` 审核并信任该定义。未自动写 trust，未使用 bypass trust。当前可用的是 Skills 规则及校验/提交脚本，不能宣称 hook 自动拦截已启用。
- 原 GPT-6 guard 原先为 `enabled: false / trusted`，安装后相同。全局 config.toml 安装前后 SHA-256 均为 `AFD6EA15C5DEF443D10F8030842A2B6B10CFCB953CE64EC2DA261A11945D69A1`。
- 现有 guard 存在 TOML、本功能保存在 hooks.json；运行时提示同层两种来源合并。未复制 guard 或改变其配置，两者无重复 handler。
- 全局安装位置为 `C:/Users/chenk-u/.agents/skills`；用户级 hook 为 `C:/Users/chenk-u/.codex/hooks.json`。

## GLM 与边界

已同步 `C:/Users/chenk-u/code/glm/AGENTS.md` 和 `.flow/config.yaml`，移除项目级任务号 91099，启用逐需求身份、完整分支模式和中文提交。根目录非 Git 仓库，改动保存在本地，没有初始化 Git 或重命名存量需求。

没有改动旧 Claude 安装入口或共享原版 config/overview 模板；新模板通过 Codex 覆盖安装。没有修改 core.hooksPath 或新增 Git hook。任意脚本内部、别名和 write_stdin 不属于完整拦截保证；中文语义正确性仍由实施者自查。
