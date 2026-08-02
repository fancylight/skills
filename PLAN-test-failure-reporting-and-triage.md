# 集成测试失败归因与报告闭环改进方案

## 背景

现有集成测试流程能够在 runner 失败时保留原始日志、测试报告与部分运行证据，但失败摘要常停留在“suite failed”层面。执行者必须再手工比对测试报告、服务日志、外部替身记录和 fixture，才能判断问题应由环境、测试实现、数据契约还是业务实现处理。

这会造成三个风险：

- 把外部桩、fixture 或断言错误误判为业务缺陷；
- runner 未生成或未收集原始报告时，错误地把不完整证据当成结论；
- 同一 revision 在没有新证据或新修复的前提下重复运行。

目标不是增加通用 schema 扫描或额外环境探测，而是在既有设计、验证、执行链路中，使每次失败都有最小、可审计且可行动的归因结果。

## 目标与非目标

### 目标

1. runner 无论 PASS 或 FAIL 都产出一致的原始证据索引。
2. runner FAIL 时产出结构化失败归因报告，逐项关联测试场景、测试方法、响应、首个异常与外部桩记录。
3. 将失败严格分类为配置/中间件、测试实现、数据/schema 契约、SUT 业务行为或未定性。
4. 让 verify 能验证失败证据的完整性，但不把失败 runner 伪装为 result PASS。
5. 失败后只允许基于确认归因形成新 revision；不得同 revision 盲目重跑。

### 非目标

- 不在 runner 前进行全库 schema 推断、动态 SQL 静态分析或通用数据库巡检。
- 不因失败报告自动修改业务源码、配置或测试数据。
- 不要求所有失败都自动归因为业务缺陷；证据不足必须显式标为未定性。
- 不将本地测试结果等同生产发布结论。

## 失败分类模型

| 分类 | 定义 | 最小证据 | 默认处置 |
|---|---|---|---|
| `CONFIG_INFRA` | 配置来源、端口、服务健康、中间件或连接不可用 | probe/doctor 输出、健康检查或连接错误 | 停止，等待人工修复配置或环境 |
| `TEST_HARNESS` | 测试代码、fixture、断言、WireMock、runner 或 evidence 实现错误 | test case、fixture/桩契约、对应异常 | 仅修 system-test，形成新测试 revision |
| `DATA_SCHEMA_CONTRACT` | 测试依赖的表/列/约束与服务写入策略或基线不一致 | 实际 DDL/metadata、SQL、ORM/服务调用 | 先确认权威 schema，再决定测试、迁移或业务修复 |
| `SUT_BUSINESS` | 有效输入、fixture、外部桩均成立时，SUT 行为违反已批准验收 | 场景请求/响应、首个 SUT 异常或状态断言、无副作用证据 | 进入业务 Flow 设计与修复 |
| `UNDETERMINED` | 缺少可关联的请求、日志、桩或原始测试报告 | 明确缺失项 | 只补诊断证据，不猜测修改 |

每一项必须记录 `certainty: confirmed | suspected`。只有 `confirmed` 的 SUT 业务行为才可直接作为业务修复输入。

## 设计阶段改动

### `flow-codex-test-design`

在 `test-design.md` 与 manifest 增加“失败可观测性契约”：

- 每个场景的稳定 ID；
- API 场景的请求关联字段，例如场景 header 或等价 correlation id；
- 每个外部调用的实际 Feign/HTTP method、path、query 与最小响应契约；
- Surefire/Playwright、服务日志、WireMock journal、fixture/schema 证据路径；
- 涉及数据库时，仅声明该场景实际读写表、列、约束与权威来源；
- 每个主要风险的可判定失败类别与首选证据。

`flow-codex-test-verify design` 增加检查：缺少上述契约、外部桩无法追溯到实际调用点、或没有 `UNDETERMINED` 的处理边界时，design ERROR。

## 测试实现阶段改动

### `flow-codex-test-apply`

要求实现：

