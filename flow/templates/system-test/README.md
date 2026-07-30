# Flow System Test

由 `flow-codex-test-design` 从 Flow skills 模板初始化的集成测试框架仓。

通过 manifest 启动被测服务、执行 SQL fixtures、运行 API（及可选 UI/CDC）套件，并收集 evidence。

## 快速入口

```powershell
Copy-Item .env.example .env.local
# 按项目填写中间件与服务 URL 后：
.\scripts\system-test.ps1 doctor -Change <change> -EnvFile .env.local
.\scripts\system-test.ps1 run -Change <change> -Suite api -EnvFile .env.local
```

## 目录约定

| 路径 | 说明 |
|------|------|
| `changes/<change>/manifest.yaml` | 执行拓扑（JSON 内容；扩展名历史兼容） |
| `changes/<change>/test-plan.md` | 验收映射与跑法 |
| `backend-tests/` | JUnit API 测试（`flow-codex-test-apply` 编写） |
| `test-support/` | FixtureTool 等共享工具 |
| `config/services/` | 各服务 system-test 环境契约（按需） |
| `scripts/system-test.ps1` | doctor / up / run / down / cleanup |

编排根路径：默认测试仓的父目录；可用 `-OrchRoot` 或环境变量 `FLOW_ORCH_ROOT` 覆盖。manifest 中 `${ORCH_ROOT}` / `${TEST_ROOT}` 会被展开（`${GLM_ROOT}` 为 `${ORCH_ROOT}` 别名）。

中间件（MySQL/Redis 等）与业务服务配置由项目自备，不在本骨架内。
