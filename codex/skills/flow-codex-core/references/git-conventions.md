# Codex 需求命名与 Git 提交

适用于已接入 `conventions.agent_git: flow-v1` 的项目及显式绑定的工作目录。规则作用于 Agent；不安装 Git hook，不限制用户从终端/IDE 手动提交。不要求多对话，不新增 Flow 阶段。

## 唯一需求身份

首次 design 先明确真实需求号、中文标题、英文 kebab-case 短名和预计交期 YYYYMMDD。已有讨论能确定的直接复用，只询问缺失值；不编造编号/交期。英文短名简洁表达业务需求，不用 spec ID、模型名或临时方案代替。

使用 core 的 `assets/scripts/flow-git.py`（下文记作 SCRIPT），以已验证可用的 Python 3.10+ 执行：

```text
python SCRIPT init --root ROOT --issue glw-92995 --title 考勤展示优化 --slug attendance-refinement-display --delivery-date 20260930
```

生成 `.flow/changes/attendance-refinement-display-20260930/change.json`：version、requirement_id、title、slug、delivery_date、change_name、branch、legacy。完整分支为 `feature/attendance-refinement-display-20260930`。这是命名元数据，不是提前生成方案；首次 design 仍只做领域发现。延期不修改初始交期、目录或分支。

task、概要设计、业务和 st-api spec 必须读取这一身份；一个根需求全部提交贯穿同一需求号。根配置只保存格式 `branch_pattern: feature/{change_name}`、`commit_format: {requirement_id} {type} {description}`，禁止项目级固定 task_id。分支模式只渲染一次，文档使用元数据的完整 branch。

## 工作目录绑定与写操作

```text
python SCRIPT bind --repo REPO --change ROOT/.flow/changes/CHANGE/change.json
python SCRIPT check-branch --repo REPO
python SCRIPT create-branch --repo REPO --base main
python SCRIPT create-worktree --repo REPO --change ROOT/.flow/changes/CHANGE/change.json --path NEW_PATH --base origin/main
python SCRIPT switch-branch --repo REPO --branch feature/CHANGE
python SCRIPT check-commit --repo REPO --message-file MESSAGE_FILE
python SCRIPT commit --repo REPO --message-file MESSAGE_FILE
python SCRIPT audit --repo REPO --base START_REVISION --target HEAD
```

- bind 将引用保存在该工作目录的实际 Git dir，worktree 之间隔离；不会 checkout。已有不同绑定时先核对任务，用户已授权切换任务才能 `--replace`。
- 用户已授权创建新需求 worktree 时使用 create-worktree。直接读取 change.json 创建其完整分支并绑定新工作目录，不必先绑定或切换源目录；源目录已有任务绑定及未提交文件保留。必须明确新路径和已存在的本地/远端跟踪基线（main、origin/main 或完整 refs/heads/...、refs/remotes/...），有歧义时使用完整引用；不自动 fetch、不设置 upstream。目标路径已存在或分支重名即拒绝，不覆盖、不重置。绑定失败保留已创建目录并按错误提示 bind、check-branch 恢复；不能重复创建或让用户手动绕过 Hook。此入口仅创建新分支，挂载已有分支及移动 worktree 须按具体任务另行审查。
- 存量 Flow 服务分支与根需求分支不同且已核实时，可用 `bind --change <change.json> --existing` 保留当前分支。仅允许 legacy 需求；例外绑定根需求身份、原根分支及本 Git dir，不能复制到其他工作目录或用于新需求。
- 开始修改前执行 check-branch；不匹配先说明原因，不能静默切换。新分支在用户授权创建后用 create-branch，显式给出已有本地基线（GLM 使用 main），禁止自动 upstream。要求干净工作区，唯一例外是本次 init 创建且已绑定的未跟踪 change.json；先创建分支再写领域文档。已有正确分支直接使用。
- commit 前检查 diff，并用显式路径暂存本任务文件，检查完整暂存区不混入其他任务。消息写 UTF-8 文件；脚本不代替文件范围审核，不自动 stage、push、amend 或修改历史。失败先查输出及 HEAD，不盲目重试提交。
- 恢复已授权的既有需求分支时，使用 switch-branch，显式目标必须与绑定一致且本地已存在。脚本拒绝已跟踪文件的未提交改动和进行中的合并/变基/拣选；未跟踪或被忽略的测试证据可原样保留，由 Git 检查实际路径冲突，并禁止覆盖被忽略文件。不新建或重置分支、不猜远端分支、不自动 stash、清理或暂存证据。成功后检查绑定分支；不要求用户手动切分支来绕过 hook。
- 新建非 Flow 修复：`bind --repo REPO --adhoc --branch bugfix/fix-name-20260916 [--issue glw-92995]`；无真实需求号时省略 issue。脚本使用显式日期，Agent 根据创建当天填写。已有非 Flow 维护分支使用 `--adhoc --existing` 保留当前分支。不能把已绑定 Flow 需求改成 adhoc 来省略编号。
- 根编排目录不是 Git 仓库时只维护 change.json，不初始化 Git；分别绑定真正的业务/测试/文档仓库。
- merge、rebase、cherry-pick、revert 等复杂写操作不由普通提交入口处理。若任务明确需要，先形成针对该操作的具体方案；不能为绕过 hook 转入 Python、交互 shell 或临时关闭检查。

## 提交消息

```text
glw-92995 feat 增加考勤执行记录展示
glw-92995 fix 修复 AttendanceService 分段查询
glw-92995 docs 更新测试结果
chore 更新本地配置
```

类型：feat、fix、docs、test、refactor、perf、style、build、ci、chore、revert。固定前缀及类型之外的描述使用中文，必要的 API/类名可保留英文；正文如有也使用中文说明。编号、类型、描述以单个空格分隔，不加冒号或竖线。无编号示例仅用于明确的非 Flow 无编号任务。

脚本检查类型、准确编号、分隔格式和中文字符；Agent 负责描述的中文语义及与真实改动一致，不能靠一个中文字符凑校验。

## 存量与量化

已有需求没有 change.json 时，只接入用户正在处理的需求：核对 task/配置及真实分支后执行 `adopt --change-dir DIR --repo EVIDENCE_REPO --issue ID --title 中文标题`，记录原目录、原分支、证据仓为该需求例外。不要批量扫描迁移或虚构旧交期。其他服务仍须匹配此完整分支，不能把任意当前分支自动列为例外。

脚本提交成功会在 Git dir 写入本地回执。audit 对明确的起止 revision 统计 agent_pass、agent_fail、unclassified、legacy_exceptions；仅回执确认的本次提交参与 Agent 合规计数，其他提交不推断作者身份，不合规时只 WARN。复制仓库导致回执缺失时标记 unclassified，不能据此宣称全部 Agent 提交通过。只读 check 不执行 bind/adopt。

## Codex hook 边界

安装器显式启用 PreToolUse，识别受管项目中的字面量 Git 分支/提交命令并转向公共脚本；普通读取、暂存及未接入项目不受新规则影响。支持工具 cwd/workdir 和 git -C；不是完整 shell 解释器，任意脚本内部、别名和 write_stdin 输入不保证拦截。Agent 仍须遵守上述入口，交付时运行 audit。

Hook 定义需由用户在 Codex `/hooks` 信任；安装不写信任状态、不覆盖其他 hook/GPT-6 guard。未信任时脚本和 Skills 仍可用，但必须如实报告自动拦截未启用。安装/撤销与验证见仓库 `docs/git-conventions.md`。
