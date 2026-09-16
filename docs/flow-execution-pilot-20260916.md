# Flow 执行改造与本地试点记录

框架已实现；跨夜选定试点通过，考勤展示完整集成验收未通过。不能据此宣称所有痛点已解决。全过程在当前对话完成，没有子 Agent、新 worktree、远端部署或历史改写。

## 实际抓住的问题

| 问题 | 原始证据与处置 | 当前结论 |
|---|---|---|
| 组织 ID 与项目 ID 被等同 | 复核考勤原有同名回归断言的 red.xml 与 green XML；新夹具使用不同 ID 并加入错误组织的干扰规则 | 既有缺陷红绿证据可复用；本次正式接口切片未通过，不能扩大结论 |
| 源码正确但 worker 构件仍旧 | 正式 DISPLAY-04 在启动前失败，日志为 Pinned build identity mismatch | 增加只读构件预检；构件在预算内重建，未在预算内再次运行该切片 |
| 把存储版本不变当成业务不变 | CN-01 三组业务断言通过，但 AfterAll 全等断言失败；逐字段核对仅 `_version` 与 `modify_time` 不同 | 只排除这两个存储字段，其他身份及业务字段仍精确比较；改动工时的反例仍被拒绝，修复后正式通过 |
| 环境失败后不能清楚恢复 | 旧指纹、已占用的配置服务端口及前置服务不可用均在试点遇到 | 失败保留，修复后在同一预算 resume；复用核实后的既有配置服务，不停止用户进程 |
| 跨版本状态完整性误报 | PowerShell 5 将 `>` 转义为 `\u003e`，PowerShell 7 默认保持原字符 | 增加按原始 JSON 核验既有签名的兼容路径；不放宽对内容改动的检查 |

## 两项实际试点

每项预算独立，均从第一次 prepare 开始；重试没有重置截止时间。

**考勤展示**：开始 18:08:48，截止 18:38:48（北京时间）。正式 DISPLAY-04 运行失败，选中夹具只有一组，按 ledger 清理完成。最后两分钟不再启动新运行。已有缺陷/修复版本回归证据核实，未修改业务修复提交 `5755f43d`。本次最终仍缺正式集成通过证据，继续需要明确追加预算，并为旧启动包装器补齐 `ValidateOnly` 转接。

- [当前执行摘要](C:/Users/chenk-u/code/glm/.flow/changes/attendance-refinement-display-20260930/execution-summary.md)
- [既有缺陷回归证据](C:/Users/chenk-u/code/glm/.flow/changes/attendance-refinement-display-20260930/evidence/org-id-fix-20260916/red.xml)
- [本次正式失败](C:/Users/chenk-u/code/glm/glm-system-test/changes/attendance-refinement-display-20260930/evidence/runs/20260916T102650-af3d9d1f/runtime-result.json)

**跨夜算法**：开始 18:37:32，截止 19:07:32；选定试点在截止前完成。沿用业务版本 `ea664417`，仅修改测试仓。

| 正式运行 | 时间 | 结果 |
|---|---:|---|
| CN-01 首切片 | 130 秒 | 三策略业务断言通过，收尾对照快照错误导致整轮 FAIL；证据保留 |
| 修复后 CN-01 | 121 秒 | 1 方法、3 策略，原始 JUnit 与结果自查 PASS，清理 PASS |
| CN-17 两阶段更正 | 146 秒 | 1 方法、3 策略；先非零，再同一原始 ID 的 OUT→IN 更正归零；身份、版本及清理 PASS |

最终当前结果为 **2 个集成场景 PASS、17 个 PENDING**。CN-17 并未把 CN-01 的既有结果覆盖掉；原失败仍在历史索引。全量 Flow 未完成。结果是当前 Agent 自查，不称独立审核。

- [当前执行摘要](C:/Users/chenk-u/code/glm/.flow/changes/attendance-cross-night-segment-settlement-20260930/execution-summary.md)
- [原失败 JUnit](C:/Users/chenk-u/code/glm/.flow/worktrees/cross-night-system-test-20260930/changes/attendance-cross-night-segment-settlement-20260930/evidence/runs/20260916T104609-a7280833/junit/TEST-com.glodon.glm.systemtest.crossnight.CrossNightSettlementApiTest.xml)
- [CN-01 原始断言](C:/Users/chenk-u/code/glm/.flow/worktrees/cross-night-system-test-20260930/changes/attendance-cross-night-segment-settlement-20260930/evidence/runs/20260916T105056-9971e194/CN-01/assertions.json)
- [CN-17 原始断言](C:/Users/chenk-u/code/glm/.flow/worktrees/cross-night-system-test-20260930/changes/attendance-cross-night-segment-settlement-20260930/evidence/runs/20260916T105412-86e22454/CN-17/assertions.json)

## 自动化与职责

- design/verify/review 在现有阶段核验关键判断的原始依据及反例；不增加用户阶段。文档齐全不能自动变成语义 PASS。
- `flow-test.ps1 prepare/advance/resume/status` 使用唯一 controller state；登记运行、锁定选择、归档证据、生成审核输入和当前摘要。审核模板初始为 PENDING，Agent 负责填写实际业务判断。
- 正式入口执行选中场景绑定、环境及只读构件验证；运行登记先于投递，重复分派有标记拦截，中断先恢复原运行。
- 版本及配置变化计算失效；仅在原审核有完整依赖映射且变更不相交时复用旧结果。清理问题不覆盖首个失败。
- 运行及阶段耗时由工具生成；30分钟截止时间跨修复保留。构建和人工诊断也受同一预算约束，不把换命令当续期。
- 旧服务分支可记录与根需求及实际 Git dir 绑定的存量例外，不把 Flow 降级成无编号临时任务；没有新增 Git hook。

旧需求首次接入仍有一次 runner 适配、认证、环境解析和提交成本；本次没有证明这些成本已降到足够低。考勤试点的预算中相当一部分用于接入与环境恢复，这是尚需用后续样本衡量的限制。

## 验证与安装

验证包括框架校验、controller 全量回归（含切片/恢复/授权/范围）、运行器回归、环境与实际构件预检、场景选择校验、Git 23 项回归，以及 PowerShell 5/7 签名兼容和篡改反例。临时 harness 使用隔离目录，合成测试回执只证明控制协议，不冒充业务运行证据。

全局目标为 `C:/Users/chenk-u/.agents/skills`。重复安装核对源文件哈希，保留原 Codex 配置及 hook；未修改信任记录。安装前副本保存在 `C:/Users/chenk-u/AppData/Local/Temp/flow-cycle-global-backup-e615d59e52644c90b5c0437d5a0b69a0`。

试点启动的 9 个原有容器均已恢复为初始停止状态；保留用户原有配置服务进程。没有清空共享队列或数据库。

**未验证范围**：考勤展示的正式接口集成通过、跨夜其余17个集成场景、真实进程被外部中断后的业务级恢复（框架已回归）、其他业务项目及长期节省时间的比例。后续不能用框架 PASS 代替这些验收。
