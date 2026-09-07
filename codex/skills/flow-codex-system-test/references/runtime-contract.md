# Runner 命令契约

命令均在 **集成测试仓** 根目录执行。测试仓路径从根 `.flow/config.yaml` 解析：

1. `type: system-test` 的服务，或
2. `type` 为 `system-test`，实际服务名从同一 config 条目动态解析

业务 suite 只能使用已认证 harness。平台维护者只能在隔离的临时 harness 副本中运行 `self-test/invoke-harness-self-test.ps1`，再用 `scripts/harness-certification.ps1 certify` 生成绑定受控文件哈希和 harness version 的认证；runner 每次执行前用 `verify` 复核，任一 harness 文件变化都会使旧认证失效。业务 change、正式 system-test 仓和 orchestrated runner 不得启用 self-test adapter，也不得临时修改 runner 或伪造认证。

```powershell
.\scripts\system-test.ps1 doctor -Change <change> -EnvFile .env.local
.\scripts\system-test.ps1 run -Change <change> -Suite <suite> -ExecutionMode <orchestrated|standalone> -EnvFile .env.local
.\scripts\system-test.ps1 cleanup -Change <change> -EnvFile .env.local
```

manifest 的 `configuration.source` 是唯一配置来源，`configuration.ownership` 只能是 `human` 或 `harness`。人工配置探针失败只输出 `[TEST_CONFIGURATION] BLOCKED` 与 `STOP_AWAIT_HUMAN_CONFIGURATION`；平台配置失败路由到独立 harness 修复，不猜测密码、不扫描或切换配置来源。PASS、FAIL、BLOCKED 都执行 cleanup 并保留原始报告索引。

上段 `configuration.source` 仅适用于 v1。v2 以配置中心 `configuration.provider/targets` 为唯一配置来源，
`environmentFile` 仅承载必要运行参数；Git 忽略的 human 本地配置可保留既有凭据，完整文件 hash 绑定快照。
测试夹具从 `FLOW_RESOLVED_MANIFEST` 定位同一配置中心，不复制连接账号。共享细则见 core 安装模板 `system-test/README.md`。
外部中间件只执行探针，不由 runner 启停或重建；managed 复用必须通过显式 identityProbe 和健康检查。
`runner.prepare` 负责本次 WireMock mapping 注册与响应契约验证，失败停止后续业务；cleanup 只回收本次数据、mapping、文件和已验证所属进程树。

独立 v2 运行可追加 `-ScenarioIds SMOKE-1`，过滤器与 JUnit 集合来自 canonical 派生契约，runner.command 消费
`${FLOW_TEST_FILTER}`、`${FLOW_TEST_REPORT_DIR}`。空选集、未知 ID、零匹配、缺报告、越界或 skipped 均失败。
部分运行 `fullSuite=false`，不能登记全量 PASS；standalone 不写 controller。

可选 `-OrchRoot` 或环境变量 `FLOW_ORCH_ROOT`（默认测试仓父目录 = Flow 编排根）。

`<suite>` 默认 manifest 的 `defaultSuites` 首项或 `api`。
由 `flow-codex-test` 委托时使用 `orchestrated`；用户直接复现默认 `standalone`，两者都不自行完成 Flow。

仓不存在时：先跑 `flow-codex-test-design`（会从 skills 模板 scaffold），不要临时拼凑命令。

## 证据路径

下表为 v1 路径。v2 每次运行使用 `changes/<change>/evidence/runs/<run-id>/`，其中 `index.md`、`runtime-result.json`、
`selection.json`（选场景时）、`junit/`、`logs/` 和业务证据均属于本次运行；不得覆盖旧全量证据。standalone 不覆盖根镜像。

| 类型 | 路径（相对测试仓） |
|------|----------------------|
| 运行时状态与日志 | `.runtime/<change>/` |
| Playwright | `.runtime/playwright-report/` |
| JUnit | `backend-tests/target/surefire-reports/` |
| 可提交摘要 | `changes/<change>/evidence/summary.md` |
| 当前运行索引 | `changes/<change>/evidence/current/index.md` |
| 失败归因报告 | `changes/<change>/evidence/current/failure-report.md`（仅 FAIL） |
| 原始与关联证据 | `changes/<change>/evidence/current/{junit,logs,wiremock,db}/` |
| 根镜像 | `.flow/changes/<change>/集成测试.md`（编排根） |
| SQL 计划证据（按需） | `changes/<change>/evidence/sql-plan/`（最终列表 SQL、分页 count SQL、脱敏 EXPLAIN） |

禁止将 secrets、cookies、token、数据库密码写入 evidence。

## SQL 计划验证（存在数据访问契约风险时）

1. 只执行 `test-plan.md` 已声明的只读 `EXPLAIN`，记录实际绑定后的列表 SQL 与分页 count SQL；不要由 Mapper 文本猜测框架包装 SQL。
2. 使用与验收场景相符的代表性参数/数据量；若环境无法代表高基数路径，记录为阻断，不以小样本 `EXPLAIN` 声称通过。
3. evidence 写明环境、时间、脱敏参数、访问类型与 rows 估算；禁止 secrets。非豁免 `DEPENDENT SUBQUERY` 或关键大表 `ALL` 为 FAIL。


## 发版 SQL 变更后重测

业务仓提交或 integration 窗口内重跑 release SQL 时：

以下动作仅在本次计划明确授权执行发版 SQL 时适用。只读验证或明确禁止业务 DDL 的 smoke 不执行这些写入；缺失 schema 记录具体阻断。

1. 确认 `fixtures/release/` 与服务仓 SQL 一致。
2. 本地 DB 重跑变更脚本后再声称 green。
3. 重启受影响服务。
4. 跑 manifest `apiTestFilter` 冒烟；未覆盖项须明示。

详见 `references/local-pitfalls.md`；项目若有 playbook，经 config 中测试仓 path 读取。
