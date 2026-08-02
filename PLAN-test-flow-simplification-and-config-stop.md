# 集成测试 Flow 收口与配置停止

## 目标

集成测试采用“配置契约 → 一次最小只读探针 → design verify → implementation verify → 单次 runner → result verify”。
不设独立运行前 skill 或 READY 凭据。

## 规则

- manifest 在 design 时声明 `configurationSource`、`requiredEndpoints`、`connectivityProbe`、`ownership`。
- probe 只对用户确认的来源执行一次只读连接或 metadata 检查；失败输出 `[TEST_CONFIGURATION] BLOCKED` 和 `STOP_AWAIT_HUMAN_CONFIGURATION`。
- implementation verify 承担静态计数、fixture、stub、命令 token 和路径检查；不得连接环境或启动服务。
- runner 仅在 implementation PASS、execution 授权、配置探针成功且 revision 一致时执行一次。
- runner 失败分类为环境、外部桩、fixture/断言或业务行为；均停止，不自动修配置、测试或业务仓。

## 验收

- 配置失败后无写入、无重试、无来源切换。
- implementation PASS 前的启动型命令被拒绝。
- runner 失败不重跑，result PASS 前不更新完成状态。