1. 每个 API 请求附带稳定场景标识，服务日志或测试侧记录可据此关联。
2. WireMock mapping 精确匹配实际调用的 method/path/query；不得用相近接口替代。
3. fixture 与测试查询显式登记其读写表列；不要求扫描所有动态 SQL。
4. 失败时保留脱敏请求摘要、响应摘要、WireMock unmatched 与最小数据库快照。
5. runner、日志和报告统一使用明确编码读写，推荐 UTF-8。

静态 implementation verify 应检查场景 ID、测试方法、manifest filter、外部桩契约和报告类清单的一致性；不得在该阶段启动服务或执行 runner。

## Runner 与证据改动

### `flow-codex-system-test`

无论运行成功或失败，固定生成：

```text
changes/<change>/evidence/current/
  summary.md
  failure-report.md        # FAIL 时必需；PASS 时可省略或标明无失败
  index.md
  junit/
  logs/
  wiremock/
  db/
```

runner 失败时必须：

1. 始终收集并解析原始 Surefire/Playwright 报告；只有报告文件确实不存在时才可标记 unavailable。
2. 按测试方法列出 failures、errors、skipped 与关联场景 ID。
3. 提取对应请求的响应摘要、WireMock matched/unmatched 记录及服务日志时间窗口内的首个异常。
4. 对数据库类异常输出实际 SQL、表/列/约束与脱敏参数；禁止输出密码、token 或完整连接串。
5. 为每项生成分类、确定性、证据路径、建议动作和“是否允许修改业务代码”。
6. 保留失败证据与数据，停止后续 runner；不得自动重试。

`failure-report.md` 建议格式：

```markdown
# 集成测试失败归因

- test revision / SUT revision / manifest hash
- configuration probe / doctor 状态
- JUnit 是否实际执行
- passed / failed / errors / skipped

## 失败项

| 场景 | 测试方法 | 分类 | 确定性 | 首个证据 | 建议动作 |
|---|---|---|---|---|---|

## 未定性项

- 缺失证据
- 允许的下一步只读诊断
- 禁止的自动修复范围
```

## 验证与编排改动

### `flow-codex-test-verify`

在 result 相关检查中增加失败证据完整性分支：

- runner FAIL 时绝不输出 result PASS；
- 检查 `failure-report.md`、原始报告、计数、证据索引与日志关联是否齐全；
- 不完整时输出 `TEST_EVIDENCE_INCOMPLETE`，不允许将未知异常提升为业务结论；
- 完整时输出失败归因摘要与下一步允许的修复范围。

### `flow-codex-test`

失败闭环固定为：

```text
runner FAIL
→ 失败证据完整性验证
→ confirmed 分类决定修复归属
→ 形成新 revision
→ implementation verify
→ 新的一次 runner
```

同一 revision 不得因“想再确认一次”直接重跑。`UNDETERMINED` 只能先补诊断可观测性，再进入新的 revision。

## 实施顺序

1. 更新测试设计模板、manifest checklist 与 test verify checklist，定义失败可观测性契约。
2. 更新 runner，使其稳定收集原始报告、日志、外部桩记录并生成失败归因报告。
3. 更新 test apply/verify/test 编排 instructions，写明静态门禁、失败停止和新 revision 规则。
4. 用一个已知失败的本地测试 change 验证：报告必须能区分外部桩错配、fixture/SQL 错误、schema 契约漂移与 SUT 行为。
5. 仅在报告完整性验证通过后，将规则作为后续集成测试的硬门禁。

## 验收标准

- 任意 FAIL 运行都有可解析的原始报告或明确的“报告未产生”原因。
- `failure-report.md` 覆盖所有 failure/error，计数与原始报告一致。
- 每项都有分类、确定性、证据路径和建议动作。
- 报告不泄露敏感配置。
- 证据不足时明确 `UNDETERMINED`，不会自动创建业务修复结论。
- 同 revision 不重跑；修复后必须经过 implementation verify 才可执行下一次 runner。
