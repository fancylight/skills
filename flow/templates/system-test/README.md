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
| `config/environments/` | 测试环境 v2 descriptor 示例 |
| `scripts/system-test.ps1` | doctor / up / run / down / cleanup |
| `scripts/run-resolved-environment.ps1` | 独立的 v2 resolved manifest 生命周期验证引擎（P3） |

编排根路径：默认测试仓的父目录；可用 `-OrchRoot` 或环境变量 `FLOW_ORCH_ROOT` 覆盖。manifest 中 `${ORCH_ROOT}` / `${TEST_ROOT}` 会被展开（`${GLM_ROOT}` 为 `${ORCH_ROOT}` 别名）。

中间件（MySQL/Redis 等）与业务服务配置由项目自备，不在本骨架内。

## 测试环境 v2（P1–P3）

`config/environments/local.example.json` 是 repo 级环境描述符示例。change manifest 使用
`schemaVersion: 2` 引用 descriptor 后，可通过安装到 core assets 的
`resolve-test-environment.ps1` 生成确定性的 `resolved-manifest.json`。P1 resolver 只执行静态结构、路径、Git revision、
配置目标、资源依赖、secret 和 fingerprint 校验；`system-test.ps1` 按 manifest 版本分派 v1/v2 生命周期。

P2 的 `validate-test-environment.ps1` 在 controller `VERIFY_ENVIRONMENT` 阶段消费 resolved manifest：检查输入和 revision
漂移、环境引用、managed 启动构件/空闲端口，并只执行 external TCP/HTTP preflight probe。它不会启动 managed 资源；
PASS 报告可提交给 controller，BLOCKED 报告必须停止。

P3 的 `run-resolved-environment.ps1` 在隔离模式下消费已锁定 fingerprint 的 resolved manifest，按依赖顺序启动 managed
资源、通过显式 `identityProbe` 与健康检查复用实例（不接管）、校验 Spring Config target 的 application/profile 身份、启动 SUT 并验证声明的
`log-regex` 配置消费证据，最后同步执行 manifest runner。它只清理由本次运行创建的进程，并输出结构化 failure category。
该引擎已纳入 harness certification。`system-test.ps1` 会按 manifest `schemaVersion` 分派：v1 保持原链路，v2 强制
certification、resolved fingerprint 和 environment file 一致后调用该引擎，并生成 `evidence/runs/<run-id>/runtime-result.json` 与索引。
运行中断时，`cleanup` 根据持久化的 PID + process start time 只回收本次创建的进程。

本地配置以配置中心为唯一来源。`ownership=human` 且被配置仓 Git 忽略的文件可保留本地凭据；其他配置输入仍要求 secret reference。
完整文件摘要会绑定配置指纹，报告不保存配置值。日志先写入私有临时目录，进程停止后脱敏保存到本次证据目录。
`.env` 仅放必要运行参数，测试夹具读取 `FLOW_RESOLVED_MANIFEST` 指向的配置来源，不复制账号密码。
native profile 和 search locations 可以由启动契约传入，无须在固定提交的服务源码添加 application-native 文件。
外部中间件必须使用 `lifecycle=external`，runner 只探测连接；managed 能力仅用于项目明确授权的资源。
`runner.prepare`、`runner.cleanup` 可声明 token-array 命令；prepare 在 SUT 启动前注册并验证本次 WireMock mappings，失败立即阻断，cleanup 仅清理本次夹具。
prepare 以退出码 78 表示配置、基础设施或存储 schema 前置不满足，runner 归为 CONFIG_INFRA/BLOCKED；其他非零退出归为 TEST_HARNESS。具体首个失败响应由 prepare 保存到本次 evidence。
SUT 的 `id` 对应其 configuration target `application`，加载证据按服务关联。单服务启动默认最多 120 秒，suite 默认最多 600 秒；启动适配器必须同步等待子进程以保持所属进程树。

独立选择场景：`system-test.ps1 run -Change <change> -ScenarioIds SMOKE-1`。仅 v2 standalone 支持；从 `testCasesContract.path` 指向的 canonical 派生契约生成精确 class#method 过滤器。
runner 命令通过 `${FLOW_TEST_FILTER}` 和 `${FLOW_TEST_REPORT_DIR}` 消费过滤器及本次 JUnit 目录。空选集、未知 ID、源文件漂移、缺报告、零匹配、越界报告或 skipped 都失败。
结果明确 `fullSuite=false`，不能登记成全量 Flow PASS，也不能覆盖旧全量证据或 controller 状态。

旧 manifest 迁移使用 `migrate-test-environment-manifest.ps1` 和人工审核的 migration spec。迁移器只写新文件、不覆盖旧
manifest；保留 test-cases/suite 等非环境字段，把旧 `configuration.source/ownership` 映射为 v2，并拒绝猜测 provider、SUT、
evidence 或 runner 契约。
