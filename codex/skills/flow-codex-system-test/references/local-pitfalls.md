# 本地集成常见卡点

执行前读取 config 解析出的 system-test 仓内 `docs/local-integration-playbook.md`，端口、数据范围、鉴权和接口契约以该项目已批准计划为准。

## 启动与配置

1. v2 固定 manifest、resolved fingerprint、harness certification 与 SUT revision，先配置中心和替身，后业务服务。
2. 配置中心 bootstrap URI、application name、profile 必须在远程配置拉取前传入；验证每个服务加载了自己的 dev 配置。
3. 端口占用时核对身份，无法确认就阻断，不杀未知进程或自动换端口。IDEA 与 runner 不同时管理同一服务。
4. 外部 Docker 中间件只探测，不自动 Compose、启动、停止或重建。
5. WireMock 先验证方法、路径、参数、鉴权与响应结构；本次 mapping 注册失败不进入业务用例，禁止全局 reset。

## 失败归因顺序

1. 服务 health → 2. SQL/sequence/夹具 → 3. Feign/WireMock → 4. 鉴权 → 5. 业务断言。

## 数据与重试

- 只新增 manifest 预留范围内的数据，存在 ID 冲突就停止。仅在计划明确授权后执行 release-sql；禁止业务 DDL 的 smoke 遇到缺失 schema 时报告阻断。
- 共同前置失败保存首个失败步骤与脱敏原始响应，不重复跑全套。只修本次获准的配置或测试范围，输入未改变不重跑。
- 鉴权凭据从同一配置中心获取，不新增第二份手填账号，不向 evidence 输出 token、cookie 或完整配置。
- 独立选场景必须 `fullSuite=false`；缺报告、零匹配或 skipped 不能通过，保留旧全量失败证据和控制状态。

## 禁止

- 未确认服务 down 就改业务代码。
- runner 与 IDEA 同时占用同一服务端口。
- 把 `seed-fixture.sql` 当作测试环境发版 SQL。
