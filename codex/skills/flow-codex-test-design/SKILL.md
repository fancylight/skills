---
name: flow-codex-test-design
description: 在业务代码已审核提交后，基于概要设计验收、as-built revision 和本地环境设计可独立实施的 Flow 集成测试。产出 test-design、test-plan、manifest 与 fixtures 契约，不编写 JUnit。
---

# Codex Flow 集成测试设计

作为根编排 agent 执行。读取 `../flow-codex-core/references/platform.md`、
`references/manifest-checklist.md`、`references/scaffold.md` 和已安装模板中的
`test-design.md.tmpl`、`test-plan.md.tmpl`。

## 硬前置与输入

1. 要求根角色为 `orchestrator` 与明确的 `change_name`。
2. 所有纳入范围的业务 spec 已完成 review、单元测试和提交；`flow-codex-verify` 全量 §A+§B 无 ERROR。
3. 每个 SUT 记录仓库、期望分支、commit、启动模块和配置；未提交业务代码不得作为基线。
4. 读取概要设计验收、操作链路、数据访问契约、OpenSpec/as-built、单元测试结果、本地 playbook 和现有
   system-test 支撑。不得读取本需求已写集成测试代码反推设计。
5. 关键中间件、数据、鉴权、外部依赖替身或观测能力无法盘点时 BLOCKED。

## 步骤

0. 按 `scaffold.md` 解析或初始化 config 中的 system-test 仓；已存在完整仓时只增量更新 change 产物。
1. 为概要设计每条验收分配稳定 `AC-n`，确定集成 Y/N、Non-Goal 或后续阶段；N 不得伪装为覆盖。
2. 设计并写入 `test-design.md`：完整覆盖 TDD.1–TDD.10（目标与风险、SUT revision、拓扑、真实/桩边界、
   鉴权、夹具、观测点、覆盖策略、SQL、失败归因）。
3. 写入 `test-plan.md` 场景矩阵：每个 Y 验收映射至 `AC-n-Sn`、required/optional、测试类和方法、准备数据、
   操作、响应、文件/Excel、数据/副作用、清理和 suite。正向能力缺 happy path，或“未写入”缺观测，均 BLOCKED。
4. 由设计推导 manifest、IDS、幂等 seed/cleanup、环境契约及必要 release SQL 镜像；manifest 不得承担覆盖论证。
5. 数据访问风险必须在 plan 中列最终列表 SQL/count、代表性参数、只读 EXPLAIN 命令/阈值/evidence 路径；不可得则 BLOCKED。
6. 在根 task 创建 st-api 条目和“集成测试设计 READY”待验证状态；不得因自身 READY 勾选为通过。

禁止写 JUnit、修改业务源码，或在 design/plan 中写实际 PASS、日期、耗时、真实 EXPLAIN 与事后 evidence。

## 结果

```text
[TEST_DESIGN_RESULT] READY | BLOCKED
change_name: <name>
service_name: <system-test service name>
service_path: <absolute path>
business_revisions:
  - <repo> <branch> <commit>
acceptance: <AC count>; required_scenarios: <count>
topology: <summary>
blocked:
  - <item or none>
next: flow-codex-test-verify design
```
