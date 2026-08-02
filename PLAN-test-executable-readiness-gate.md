# 运行前可执行性检查的收口决策

## 决策

不新增独立运行前 skill。环境、fixture、命令和计数规则按职责并入 design / implementation verify，真实运行问题由唯一 runner 产出证据。

## 原则

- 配置来源及最小只读探针属于 design 契约。
- WireMock、fixture、命令 token 与计数属于 implementation 静态验证。
- 真实 API、数据库和 runner 行为只在 execution 授权后的单次 runner 中判断。
- 任何失败均停止并分类；不得以额外预检、自动修复或重复 runner 扩张流程。
