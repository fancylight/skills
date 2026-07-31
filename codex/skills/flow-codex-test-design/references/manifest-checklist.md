# 集成测试三产物协议

`flow-codex-test-design` 必须产出 manifest、test-design、test-plan、IDS、seed 与 cleanup；缺任一项为
`[TEST_DESIGN_RESULT] BLOCKED`。模板为安装后 core assets 中 `test-design.md.tmpl`、`test-plan.md.tmpl`。

## test-design.md：为什么这样测

完整覆盖 TDD.1–TDD.10：测试目标/风险、SUT revision、本地拓扑、真实/替身边界、鉴权上下文、数据模型/夹具、
可观测点、验收覆盖策略、SQL 计划与失败归因。不得写实际执行结果或“复用既有约定”替代可执行内容。

## test-plan.md：测什么

每条概要设计验收有 AC ID 与 Y/N。每个 Y 至少一个场景，且给出场景 ID、必需性、类/方法、准备数据、步骤、
响应、文件、数据/副作用、清理和 suite。required 场景不得 skip；“现网不变”必须有观测字段或明确集成 N。

## manifest.yaml：怎么跑

仅记录从设计导出的 SUT working directory/revision、命令、端口、环境、dependencies、profiles、filter、seeds、
cleanups 与 cleanup policy。filter 覆盖所有 required 类；seed/cleanup 仅使用 IDS 预留范围。

## SQL 与任务

数据访问风险场景列最终列表 SQL/count、代表性参数、只读 EXPLAIN 命令、阈值和 evidence 路径。根 task 的 READY
仅表示产出完成；assign 只接受 `TEST_VERIFY_RESULT design PASS`。
