# 首轮交付本地闭环验证（2026-09-15）

本次实现将运行约定收敛为独立预期、最小真实链路、受影响重验和当前构件证据汇合。默认单对话，阶段顺序保持；自查标明 self，不制造独立身份。正式测试 controller 的状态、权限、租约和版本约束未修改。

## 实现

- `flow-codex-check/scripts/local-delivery.py` 实际执行项目 argv 命令，独立新目录采集 JUnit、文件/数据证据、退出码和耗时；正确基线通过后才执行选定故障参数。`check` 只读重验 XML、场景和构件/证据摘要。结果始终注明 local-declared-scenarios、flowComplete=false。
- `validate-test-cases.ps1 -ExportJson` 复用原 canonical 校验，增加标准 JSON 导出，无新场景源。`validate-test-artifacts.ps1` 的可选本地结果参数只调用 check，不运行项目测试；未传参数的旧接口保持。
- 安装器分发 Python 执行器与公共校验脚本，排除 Python 缓存，并在安装后的正式测试协议保留 Codex 单对话指引。
- 业务入口、阶段 skills 和当前状态/交接规则链接同一精简参考；没有新 skill、新 controller phase、CI、后台服务或新 worktree。

## 实际验证

临时安装：`C:/Users/chenk-u/code/self/flow-local-delivery-stage-20260915`。安装后的 Python 执行器及 PowerShell 校验器执行 18 项测试，全部通过；使用 Python 3 标准库、Windows PowerShell 5.1。测试自建临时 Git 夹具，不是 worktree，不使用业务服务、外部数据库或 Docker。

真实样例：JSON 输入 quantity=7，经参数绑定写入 SQLite，查询后导出 CSV，再断言最终内容。故障参数将 quantity 改为0，真实业务断言失败并由执行器识别 caught。原始 SQLite、CSV、JUnit 和 receipt 保存在 `C:/Users/chenk-u/code/self/flow-local-delivery-final-20260915/test_real_roundtrip_probe_and_readonly_check/evidence`。

失败用例覆盖：基线业务失败停止 probes、无 XML、skipped、缺必要方法、缺消费端文件、错误未捕获、error 不计捕获、错误断言不计捕获、命令超时、旧 revision、未提交源码、被忽略构件变化、场景漂移、证据篡改、手改 PASS 不掩盖失败 XML、路径越界及拒绝覆盖首次运行。各用例原始产物在上述 evidence 根按测试名保留。测试数量是机制回归数量，不是业务场景通过率。

既有 `test-validate-test-cases.ps1` 通过；`test-validate-test-artifacts.ps1` 原始测试在 PowerShell7 中生成夹具、PowerShell5 中消费时失败，修改前 HEAD 也可复现，原证据 `C:/Users/chenk-u/AppData/Local/Temp/flow-baseline-readonly-pp5chcyn/baseline.log`。已仅修测试宿主选择，生成和消费统一到当前 PowerShell，原正反例通过。生产校验没有放宽内容匹配。正式结果校验器与本地执行器的接线正反例也通过：相同 canonical 场景的有效结果可汇合，篡改文件后由正式校验入口拒绝。

## 边界

这是可运行、可复核的本地通用机制和真实小样例，未宣称 GLM 或其他业务仓已经接线通过。实际需求由当前 Codex 在获授权的业务/测试仓登记同一 canonical 场景与实际构件，将已有测试命令接入并运行，不把待填模板当作业务验收。局部测试不能证明实际部署、事务、MQ、浏览器或容量；按需求接入相应真实观测。

本地 receipt 不是密码学受信签名；操作者若同时伪造代码和报告，纯本地脚本不能证明其真实性。仍需审查独立预期和实际测试实现。CI 强制未接入，GPT-6 质量/效率改善及长期缺陷指标尚未验证。当前主执行者实施、只读自查和测试，未使用子 agent。
