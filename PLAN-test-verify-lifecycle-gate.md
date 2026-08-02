# 集成测试生命周期验证门禁

## 三阶段职责

- design：验证验收映射、测试拓扑、fixture、SQL、配置契约和最小探针证据。
- implementation：验证测试实现、静态编译/发现、stub、计数、revision 与范围边界。
- result：验证唯一 runner 的原始报告、cleanup、证据与验收映射。

任何阶段都不自动推进授权上限；runner PASS 不等同 result PASS 或完整 Flow 完成。
