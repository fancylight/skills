# GLM 本地集成测试环境

项目清单安装到 `C:/Users/chenk-u/code/glm/.flow/test-environment.json`，入口安装到 `.flow/scripts/prepare-test-environment.ps1`。通用技能不硬编码 GLM 的容器名。清单是允许使用的已有容器，不是每次都要启动的服务清单；实际选择来自 resolved manifest 的 resources，ES、Kafka 和其他未选择的依赖不检查、不启动。

`prepare-test-environment.ps1 status -ResolvedManifestPath <路径>` 只读汇总；`ensure` 在运行授权及预算内仅允许 `docker start <已有允许容器>`。禁止 create、run、compose up、替代实例、全局 reset 和共享容器清理。检查全体选择后才开始任何启动，错误报告包含资源、原因和下一步。仅容器运行不表示业务就绪。

`flow-test.ps1 advance` 在静态环境验证前执行该入口的同一实现；新版 runtime 在启动资源与投递前再次核实。旧的项目 runner 通过新版 flow-test 编排也受约束；旧版 standalone 直调不受新版代码控制，必须升级对应 runtime 或先执行项目入口，不得声称已被技术拦截。不要覆盖业务项目定制启动器来升级框架。

配置中心使用现有 config-center。配置端点、内容指纹、服务实际配置消费、健康与消费者检查，以及 WireMock 契约注册继续由现有 runner 执行，不另造一套启动引擎。本次不自动改业务版本或重建 JAR。检查失败在原授权内修复后继续；配置选择或凭据确实缺失才询问用户。

核对时跨夜旧配置仍指向 19092 的 glm-attendance-local-kafka，本清单明确只接受 kafka-server:9092。不要为通过检查自动改配置；先确认本次链路是否实际需要 Kafka，若需要则修复既有 kafka-server 并同步真实配置，重新解析验证。huawei-*、glm-attendance-local-kafka、旧 parity-wiremock 都不属于批准环境，脚本也不删除它们。

## 环境之外的验收

- 用例是否能独立读懂输入和预期、错误实现是否也会通过，仍由业务审核负责。
- harness 内容没变时只验证已有认证；内容变化才重验，不能因为新场景或新运行目录重复认证。
- 旧预算不阻止设计和编码；运行失败修复后沿用恢复入口，不重复投递。
- 结果等待必须关联本次输入，并区分处理完成与存储可见；不能靠增加 sleep 或隐式补发。
- 报告同时保留准备、首次断言、执行及返修时间。环境准备通过不等于上述问题通过；真实完整流程仍需单独验收。

## 本轮验证（2026-09-21，自查）

项目脚本已复制到 GLM 根目录，全局技能与模板已安装。真实 Docker 只读检查约1.95秒：8个已选容器可复用，旧跨夜 Kafka 19092 与批准的9092不一致；未启动、创建、删除任何容器，也未重跑业务用例。配置中心合法构建副本不被当成错误目录，配置来源仍核对原 config-center。

PowerShell 5.1/7 回归覆盖已有环境连续复用、只读 status、仅启动既有实例、错误端口拒绝、managed 替代拒绝和未选依赖不访问。实际 runner 临时环境验证项目清单拒绝发生在资源启动及 suite 之前；controller 执行恢复与 harness 自测认证通过，24技能校验通过。

尚未验证真实 Kafka 修复、全部业务服务热复用、已有定制 standalone runner 全量升级，以及新需求从用例设计到最终交付的端到端改善。本轮没有用环境检查代替这些结论。
