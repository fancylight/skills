# Flow 灵活交付 MVP 验证（2026-09-11）

候选的安装覆盖阻断已修复：工程质量资源完整，apply/feedback 与现有全局内容一致。Git 范围盘点、分发和 GLM 隔离适配测试通过；真实业务冒烟与双模型回放仍未完成。未 push、未更新全局安装、未打通过标签。

## 验证对象与范围

- Skills：`caaaa1b`，验证分支 `codex/flow-flexible-delivery-mvp`，工作区 `C:/Users/chenk-u/code/self/skills-flow-mvp`。
- GLM：既有冒烟基线 `3399d48`、接线 `301b43f`，验证分支 `codex/flow-service-reuse-mvp`，工作区 `C:/Users/chenk-u/code/glm/glm-system-test-flow-mvp`。
- 后续阻塞修复从原源仓审查并提取 24 个必要的 Codex 工程质量文件及改动，另增加 Codex 分发回归；没有复制 Claude 入口或其他架构/运行产物。未修改业务源码或运行适配实现，两个原工作区的既有未提交内容保留。
- 环境：Windows、PowerShell 5.1 运行 GLM 脚本、捆绑 Python 运行 Git 回归。由主 agent 执行；用户撤回子 agent 授权后未创建或使用任何子 agent。

## 结果

| 检查 | 结论 | 实际输入与断言 |
|---|---|---|
| Git 范围 | PASS | `test-delivery-scope.py` 两项真实临时 Git 仓回归：已提交/暂存/未暂存/未跟踪、中文空格路径、删除、重命名按删除+新增、二进制、非 HEAD target、非法 revision；逐文件比较检查前后的文件及 Git 元数据均未改变。 |
| Skills 校验 | PASS | 候选工作区执行 `codex/validate.ps1`；临时安装后检查实际输出资源。 |
| 全局安装差异 | PASS | 修复后对比 `C:/Users/chenk-u/.agents/skills`：新增 6、删除 0、内容变化 16、仅编码/换行变化 53。剩余内容变化对应灵活交付规则，以及既有安装器的“子 agent→执行 agent”术语替换；apply/feedback 全目录规范化内容、3 个质量资源与全局一致。 |
| 工程质量基线 | PASS | `test-engineering-quality-distribution.ps1 -BaselineDir C:/Users/chenk-u/.agents/skills` 检查 12 个入口、资源与现有安装；`test-check-java-style.ps1 -JavaExecutable D:/jdk-21.0.8/bin/java.exe` 使用 Checkstyle 14.1.0 实际执行 18 项回归，涵盖新增/历史违例、移动行、重命名、非法输入及工具缺失。 |
| GLM 原 runner | PASS（复用证据） | 复用此前 14 项真实自测输出；当前认证器重新校验完整证据并通过。harness revision 精确匹配 `a8f8e2fc369c8e4150024f4365a164edd1ed998d05ea3269d62c78554cc3e4ad`，没有声称重跑 14 项。 |
| GLM 复用路由 | PASS | `test-service-reuse.ps1`：doctor/up/run 参数分派、非 SMOKE-1 和 orchestrated 拒绝、无效认证拒绝、首次失败后不重试。 |
| GLM 启动适配 | PASS（隔离测试） | 新增 `test-service-reuse-adapter.ps1` 执行未修改的启动循环及真实 Git/构件/配置摘要逻辑。验证已有进程不启动、只调度缺失服务、构件变动先于健康检查被拒绝、配置变动不被接管、首次 preflight 失败停止后续服务和业务执行。进程与 HTTP 为替身，不能等同真实服务验收。 |
| GLM 真实路径 | UNVERIFIED | Python 依赖映射修复并验证全部固定版本后，正式入口再次启动检查：Config Center 就绪，真实 preflight PASS，upload-receiver 就绪；WireMock 18080 拒绝连接，停在契约准备，未进入业务 SMOKE-1。查明所需 WireMock/ES 既有容器已停止；用户明确授权恢复后工具仍拒绝启动，待外部恢复。 |
| GPT-6 / GPT-5.6 Sol 语义与效率 | UNVERIFIED | 用户禁止子 agent；8 次独立会话回放未执行。当前会话知道期望结果，自查不能充当盲测或证明跨模型兼容。 |

## 当前修复与剩余运行边界

已将现有安装使用的工程质量规则、检查器、模板与 Codex 入口引用纳入候选源文件，并保持原源仓不变。新安装结果不删除质量资源、不撤销 apply/feedback 引用。分发回归同时检查源文件与安装结果，防止仅在全局目录手工补文件而未修复后续安装。

隔离工作区通过 `.local/tools/python` junction 复用原工作区既有依赖，未重新下载或安装第三方包。实际 import 和 metadata 检查确认 PyYAML 6.0.2、PyMySQL 1.1.1、psycopg/psycopg-binary 3.2.10、pymongo 4.14.1、pika 1.3.2、openpyxl 3.1.5。首次缺包失败保留为历史记录；修复后真实配置、Mongo 副本集事务读取及 schema preflight 已通过。

新阻断为 `compose-wiremock-1`（18080）和 `es`（9200）已停止，镜像/端口已从 Docker 元数据核对。自动审批在明确授权前后两次拒绝 `docker start compose-wiremock-1 es`，仅返回 `blocked by policy`，没有执行启动或修改中间件。本轮业务冒烟仍为 0 次。不能将配置中心和 preflight 就绪登记为业务闭环 PASS。

## 发布边界

2026-09-11 使用 `git ls-remote` 确认远端 `origin/codex/adapter` 为 `34ac185d5354a21769a3c8c362fd749b95deff5a`，与本地跟踪引用一致。`caaaa1b` 比它多 10 个提交，其中 9 个为本轮之前的提交。新分支保留这段历史，后续推送前须明确这些提交的发布范围。GLM 当前没有配置 remote，不仅是缺 upstream。

本分支定位为面向高能力模型的候选验证版本，未证实 GPT-6 或 GPT-5.6 Sol 兼容性、效率优势。不因分支命名或静态检查通过而打稳定版本标签。

后续最小动作：由用户在本机恢复两个已明确授权的容器后，继续一次启动检查及 SMOKE-1；模型语义验收可由用户在目标模型的新主会话中执行一个实际修复闭环，不依赖主子 agent 工作流。发布与全局安装继续由用户根据具体结果决定。

## 原始证据

- Skills：`C:/Users/chenk-u/code/self/flow-mvp-evidence/` 下 `git-scope-test.log`、`validate.log`、`installation-diff.json`，以及 `installed-skills/` 候选安装目录。
- 修复后 Skills：同目录 `installation-diff-fixed.json`、`install-fixed.log`、`installed-skills-fixed/`、`java-style-summary.json`。Java 原始 XML 与逐例结果所在目录由 summary 的 `artifacts` 字段记录。
- GLM：`C:/Users/chenk-u/code/glm/glm-system-test-flow-mvp/.runtime/config-center-services/evidence/mvp-20260911/` 下 `certify.log`、`certification.json`、`dispatch-self-test.log`、`adapter-self-test.log`、`up.log`；启动日志在该工作区 `.runtime/config-center-services/`。
- 修复后 GLM：同 evidence 下 `mvp-fix-20260911/up.log`，preflight 与首次 WireMock 失败细节在 `.runtime/config-center-services/evidence/`。
- 复用的 14 项自测原始证据：`C:/Users/chenk-u/code/glm/glm-system-test/.runtime/config-center-services/evidence/flow-reuse-validation-20260911/`。运行输出不进入本轮代码提交。
