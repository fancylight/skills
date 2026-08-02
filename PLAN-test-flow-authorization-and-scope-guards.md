# 集成测试授权与范围门禁

## 目标

以用户授权阶段上限、唯一测试仓路径白名单、命令能力和不可重置审核轮次约束测试 Flow。

## 规则

- `testAuthorization.ceiling` 默认 `design`；仅用户可提升，`next` 从不构成授权。
- design 只写设计产物；apply 只写 config 中 `type: system-test` 的服务；所有跨仓写入、测试和提交都输出 `BLOCKED_SCOPE_VIOLATION`。
- implementation PASS 前只允许静态校验；外部证据缺失统一输出 `TEST_EXTERNAL_EVIDENCE BLOCKED`。
- review identity 固定，三轮 REJECT 后停止；revision、agent 或基线变化不能清零计数。
- artifact guard 拒绝工具输出污染、危险 fixture SQL 和不受约束 cleanup。

## 验收

design 授权不能派发实现；实现阶段不能启动服务；外部证据不能扩大为业务改动；任何 stale agent 均不能恢复。
