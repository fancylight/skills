# Flow 配置中心 P5 GLM Shadow Pilot 报告

> 日期：2026-08-12  
> 结论：结构验证 PASS；真实配置安全门禁 BLOCKED；未执行真实服务、数据库或业务测试。

## 1. 验证边界

本轮只读检查 `C:\Users\chenk-u\code\glm`，并在 `C:\fp5-*` 临时本地 clone 中运行 resolver。未修改、提交或启动以下真实仓：

| 角色 | 仓 | 读取到的 HEAD | 工作区状态 |
|---|---|---|---|
| Config Server 实现 | `config-center` | `87382a9c95dff2840a6317710e0957d19e1dfcb4` | dirty（1 项） |
| 配置内容 | `config` | `00ad642b0d101e4f5ba0d5a9752b39c9741353ad` | dirty（1 项） |
| SUT | `worker-service` | `214c905b9938ed4b2cc39ace9067781865851f6b` | dirty（2 项） |
| 测试平台 | `glm-system-test` | `5d35262751c73f57673f2c093263681a6e573776` | dirty（7 项） |

由于存在未确认工作区改动，P5 不生成真实仓产物，不把本轮结果记录为 canonical Flow run。

## 2. 真实结构发现

GLM 不是原设计中单仓 `spring-config-native` 结构，而是：

```text
config-center (Spring Config Server 实现仓)
  └─ git backend
       └─ config (配置内容仓，release-v2.0.0)
            └─ test/worker-service-test.yml
```

只读结构检查确认：

- `config-center` 包含 Maven 构建与 `@EnableConfigServer`；
- provider 配置使用 Spring Config git backend；
- 配置目标为 `config/test/worker-service-test.yml`；
- `glm-system-test` 已有 worker 启动 adapter；
- `worker-service` 是 Maven SUT。

因此 v2 契约已扩展为分别锁定：

- provider service repository + revision；
- configuration content repository + revision；
- SUT repository + revision；
- system-test revision 继续由 controller 单独锁定。

## 3. Shadow 场景结果

| 场景 | 结果 | 证据/解释 |
|---|---|---|
| 原始 committed snapshot | BLOCKED | `ERROR_SECRET_INPUT` |
| 临时 clone 中仅把敏感值替换为 `${SHADOW_REFERENCE}` | PASS | resolver 生成双仓 revision 与 fingerprint |
| 启动 Config Server | 未执行 | 本轮仅结构 shadow |
| 启动 worker-service | 未执行 | 真实工作区 dirty，且配置尚未引用化 |
| 数据库/Redis/WireMock 联通 | 未执行 | 不在只读 shadow 授权范围 |
| 业务集成测试 | 未执行 | 不能用结构 PASS 代替 runtime PASS |

临时脱敏 snapshot 的 resolver 证据：

```text
providerRevision: 87382a9c95dff2840a6317710e0957d19e1dfcb4
configurationRevision: 3accffb2c6f4befacbaff503368241c6e16cb0bd
sutRevision: 214c905b9938ed4b2cc39ace9067781865851f6b
configurationFingerprint: 408c8cb96f1c3a0b5fe5e802706f3012a89b522da82eedba895a2eb65aab6755
```

`configurationRevision` 是临时 clone 替换敏感值后产生的隔离 revision，不属于真实 `config` 仓，不得用于发布或 canonical run。

## 4. 发现的问题

1. 原 resolver 把 Config Server 实现仓与配置内容仓合并建模，无法表达 GLM git backend；现已修正为双仓契约，并保留 native 单仓兼容。
2. YAML secret 检查原先未覆盖 `appSecret`、`secret-key`，且 CRLF 行尾会造成漏检；现已补充回归。
3. `config/test/worker-service-test.yml` 只读扫描发现 3 个敏感键且未使用环境引用；真实 resolver 必须阻断。
4. `worker-service/src/main/resources/application-dev.yml` 只读扫描发现更多敏感键；它不能作为 v2 配置 target 或 evidence 输入。
5. 四个真实仓都有未提交内容，不能建立可发布、可复现的 canonical fingerprint。

报告不记录任何敏感配置值。

## 5. 真实 runtime pilot 前置条件

只有以下条件全部满足，才能继续 P5 runtime：

1. 人工确认四个仓的目标 branch/revision，并处理或明确允许 dirty overlay；
2. 在 `config` 仓建立不含明文敏感值的 system-test 配置 revision，敏感项全部改为受支持的引用；
3. 在 system-test 仓提交 v2 descriptor、manifest、resolved manifest、provider start adapter、SUT consumption evidence contract；
4. Config Server 本地启动契约明确使用测试配置内容仓，不访问或修改远程配置仓；
5. P2 environment verifier PASS，并由 controller 锁定同一 fingerprint；
6. 另行取得 execution 授权后，才允许启动 provider/SUT 和执行只读联通或业务 fixture 测试。

当前可声明的是“Flow v2 模型能够表达 GLM 真实配置中心结构”；不能声明“GLM 集成测试已经跑通”。
