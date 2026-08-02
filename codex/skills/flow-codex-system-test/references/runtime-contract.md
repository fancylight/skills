# Runner 命令契约

命令均在 **集成测试仓** 根目录执行。测试仓路径从根 `.flow/config.yaml` 解析：

1. `type: system-test` 的服务，或
2. `type` 为 `system-test`，实际服务名从同一 config 条目动态解析

```powershell
.\scripts\system-test.ps1 doctor -Change <change> -EnvFile .env.local
.\scripts\system-test.ps1 run -Change <change> -Suite <suite> -ExecutionMode <orchestrated|standalone> -EnvFile .env.local
.\scripts\system-test.ps1 cleanup -Change <change> -EnvFile .env.local
```

可选 `-OrchRoot` 或环境变量 `FLOW_ORCH_ROOT`（默认测试仓父目录 = Flow 编排根）。

`<suite>` 默认 manifest 的 `defaultSuites` 首项或 `api`。
由 `flow-codex-test` 委托时使用 `orchestrated`；用户直接复现默认 `standalone`，两者都不自行完成 Flow。

仓不存在时：先跑 `flow-codex-test-design`（会从 skills 模板 scaffold），不要临时拼凑命令。

## 证据路径

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

1. 确认 `fixtures/release/` 与服务仓 SQL 一致。
2. 本地 DB 重跑变更脚本后再声称 green。
3. 重启受影响服务。
4. 跑 manifest `apiTestFilter` 冒烟；未覆盖项须明示。

详见 `references/local-pitfalls.md`；项目若有 playbook，经 config 中测试仓 path 读取。
