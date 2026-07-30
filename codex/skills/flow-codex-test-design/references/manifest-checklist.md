# manifest 与 test-plan 检查清单

`flow-codex-test-design` 产出须满足以下项。blocked 任一项则 `[TEST_DESIGN_RESULT] BLOCKED`。

测试仓路径来自 config（`type: system-test` 等）；若仓不存在须先按 `scaffold.md` 初始化。

## manifest.yaml

| 字段 / 节 | 要求 |
|-----------|------|
| `changeName` | 与 Flow change 目录名一致 |
| `sourceFlowPath` | 指向 `.flow/changes/<change>` |
| `apiTestFilter` | Maven `-Dtest=` 过滤表达式；必需用例不得永久 skip |
| `services[]` | 被测服务：端口、`healthUrl`、启动命令、`environment` |
| `services[].note` | Feign/Ribbon/VM 关键覆盖说明 |
| `data.seeds[]` | 发版 SQL + align + seed-fixture 顺序固定 |
| `data.cleanups[]` | 仅清预留 ID 段 |
| `dependencies[]` | mysql/redis/wiremock 等与 suite 对齐 |
| `requiredEnvBySuite` | api/e2e 等 suite 所需 env 变量列表 |
| `composeProfiles` | 如 wiremock |
| `cleanupPolicy` | success/failure 行为 |

## test-plan.md

| 节 | 要求 |
|----|------|
| 验收映射 | 每条纳入集成的验收 ID ↔ 测试类/方法 ↔ 阶段 |
| 分期 | S0 库准备、S1…Sn 服务叠加（可写在 manifest `phase` / `phaseNote`） |
| Non-Goals | 明确不测项（如 datacenter、腾讯真回调） |
| 跑法 | `system-test.ps1 doctor/run` 或等价命令 |
| SQL 计划验证（有数据访问契约风险时） | 每行含查询入口、代表性参数、最终列表 SQL 与分页 count SQL、只读 `EXPLAIN` 命令/数据源、验收阈值、evidence 路径；缺任一项即 BLOCKED |

## test-design.md

| 节 | 要求 |
|----|------|
| 鉴权 | Redis key/JWT/header 约定（若 agg/BFF 涉及） |
| WireMock | mapping 列表或 stub 路径 |
| IDEA VM | 手工起服时的必填 JVM 参数（若 runner 未 managed） |
| 故障归因 | 先 doctor/health/SQL/环境，再改业务（引用 playbook） |

## fixtures

- `IDS.md`：预留 tenant/project/worker 等 ID 表
- `seed-fixture.sql`：幂等（先 DELETE 预留 ID 再 INSERT）
- `fixtures/release/`：本需求发版 SQL 副本，顺序与 manifest seeds 一致

## 根 task.md

- 开发顺序含 `st-api-<change>（{system_test_service}，依赖 …）`
- `## {system_test_service}` 章节含对应 spec 条目（服务名与 config 一致）
