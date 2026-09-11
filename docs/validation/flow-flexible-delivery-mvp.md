# Flow 灵活交付 MVP 验证（2026-09-11）

当前候选尚不满足全局安装条件。Git 范围盘点、安装资源生成和 GLM 隔离适配测试通过；全局安装差异有明确偏差，真实业务冒烟与双模型回放未完成。未 push、未更新全局安装、未打通过标签。

## 验证对象与范围

- Skills：`caaaa1b`，验证分支 `codex/flow-flexible-delivery-mvp`，工作区 `C:/Users/chenk-u/code/self/skills-flow-mvp`。
- GLM：既有冒烟基线 `3399d48`、接线 `301b43f`，验证分支 `codex/flow-service-reuse-mvp`，工作区 `C:/Users/chenk-u/code/glm/glm-system-test-flow-mvp`。
- 本轮只增加回归测试与验证记录；未修改业务源码或运行适配实现。两个原工作区的既有未提交内容保留。
- 环境：Windows、PowerShell 5.1 运行 GLM 脚本、捆绑 Python 运行 Git 回归。由主 agent 执行；用户撤回子 agent 授权后未创建或使用任何子 agent。

## 结果

| 检查 | 结论 | 实际输入与断言 |
|---|---|---|
| Git 范围 | PASS | `test-delivery-scope.py` 两项真实临时 Git 仓回归：已提交/暂存/未暂存/未跟踪、中文空格路径、删除、重命名按删除+新增、二进制、非 HEAD target、非法 revision；逐文件比较检查前后的文件及 Git 元数据均未改变。 |
| Skills 校验 | PASS | 候选工作区执行 `codex/validate.ps1`；临时安装后检查实际输出资源。 |
| 全局安装差异 | FAIL | 对比候选安装目录与当前 `C:/Users/chenk-u/.agents/skills`：新增 6、删除 3、字节变化 78；其中 50 处仅编码/换行差异，28 处内容变化。删除项和部分覆盖超出本轮交付预期，见下文。 |
| GLM 原 runner | PASS（复用证据） | 复用此前 14 项真实自测输出；当前认证器重新校验完整证据并通过。harness revision 精确匹配 `a8f8e2fc369c8e4150024f4365a164edd1ed998d05ea3269d62c78554cc3e4ad`，没有声称重跑 14 项。 |
| GLM 复用路由 | PASS | `test-service-reuse.ps1`：doctor/up/run 参数分派、非 SMOKE-1 和 orchestrated 拒绝、无效认证拒绝、首次失败后不重试。 |
| GLM 启动适配 | PASS（隔离测试） | 新增 `test-service-reuse-adapter.ps1` 执行未修改的启动循环及真实 Git/构件/配置摘要逻辑。验证已有进程不启动、只调度缺失服务、构件变动先于健康检查被拒绝、配置变动不被接管、首次 preflight 失败停止后续服务和业务执行。进程与 HTTP 为替身，不能等同真实服务验收。 |
| GLM 真实路径 | UNVERIFIED | 有效认证后只执行一次正式入口 `up -ReuseServices`。Config Center 成功启动；Python preflight 导入 `pika` 失败，未进入业务 SMOKE-1。无重试。 |
| GPT-6 / GPT-5.6 Sol 语义与效率 | UNVERIFIED | 用户禁止子 agent；8 次独立会话回放未执行。当前会话知道期望结果，自查不能充当盲测或证明跨模型兼容。 |

## 安装阻断与真实运行归因

当前全局版本包含尚未纳入候选提交的工程质量改动。候选安装器会删除 `flow-codex-core/assets/scripts/check-java-style.ps1`、`flow-codex-core/assets/templates/engineering-quality.md`、`flow-codex-core/assets/templates/java-need-braces.xml`，同时删除全局 apply/feedback 入口对工程质量规则的引用。虽然本轮交付提交未改 apply/feedback，但直接全局安装会覆盖这些既有内容。应先把这些既有变化整理为已审查的发布基线，再重验安装差异；不能直接安装当前候选，也不能混入整个原脏工作区。

真实运行阻断属于本轮隔离工作区的准备缺口：原工作区存在 `.local/tools/python/pika`，新工作区只连接了固定构件并复制 resolved manifest/build 记录，未带入该 Python 依赖目录。不是业务失败，也不是原工作区缺依赖。遵守首次失败停止约定，未补装或再次启动测试。本轮创建的 Config Center 进程树经 PID 与启动时间核对后清理；未停止原工作区进程，首次失败日志保留。

## 发布边界

2026-09-11 使用 `git ls-remote` 确认远端 `origin/codex/adapter` 为 `34ac185d5354a21769a3c8c362fd749b95deff5a`，与本地跟踪引用一致。`caaaa1b` 比它多 10 个提交，其中 9 个为本轮之前的提交。新分支保留这段历史，后续推送前须明确这些提交的发布范围。GLM 当前没有配置 remote，不仅是缺 upstream。

本分支定位为面向高能力模型的候选验证版本，未证实 GPT-6 或 GPT-5.6 Sol 兼容性、效率优势。不因分支命名或静态检查通过而打稳定版本标签。

后续最小动作：整理安装基线；为隔离工作区补齐原有 Python 依赖映射后，在获得重试范围确认时再运行一次业务冒烟；模型语义验收可由用户在目标模型的新主会话中执行一个实际修复闭环，不依赖主子 agent 工作流。发布与全局安装继续由用户根据具体结果决定。

## 原始证据

- Skills：`C:/Users/chenk-u/code/self/flow-mvp-evidence/` 下 `git-scope-test.log`、`validate.log`、`installation-diff.json`，以及 `installed-skills/` 候选安装目录。
- GLM：`C:/Users/chenk-u/code/glm/glm-system-test-flow-mvp/.runtime/config-center-services/evidence/mvp-20260911/` 下 `certify.log`、`certification.json`、`dispatch-self-test.log`、`adapter-self-test.log`、`up.log`；启动日志在该工作区 `.runtime/config-center-services/`。
- 复用的 14 项自测原始证据：`C:/Users/chenk-u/code/glm/glm-system-test/.runtime/config-center-services/evidence/flow-reuse-validation-20260911/`。运行输出不进入本轮代码提交。
