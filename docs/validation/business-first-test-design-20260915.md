# 业务用例先行与测试授权修复验证

本次只修改 Flow 框架，基线为 `81b5987c5a3203545bcdd4824a2d7ee270508dc5`。未读取或修改跨夜测试仓产物、未改其 controller，未运行跨夜业务测试；示例是框架回归夹具，不代表业务验收通过。

## 实施结果

- 同一 `test-cases.yaml` 增加 business：目的、配置前提、具体输入、操作、预期最终结果、独立依据、反例及证据边界。business 模式支持先生成业务预览，不要求技术绑定；审核补齐后才设计技术执行。
- test-plan 唯一生成区先展示业务用例、后展示技术附录，状态固定为设计预期/待执行。schemaVersion 仍为1；旧技术源能解析，但不能通过新的正式业务用例门禁。
- 正式产物门禁强制 business，设计/代码审核规则检查业务预期及实际观测能否验证它。脚本不会根据“字段齐全”判断业务覆盖合理。
- controller 支持用户追加授权、实施前重开设计和接纳新设计提交。追加授权不改阶段/版本/证据；重开保存旧审核，复核更新提交后旧报告失效，稳定testBaseline不变。迁移不允许夹带配置、夹具或代码，也不允许削弱必需场景。
- 用户可在原对话自查，无需新任务或子agent。只有用户要求先审批业务用例时等待意见，否则按已有授权完成自查后继续。

## 验证与证据

环境为 Windows，PowerShell 7.6.5 与 Windows PowerShell 5.1.26100.9444。使用真实临时 Git 仓和经过 self-test 认证的框架 harness，未使用业务环境。

| 检查 | 结果 | 可定位证据 |
|---|---|---|
| 业务草案无技术字段可预览；缺任一业务项拒绝；结果/反例/Y与N边界保留 | PASS | `flow/scripts/tests/test-business-case-design.ps1` |
| PowerShell 5.1/7 中文计划逐字节一致 | PASS | 同上；`business-ps7.log`、`business-ps51.log` |
| canonical 原有解析、确定性、Java绑定、漂移和required删除保护 | PASS | `flow/scripts/tests/test-validate-test-cases.ps1`、`canonical.log` |
| design可记录更高初始授权；纯技术映射不能通过正式设计；原SQL/污染/配置门禁 | PASS | `flow/scripts/tests/test-validate-test-artifacts.ps1`、`artifacts.log` |
| controller全生命周期与harness重试；新增授权和迁移允许/拒绝路径 | PASS | `flow/scripts/tests/test-flow-test-controller.ps1`、`controller.log` |
| 追加授权缺原话/来源/引用/绑定拒绝，降级/重放/原子写失败不改变状态；运行后升级保留运行证据 | PASS | `test-controller-design-authorization.inc.ps1`与主controller测试 |
| 旧state无grants可追加；设计重开保留旧审核，要求新审核；代码越界/必需场景降级拒绝 | PASS | 同上；覆盖真实Git提交及静态门禁 |
| 本地交付18项回归，含真实SQLite/CSV、JUnit与故障断言 | PASS | `codex/scripts/tests/test-local-delivery.py`，源版与全局安装版均18项通过 |
| 仓库skill规范、diff格式检查 | PASS | `codex/validate.ps1`、`git diff --check` |
| 全局安装skill与共享脚本 | PASS | 80个文件，生成协议按规范化换行比对，其余SHA256一致；`install-verification.log` |

日志和生成样例保留在 `C:/Users/chenk-u/code/self/flow-business-first-validation-20260915/`。该目录的 `test-plan.md` 可查看实际业务主体/技术附录输出；不存在业务执行PASS。

安装前备份：`C:/Users/chenk-u/.codex/backups/flow-skills/business-first-20260915-173019/`。

通用 skill-creator quick_validate 因当前 Python 缺 PyYAML 未运行成功；本仓要求的 codex/validate 已通过。本次按 flow-codex-check 的需求/文件/证据双向规则由当前实施者完成 self 检查，没有独立模型审核，不声明模型质量提升百分比。

## 存量change接入

原对话重新读取全局 `flow-codex-test-design/SKILL.md`、`flow-codex-test-verify/SKILL.md` 和 `flow-codex-core/references/test-controller.md`。对尚未实施的已审核设计：reopen-design → 补业务用例并生成预览 → 审核补齐 → 核对技术设计、静态校验、提交 → accept-design-revision → 新的design verify。继续用原稳定基线，不补造旧记录，不把旧PASS视为新规则通过。

原上限为design时，复核后仍保持design；只有实际收到更高授权时才用grant-authorization记录。若复核发现需要更改配置/夹具或已进入实施，则超出本次兼容迁移入口，须明确报告具体缺口，不能删除state绕过。
