# Runner 命令契约

命令均在 **glm-system-test** 仓库根目录执行（路径从根 `.flow/config.yaml` 的 `glm-system-test` 条目解析）。

```powershell
.\scripts\system-test.ps1 doctor -Change <change> -EnvFile .env.local
.\scripts\system-test.ps1 run -Change <change> -Suite <suite> -EnvFile .env.local
.\scripts\system-test.ps1 cleanup -Change <change> -EnvFile .env.local
```

`<suite>` 默认 manifest 的 `defaultSuites` 首项或 `api`。

## 证据路径

| 类型 | 路径（相对 glm-system-test） |
|------|------------------------------|
| 运行时状态与日志 | `.runtime/<change>/` |
| Playwright | `.runtime/playwright-report/` |
| JUnit | `backend-tests/target/surefire-reports/` |
| 可提交摘要 | `changes/<change>/evidence/summary.md` |
| 根镜像 | `.flow/changes/<change>/集成测试.md`（编排根） |

禁止将 secrets、cookies、token、数据库密码写入 evidence。

## 发版 SQL 变更后重测

register 提交或 integration 窗口内重跑 release SQL 时：

1. 确认 `fixtures/release/` 与服务仓 SQL 一致。
2. 本地 DB 重跑变更脚本后再声称 green。
3. 重启受影响服务（至少 register；Feign/鉴权变更含 agg）。
4. 跑 manifest `apiTestFilter` 冒烟；R30/projectAudit 等未覆盖项须明示。

详见 `references/local-pitfalls.md` 与 glm-system-test `docs/local-integration-playbook.md`。
