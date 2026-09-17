# Codex Git 命名与中文提交

本功能约束 Agent 的需求目录、分支和提交，不改变单对话 Flow，不安装 Git hook。一个根需求共用 `glw-数字`，新目录为英文短名加初始交期，分支为 `feature/<目录>`；非 Flow 修复分支为 `bugfix/<英文短名>-<创建日期>`。提交例子：`glw-92995 fix 修复执行记录分段`；明确无编号的非 Flow 任务可用 `chore 更新本地配置`。描述与正文使用中文，允许必要技术标识。

实施者使用公共规则 [git-conventions.md](../codex/skills/flow-codex-core/references/git-conventions.md)；脚本命令帮助：`python flow/scripts/flow-git.py --help`。业务项目的 Python 路径应先验证，不假设 WindowsApps 的 python shim 可运行。

## 安装与撤销

```powershell
./codex/install.ps1 -InstallGitHook -PythonPath '<已验证的 Python 3.11+ 绝对路径>'
```

安装默认复制全局 skills 到 `~/.agents/skills`；`-InstallGitHook` 将 Flow 定义写入用户级 `~/.codex/config.toml` 的独立标记块。可用 `-CodexHome` 指定 Codex 配置目录，`-TargetDir` 指定 skills 安装路径。重复执行不重复添加 handler，保留块外配置、GPT-6 guard 和 hook 信任/启停记录。旧 hooks.json 仅含 Flow 时自动迁移，原文件备份为 hooks.json.before-flow-inline，config.toml 备份为 config.toml.before-flow-inline；不复制旧来源的信任授权，迁移后检查 /hooks。旧 JSON 有其他 Hook 时在写入前拒绝迁移，避免擅自改变它们的来源。安装器使用 Python 3.11+ 的标准 TOML 解析器校验完整配置。

新建项目由 Codex config 模板启用 `conventions.agent_git: flow-v1`；已有项目明确接入时添加该字段，并逐需求建立 change.json，不在全局项目配置保存活动任务号。显式 bind 的工作目录也会启用检查。

撤销仅移除本功能拥有的 Codex handler，保留后来新增的其他 handler、需求元数据及本地回执：

```powershell
& '<Python绝对路径>' ./codex/scripts/install-git-hook.py --codex-home '<Codex配置目录>' --remove
```

撤销只移除 Flow 标记块及旧 JSON 中的 Flow handler，保留用户后续配置与其他 Hook；不使用整文件备份覆盖当前配置。只安装 Skills、不安装 hook 时省略 `-InstallGitHook`。安装器不替用户升级 PATH 中的 Codex CLI。

## 信任与覆盖边界

在当前桌面所使用的 Codex 运行时通过 `/hooks` 检查并信任 `Flow Git conventions (flow-v1)`。重新启动或刷新配置后检查；在确认 trusted/enabled 前，不宣称自动拦截生效。安装器不会代替用户设置 trust，也不会使用 bypass trust 参数。

官方依据：[Codex Hooks](https://learn.chatgpt.com/docs/hooks)。PreToolUse 支持 Bash/exec_command 路径；嵌套脚本内部操作及后续 write_stdin 不保证被再次检查。我们只识别字面量 Git 命令、工具工作目录和 git -C，不构建完整 shell 沙箱。用户终端/IDE 的手动 Git 不经过这项新增检查。

## 验收与统计

已授权的新需求 worktree 使用 `flow-git.py create-worktree --repo REPO --change CHANGE_JSON --path NEW_PATH --base origin/main`，也支持明确的本地基线。脚本从需求元数据取分支，在新工作目录写入独立绑定，不切换或重新绑定源目录。重复路径、重名分支、无效基线会被拒绝；不自动拉取、覆盖或设置 upstream。Hook 对直接创建命令提示这一正式入口，Agent 无需将操作转交用户终端。

```powershell
./codex/validate.ps1
& '<Python绝对路径>' -m unittest discover -s flow/scripts/tests -p test_flow_git.py -v
```

测试在临时 Git 仓及临时 worktree 中验证真实提交、编号/中文校验、分支保护、存量例外、工作目录隔离、手动提交、Windows hook 命令和安装撤销。不会在业务仓创建 worktree。

交付时对本次明确基线运行 `flow-git.py audit --repo REPO --base BASE --target HEAD`，汇总 Agent 合规数、违规数、来源未确认数、存量例外数。回执仅记录公共脚本提交，来源未知的提交不能当成自动拦截成功或失败的证据。消息含中文仅为机械检查，仍需自查中文语义与修改一致。
